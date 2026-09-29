defmodule Tempo.Holidays do
  @moduledoc """
  Holidays as Tempo recurrences, for any window.

  A holiday is a *recurrence*, not a date: "Christmas is the 25th of
  December", "Thanksgiving is the fourth Thursday of November". A territory's
  holidays are a `t:Tempo.RecurrenceSet.t/0` — one member per holiday, each
  tagged with the holiday's metadata — and `Tempo.to_interval_set/2` converts
  it to the `t:Tempo.IntervalSet.t/0` of the holidays in a window, each
  occurrence tagged the same way. Because both are Tempo values, holidays
  compose with anything else through set algebra.

  The data is the [date-holidays](https://github.com/commenthol/date-holidays)
  dataset for every territory, carrying every `:type` (public holidays through
  to observances). Fixed dates and weekday-in-month holidays are ISO 8601-2
  selections (`FL12M25DN`, `FL6M1K2IN`); Easter-relative holidays are windows
  off the computed `(easter)e` event; Islamic, Hebrew and other calendar
  holidays are recurrences in their own calendar, returned in it; a holiday
  observed on its own date and a substitute day is a nested set of both; and a
  bridge day or a holiday moved off another is a conditional member
  (`Tempo.RecurrenceSet.keep_when/2`, `move_when/2`), resolved against the
  others when the set converts.

  Each holiday's metadata is `:id` (its date-holidays rule, unique within the
  set, where names repeat), `:name` and `:type`; a substitute day adds
  `substitute: true`. The set's own metadata names its territory and
  subdivision.

  The primary API is `holidays/2`, and `day_start/2` for the Islamic and Hebrew
  holidays whose day begins at sunset.

  ## Example

      {:ok, holidays} = Tempo.Holidays.holidays(:AU)
      {:ok, this_year} = Tempo.to_interval_set(holidays, within: ~o"2026")

      {:ok, clashes} = Tempo.intersection(my_diary, holidays, metadata: :merge)

  > *"Australia's **holidays** are a set of recurrences. **This year's** are the
  > days they fall on in 2026; the diary's **clashes** are its entries that fall
  > on one, each labelled with the holiday it hit."*

  """

  alias Tempo.Holidays.{Data, DayStart, Holiday, Locale, Rule}
  alias Tempo.IntervalSet
  alias Tempo.RecurrenceSet
  alias Tempo.RecurrenceSet.Conditional

  @typedoc """
  A holiday request's target: a positional CLDR territory code (atom or string,
  always a territory — never a language), a `t:Localize.LanguageTag.t/0`, or a
  keyword list carrying a `:territory` or `:locale` option.
  """
  @type target :: atom() | String.t() | Localize.LanguageTag.t() | keyword()

  @typedoc """
  The dates a holiday observed on another day is given on: `:substitute` the
  day it is observed on, `:gazetted` its own date, or `:both`.
  """
  @type dates :: :substitute | :gazetted | :both

  @typedoc """
  The category a holiday falls under, following
  [date-holidays](https://github.com/commenthol/date-holidays): a `:public`
  holiday is a statutory day off, `:bank` a banking holiday, `:school` a school
  holiday, `:optional` a day observed at the holder's discretion, and
  `:observance` a marked but non-statutory day.
  """
  @type holiday_type :: :public | :bank | :school | :optional | :observance

  @holiday_types [:public, :bank, :school, :optional, :observance]

  @dates [:substitute, :gazetted, :both]

  @options [:territory, :locale, :subdivision, :include, :exclude, :dates]

  # The calendars whose day begins at sunset, so `day_start/2` projects their
  # holidays onto the evening before.
  @sunset_calendar_types [
    :hebrew,
    :islamic,
    :islamic_civil,
    :islamic_rgsa,
    :islamic_tbla,
    :islamic_umalqura
  ]

  @doc """
  Returns a territory's holidays as a recurrence set.

  Each member is one holiday — its recurrence, a nested set of its own date and
  its substitute days, or a conditional member for a bridge day or a holiday
  moved off another — tagged with `:id`, `:name` and `:type` metadata. The
  set's own metadata names the territory, and the subdivision when one is given.
  `Tempo.to_interval_set/2` converts it to the holidays in a window.

  A period date-holidays splits over the year end, because its data cannot run
  one past it, is one member: Victoria's summer school holidays run from
  December to the end of January, 31 December included.

  A selection by type never changes a holiday's date: a kept holiday that moves
  off another (Näfelser Fahrt off Maundy Thursday, an observance) carries the
  holidays it depends on when their type is left out.

  ### Arguments

  * `target` names the territory — a positional CLDR territory code (`:AU`,
    `"AU"`, always a territory, never a language) or a `t:Localize.LanguageTag.t/0`.
    Omit it and pass the target by option instead. See `Tempo.Holidays.Locale`.

  ### Options

  * `:territory` — an explicit CLDR territory code, validated (`territory: :SA`
    is Saudi Arabia).

  * `:locale` — a BCP 47 locale identifier or `t:Localize.LanguageTag.t/0` whose
    territory is derived (`locale: "en-US-u-sd-usca"` selects California).

  * `:subdivision` — a subdivision code, the ISO 3166-2 part after the
    territory's (`"ENG"`, `"CA"`), or the whole code (`"GB-ENG"`), in place of
    a locale's `u-sd` subdivision. It names a subdivision at whichever level
    the data holds it: a state, or a region by its own code or by its path from
    its state (`"CA-LA"`, Los Angeles, where `"LA"` alone is Louisiana). See
    `Tempo.Holidays.Data.subdivision/2`.

  * `:include` — the `t:holiday_type/0` to keep, a type or a list of them. The
    default is every type.

  * `:exclude` — the `t:holiday_type/0` to leave out, a type or a list of them,
    winning over `:include`. The default is none.

  * `:dates` — the dates a holiday observed on another day is given on, when
    its own date falls on a weekend, say:

    * `:substitute` — the day it is observed on: its substitute day in place
      of its own date, so each holiday is counted once. The default.

    * `:gazetted` — its own date alone, the date its law names.

    * `:both` — its own date and its substitute day, as date-holidays gives
      them. A holiday the data moves to another day, rather than observing on
      both, is on the day it moves to.

  ### Returns

  * `{:ok, recurrence_set}` — a `t:Tempo.RecurrenceSet.t/0` of the holidays: the
    territory's, with a subdivision's own in place of the ones it redefines.

  * `{:error, reason}` — `{:unknown_territory, territory}`,
    `{:invalid_locale, target}`, `{:unknown_subdivision, subdivision}`,
    `{:ambiguous_subdivision, subdivision}`, `{:invalid_holiday_type, value}`,
    `{:invalid_dates, value}` or `{:invalid_option, option}`.

  ### Examples

      iex> {:ok, holidays} = Tempo.Holidays.holidays(:AU)
      iex> holidays |> Tempo.RecurrenceSet.members() |> Enum.map(&Tempo.metadata(&1).name) |> Enum.take(2)
      ["New Year's Day", "Australia Day"]
      iex> Tempo.RecurrenceSet.metadata(holidays)
      %{territory: "AU"}

      iex> {:ok, banking} = Tempo.Holidays.holidays(:AT, include: :bank)
      iex> banking |> Tempo.RecurrenceSet.members() |> Enum.map(&Tempo.metadata(&1).type) |> Enum.uniq()
      [:bank]

      iex> import Tempo.Sigils
      iex> {:ok, england} = Tempo.Holidays.holidays(:GB, subdivision: "ENG", exclude: :observance)
      iex> {:ok, this_year} = Tempo.to_interval_set(england, within: ~o"2026")
      iex> Tempo.IntervalSet.count(this_year)
      8

  """
  @spec holidays(target(), keyword()) :: {:ok, RecurrenceSet.t()} | {:error, {atom(), term()}}
  def holidays(target \\ [], options \\ [])

  def holidays(options, extra) when is_list(options) and is_list(extra),
    do: holiday_set(nil, extra ++ options)

  def holidays(target, options), do: holiday_set(target, options)

  defp holiday_set(target, options) do
    with :ok <- known_options(options),
         {:ok, types} <- selected_types(options),
         {:ok, dates} <- selected_dates(options),
         {:ok, resolved} <- Locale.resolve(target, options),
         {:ok, subdivision} <- Data.subdivision(resolved.territory, resolved.subdivision),
         {:ok, holidays} <- Data.for_territory(resolved.territory, subdivision) do
      members =
        holidays
        |> join_year_end_splits()
        |> observe(dates)
        |> Enum.flat_map(&holiday_member/1)

      set = RecurrenceSet.new!(members, metadata: set_metadata(resolved.territory, subdivision))
      {:ok, select_types(set, types)}
    end
  end

  defp known_options(options) when is_list(options) do
    case Enum.reject(options, &known_option?/1) do
      [] -> :ok
      [{option, _value} | _rest] -> {:error, {:invalid_option, option}}
      [other | _rest] -> {:error, {:invalid_option, other}}
    end
  end

  defp known_options(options), do: {:error, {:invalid_option, options}}

  defp known_option?({option, _value}), do: option in @options
  defp known_option?(_other), do: false

  defp selected_dates(options) do
    case Keyword.get(options, :dates, :substitute) do
      dates when dates in @dates -> {:ok, dates}
      other -> {:error, {:invalid_dates, other}}
    end
  end

  # date-holidays cannot run a period past the year end, so it writes one as two
  # entries under one name (`Tempo.Holidays.Rule.join_year_end/2`); they are one
  # member here, the period they describe.
  defp join_year_end_splits(holidays) do
    {joined, continuations} =
      Enum.map_reduce(holidays, [], fn holiday, continuations ->
        case Enum.find_value(holidays, &continuation(holiday, &1)) do
          {january, rule} -> {%{holiday | rule: rule}, [january.rule.source | continuations]}
          nil -> {holiday, continuations}
        end
      end)

    Enum.reject(joined, &(&1.rule.source in continuations))
  end

  defp continuation(
         %Holiday{name: name, type: type} = december,
         %Holiday{name: name, type: type} = january
       ) do
    case Rule.join_year_end(december.rule, january.rule) do
      {:ok, rule} -> {january, rule}
      :error -> nil
    end
  end

  defp continuation(_december, _january), do: nil

  # The dates a holiday observed on another day is given on
  # (`Tempo.Holidays.Rule.observe/3`). A substitute entry gives nothing under
  # `:gazetted`, and under `:substitute` stands in for the holidays of its own
  # type, so a selection by type keeps or drops both together.
  defp observe(holidays, :both), do: holidays

  defp observe(holidays, :gazetted) do
    for holiday <- holidays, not Rule.substitute_entry?(holiday.rule) do
      %{holiday | rule: Rule.observe(holiday.rule, :gazetted, [])}
    end
  end

  defp observe(holidays, :substitute) do
    entries = Enum.filter(holidays, &Rule.substitute_entry?(&1.rule))

    for holiday <- holidays do
      own_type = for entry <- entries, entry.type == holiday.type, do: entry.rule
      %{holiday | rule: Rule.observe(holiday.rule, :substitute, own_type)}
    end
  end

  # The holiday types a request keeps: those `:include` names, every type by
  # default, less those `:exclude` names — each a type or a list of them.
  defp selected_types(options) do
    with {:ok, included} <- holiday_types(Keyword.get(options, :include, @holiday_types)),
         {:ok, excluded} <- holiday_types(Keyword.get(options, :exclude, [])) do
      {:ok, included -- excluded}
    end
  end

  defp holiday_types(types) when is_list(types) do
    case Enum.reject(types, &(&1 in @holiday_types)) do
      [] -> {:ok, types}
      [invalid | _] -> {:error, {:invalid_holiday_type, invalid}}
    end
  end

  defp holiday_types(type) when is_atom(type), do: holiday_types([type])
  defp holiday_types(other), do: {:error, {:invalid_holiday_type, other}}

  # The members of the selected types. A kept conditional reads the rest of the
  # territory as it would unselected: when the type it falls on is left out, it
  # carries those holidays — each at its dates before any condition, as the
  # condition reads it — as its own `:falls_on` set.
  defp select_types(%RecurrenceSet{members: members} = holidays, types) do
    kept =
      for member <- members,
          member_type(member) in types,
          do: carry_dependencies(member, members, types)

    %{holidays | members: kept}
  end

  defp carry_dependencies(%Conditional{falls_on: %{type: type}} = conditional, members, types)
       when not is_struct(conditional.falls_on) do
    if type in types do
      conditional
    else
      own_id = Tempo.metadata(conditional)[:id]

      carried =
        for member <- members,
            member_type(member) == type,
            Tempo.metadata(member)[:id] != own_id,
            do: base_member(member)

      %{conditional | falls_on: RecurrenceSet.new!(carried)}
    end
  end

  defp carry_dependencies(member, _members, _types), do: member

  defp base_member(%Conditional{member: member, metadata: metadata}),
    do: RecurrenceSet.new!([member], metadata: metadata)

  defp base_member(member), do: member

  defp member_type(member), do: Tempo.metadata(member)[:type]

  # A holiday is one member: its recurrence, tagged with the holiday's id, name
  # and type over any metadata the recurrence carries (a multi-day holiday's
  # span). A rule with no recurrence has no member.
  defp holiday_member(%Holiday{rule: rule, name: name, type: type}) do
    case Rule.recurrence(rule) do
      {:ok, recurrence} ->
        metadata =
          Map.merge(Tempo.metadata(recurrence), %{id: rule.source, name: name, type: type})

        [Tempo.put_metadata(recurrence, metadata)]

      _needs_window_or_error ->
        []
    end
  end

  defp set_metadata(territory, nil), do: %{territory: territory}
  defp set_metadata(territory, subdivision), do: %{territory: territory, subdivision: subdivision}

  @doc """
  Projects holiday occurrences onto the evening their day begins.

  A day in Tempo is just a day: an Islamic or Hebrew holiday converts to a day
  in its own calendar, which carries no day-start convention. That calendar's
  day begins at sunset, so on the Gregorian timeline the holiday begins the
  evening before. `day_start/2` projects each occurrence dated in such a
  calendar onto the datetime interval from the boundary that begins its first
  day to the one that begins the day after its last; every other occurrence is
  left as it is.

  ### Arguments

  * `occurrences` is a `t:Tempo.IntervalSet.t/0` of holiday occurrences, as
    `Tempo.to_interval_set/2` converts the set `holidays/2` returns.

  * `day_start` is how the day begins, a `t:Tempo.Holidays.DayStart.t/0`:

    * `:midnight` — leaves the occurrences as they are.

    * `:evening` or `:sunset` — 18:00, or sunset, at the calendar's reference
      place: Mecca for an Islamic date, Jerusalem for a Hebrew one.

    * `{:evening, location}` or `{:sunset, location}` — the same at a location
      of your own, an IANA zone id (`"Asia/Kuala_Lumpur"`) or a `{longitude,
      latitude}` point.

  ### Returns

  * `{:ok, interval_set}` — the occurrences, each projected one a datetime
    interval keeping its metadata. A lazy set stays lazy.

  * `{:error, {:invalid_day_start, day_start}}` or
    `{:error, {:invalid_occurrences, occurrences}}`.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, holidays} = Tempo.Holidays.holidays(:SA, include: :public)
      iex> {:ok, this_year} = Tempo.to_interval_set(holidays, within: ~o"2026")
      iex> {:ok, evenings} = Tempo.Holidays.day_start(this_year, {:evening, "Asia/Riyadh"})
      iex> eid = Enum.find(Tempo.IntervalSet.members(evenings), &(Tempo.metadata(&1).name =~ "Eid al-Fitr"))
      iex> {:ok, begins} = Tempo.to_elixir(Tempo.Interval.from(eid))
      iex> {DateTime.to_date(begins), DateTime.to_time(begins)}
      {~D[2026-03-18], ~T[18:00:00.000000]}

  """
  @spec day_start(IntervalSet.t(), DayStart.t()) :: {:ok, IntervalSet.t()} | {:error, term()}
  def day_start(%IntervalSet{} = occurrences, day_start) do
    with {:ok, day_start} <- DayStart.validate(day_start) do
      project_day_start(occurrences, day_start)
    end
  end

  def day_start(occurrences, _day_start), do: {:error, {:invalid_occurrences, occurrences}}

  # A day is just a day until it is projected onto the Gregorian timeline. Each
  # occurrence dated in a sunset-starting calendar (Islamic, Hebrew) is
  # projected to the datetime interval that begins when its day begins, keeping
  # its metadata; every other occurrence, and `:midnight`, is left as the civil
  # day it already is. A lazy set is projected as it is walked.
  defp project_day_start(occurrences, :midnight), do: {:ok, occurrences}

  defp project_day_start(occurrences, day_start) do
    metadata = IntervalSet.metadata(occurrences)

    if IntervalSet.bounded?(occurrences) do
      occurrences
      |> IntervalSet.members()
      |> Enum.map(&project_occurrence(&1, day_start))
      |> IntervalSet.new(metadata: metadata)
    else
      projected =
        occurrences
        |> IntervalSet.walk()
        |> Stream.map(&project_occurrence(&1, day_start))

      {:ok, IntervalSet.from_stream(projected, metadata: metadata)}
    end
  end

  defp project_occurrence(interval, day_start) do
    calendar = Tempo.Interval.from(interval).calendar

    with true <- sunset_calendar?(calendar),
         {:ok, projected} <- DayStart.project(interval, calendar, day_start) do
      Tempo.put_metadata(projected, Tempo.metadata(interval))
    else
      _midnight_calendar_or_error -> interval
    end
  end

  defp sunset_calendar?(calendar) when is_atom(calendar) do
    Code.ensure_loaded?(calendar) and function_exported?(calendar, :cldr_calendar_type, 0) and
      calendar.cldr_calendar_type() in @sunset_calendar_types
  end

  defp sunset_calendar?(_calendar), do: false
end
