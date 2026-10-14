defmodule Tempo.Holidays do
  @moduledoc """
  Holidays as Tempo recurrences, for any window.

  A holiday is a *recurrence*, not a date: "Christmas is the 25th of
  December", "Thanksgiving is the fourth Thursday of November". A territory's
  holidays are a recurrence set (a `t:Tempo.t/0`) — one member per holiday, each
  tagged with the holiday's metadata — and `Tempo.to_interval/2` converts
  it to the set (a `t:Tempo.t/0`) of the holidays in a window, each
  occurrence tagged the same way. Because both are Tempo values, holidays
  compose with anything else through set algebra.

  The data is the [date-holidays](https://github.com/commenthol/date-holidays)
  dataset for every territory, carrying every `:type` (public holidays through
  to observances). Fixed dates and weekday-in-month holidays are ISO 8601-2
  selections (`FL12M25DN`, `FL6M1K2IN`); Easter-relative holidays are windows
  off the computed `(easter)e` event; Islamic, Hebrew and other calendar
  holidays are recurrences in their own calendar, which a set of occurrences
  brings to the one calendar it is in; a holiday
  observed on its own date and a substitute day is a nested set of both; and a
  bridge day or a holiday moved off another is a conditional member
  (`Tempo.RecurrenceSet.keep_when/2`, `move_when/2`), resolved against the
  others when the set converts.

  Each holiday's metadata is `:id` (its date-holidays rule, unique within the
  set, where names repeat), `:name` and `:type`; a substitute day adds
  `substitute: true`, and a holiday whose rule is in another calendar than the
  Gregorian adds `:calendar`, that calendar's module. The set's own metadata
  names its territory and subdivision.

  The primary API is `holidays/2`, and `day_start/2` for the Islamic and Hebrew
  holidays whose day begins at sunset.

  ## Example

      {:ok, holidays} = Tempo.Holidays.holidays(:AU)
      {:ok, this_year} = Tempo.to_interval(holidays, within: ~o"2026")

      {:ok, clashes} = Tempo.intersection(my_diary, holidays, metadata: :merge)

  > *"Australia's **holidays** are a set of recurrences. **This year's** are the
  > days they fall on in 2026; the diary's **clashes** are its entries that fall
  > on one, each labelled with the holiday it hit."*

  """

  alias Tempo.Holidays.{Data, DayStart, Holiday, Locale, Rule}
  alias Tempo.IntervalSet
  alias Tempo.RecurrenceSet

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
  `Tempo.to_interval/2` converts it to the holidays in a window.

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

  * `{:ok, recurrence_set}` — a recurrence set (a `t:Tempo.t/0`) of the holidays: the
    territory's, with a subdivision's own in place of the ones it redefines.

  * `{:error, reason}` — `{:unknown_territory, territory}`,
    `{:invalid_locale, target}`, `{:unknown_subdivision, subdivision}`,
    `{:ambiguous_subdivision, subdivision}`, `{:invalid_holiday_type, value}`,
    `{:invalid_dates, value}` or `{:invalid_option, option}`.

  ### Examples

      iex> {:ok, holidays} = Tempo.Holidays.holidays(:AU)
      iex> holidays |> Tempo.RecurrenceSet.members() |> Enum.map(&Tempo.metadata(&1).name) |> Enum.take(2)
      ["New Year's Day", "Australia Day"]
      iex> Tempo.metadata(holidays)
      %{territory: "AU"}

      iex> {:ok, banking} = Tempo.Holidays.holidays(:AT, include: :bank)
      iex> banking |> Tempo.RecurrenceSet.members() |> Enum.map(&Tempo.metadata(&1).type) |> Enum.uniq()
      [:bank]

      iex> import Tempo.Sigils
      iex> {:ok, england} = Tempo.Holidays.holidays(:GB, subdivision: "ENG", exclude: :observance)
      iex> {:ok, this_year} = Tempo.to_interval(england, within: ~o"2026")
      iex> Tempo.IntervalSet.count(this_year)
      8

  """
  @spec holidays(target(), keyword()) ::
          {:ok, Tempo.t()} | {:error, {atom(), term()} | Exception.t()}
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
      observed = holidays |> join_year_end_splits() |> observe(dates)

      members =
        for holiday <- observed,
            holiday.type in types,
            member <- holiday_member(holiday, falls_on(holiday, observed, types)),
            do: member

      RecurrenceSet.new(members, metadata: set_metadata(resolved.territory, subdivision))
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

  # A kept conditional reads the rest of the territory as it would unselected:
  # when the type it falls on is left out, it reads those holidays — each at
  # its dates before any condition, as the condition reads it — as its own
  # `:falls_on` set.
  defp falls_on(%Holiday{rule: %Rule{conditional: nil}}, _holidays, _types), do: []

  defp falls_on(%Holiday{rule: %Rule{conditional: %{type: type}} = rule}, holidays, types) do
    if type in types do
      []
    else
      carried =
        for holiday <- holidays,
            holiday.type == type,
            holiday.rule.source != rule.source,
            member <- base_member(holiday),
            do: member

      [falls_on: RecurrenceSet.new!(carried)]
    end
  end

  # A holiday is one member: its recurrence, tagged with the holiday's id, name
  # and type over any metadata the recurrence carries. A rule with no
  # recurrence has no member.
  defp holiday_member(%Holiday{rule: rule} = holiday, options) do
    case Rule.recurrence(rule, options) do
      {:ok, recurrence} -> [tagged(recurrence, holiday)]
      _needs_window_or_error -> []
    end
  end

  # A holiday at its dates before any condition.
  defp base_member(%Holiday{rule: rule} = holiday) do
    case Rule.base_recurrence(rule) do
      {:ok, recurrence} -> [tagged(recurrence, holiday)]
      _needs_window_or_error -> []
    end
  end

  defp tagged(recurrence, %Holiday{rule: rule, name: name, type: type}) do
    metadata = Map.merge(Tempo.metadata(recurrence), %{id: rule.source, name: name, type: type})
    Tempo.put_metadata(recurrence, metadata)
  end

  defp set_metadata(territory, nil), do: %{territory: territory}
  defp set_metadata(territory, subdivision), do: %{territory: territory, subdivision: subdivision}

  @doc """
  Projects holiday occurrences onto the evening their day begins.

  A day in Tempo is just a day: an Islamic or Hebrew holiday converts to a day
  in its own calendar, which carries no day-start convention. That calendar's
  day begins at sunset, so on the Gregorian timeline the holiday begins the
  evening before. `day_start/2` projects each occurrence of a holiday of such a
  calendar onto the datetime interval from the boundary that begins its first
  day to the one that begins the day after its last. A set of occurrences is
  in one calendar, so a holiday is told by the `:calendar` its metadata
  carries, the calendar its rule is in, and an occurrence that carries none by
  the calendar its own day is in.

  A set is of one frame, so every other occurrence becomes the civil day it
  is where the day start is read: in the zone it names, at its location, or,
  for a bare `:evening` or `:sunset`, at the reference place of the set's
  sunset holidays. Where no holiday is projected, as for a set of Gregorian
  holidays alone, every occurrence is left as it is.

  ### Arguments

  * `occurrences` is a set (a `t:Tempo.t/0`) of holiday occurrences, as
    `Tempo.to_interval/2` converts the set `holidays/2` returns.

  * `day_start` is how the day begins, a `t:Tempo.Holidays.DayStart.t/0`:

    * `:midnight` — leaves the occurrences as they are.

    * `:evening` or `:sunset` — 18:00, or sunset, at the calendar's reference
      place: Mecca for an Islamic date, Jerusalem for a Hebrew one.

    * `{:evening, location}` or `{:sunset, location}` — the same at a location
      of your own, an IANA zone id (`"Asia/Kuala_Lumpur"`) or a `{longitude,
      latitude}` point.

  ### Returns

  * `{:ok, interval_set}` — the occurrences, each projected one a datetime
    interval and each other one a day in the day start's zone, keeping their
    metadata. A lazy set stays lazy.

  * `{:error, {:invalid_day_start, day_start}}`,
    `{:error, {:invalid_occurrences, occurrences}}`, or
    `{:error, {:location_required, day_start}}` for a lazy set and a bare
    `:evening` or `:sunset`, since a set read as it is walked cannot be looked
    through for the reference place of its sunset holidays.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, holidays} = Tempo.Holidays.holidays(:SA, include: :public)
      iex> {:ok, this_year} = Tempo.to_interval(holidays, within: ~o"2026")
      iex> {:ok, evenings} = Tempo.Holidays.day_start(this_year, {:evening, "Asia/Riyadh"})
      iex> eid = Enum.find(Tempo.IntervalSet.members(evenings), &(Tempo.metadata(&1).name =~ "Eid al-Fitr"))
      iex> {:ok, begins} = Tempo.to_elixir(Tempo.Interval.from(eid))
      iex> {DateTime.to_date(begins), DateTime.to_time(begins)}
      {~D[2026-03-18], ~T[18:00:00]}

  """
  @spec day_start(Tempo.t(), DayStart.t()) :: {:ok, Tempo.t()} | {:error, term()}
  def day_start(%Tempo{} = occurrences, day_start) do
    with {:ok, day_start} <- DayStart.validate(day_start) do
      project_day_start(occurrences, day_start)
    end
  end

  def day_start(occurrences, _day_start), do: {:error, {:invalid_occurrences, occurrences}}

  # A day is just a day until it is projected onto the Gregorian timeline. Each
  # occurrence of a holiday of a sunset-starting calendar (Islamic, Hebrew) is
  # projected to the datetime interval that begins when its day begins, keeping
  # its metadata; every other occurrence, and `:midnight`, is left as the civil
  # day it already is. A lazy set is projected as it is walked.
  defp project_day_start(occurrences, :midnight), do: {:ok, occurrences}

  # A set is of one frame, so the civil days beside the projected ones are
  # days where the day start is read: in the zone it names, at its location,
  # or for a bare boundary at the reference place of the set's sunset
  # holidays, and with none of those nothing is projected (decision 41 of
  # Tempo). A set read as it is walked cannot be looked through for its
  # sunset holidays, so it is given a location.
  defp project_day_start(occurrences, day_start) do
    metadata = Tempo.metadata(occurrences)

    if Tempo.bounded?(occurrences),
      do: project_members(IntervalSet.members(occurrences), day_start, metadata),
      else: project_stream(occurrences, day_start, metadata)
  end

  defp project_members(members, day_start, metadata) do
    case DayStart.civil_zone(day_start, sunset_calendar_of(members)) do
      {:ok, zone} ->
        members
        |> Enum.map(&(&1 |> project_occurrence(day_start) |> as_day_in(zone)))
        |> IntervalSet.new(metadata: metadata)

      :none ->
        IntervalSet.new(members, metadata: metadata)
    end
  end

  defp project_stream(_occurrences, day_start, _metadata) when day_start in [:evening, :sunset],
    do: {:error, {:location_required, day_start}}

  defp project_stream(occurrences, day_start, metadata) do
    zone = DayStart.civil_zone(day_start, nil)

    projected =
      occurrences
      |> IntervalSet.walk()
      |> Stream.map(&(&1 |> project_occurrence(day_start) |> as_day_in(zone)))

    {:ok, IntervalSet.from_stream(projected, metadata: metadata)}
  end

  # The first calendar of a holiday whose day begins at sunset, if any.
  defp sunset_calendar_of(members) do
    Enum.find_value(members, fn member ->
      calendar = holiday_calendar(member)
      if sunset_calendar?(calendar), do: calendar
    end)
  end

  # A civil day, one no projection reached, as the day it is in the zone.
  defp as_day_in(occurrence, :none), do: occurrence
  defp as_day_in(occurrence, {:ok, zone}), do: as_day_in(occurrence, zone)

  defp as_day_in(occurrence, zone) when is_binary(zone) do
    if Tempo.zoned?(occurrence) do
      occurrence
    else
      case Tempo.in_zone(occurrence, zone) do
        {:ok, placed} -> placed
        {:error, _} -> occurrence
      end
    end
  end

  defp project_occurrence(interval, day_start) do
    calendar = holiday_calendar(interval)

    with true <- sunset_calendar?(calendar),
         {:ok, projected} <- DayStart.project(interval, calendar, day_start) do
      Tempo.put_metadata(projected, Tempo.metadata(interval))
    else
      _midnight_calendar_or_error -> interval
    end
  end

  # The calendar that says how an occurrence's day begins: the one its
  # holiday's rule is in, which the occurrence carries as `:calendar`, or else
  # the calendar the day itself is in. A set of occurrences is in one calendar,
  # so the day of an Islamic holiday beside Gregorian ones is a Gregorian day.
  defp holiday_calendar(%Tempo{calendar: calendar} = interval) do
    Map.get(Tempo.metadata(interval), :calendar, calendar)
  end

  defp sunset_calendar?(calendar) when is_atom(calendar) do
    Code.ensure_loaded?(calendar) and function_exported?(calendar, :cldr_calendar_type, 0) and
      calendar.cldr_calendar_type() in @sunset_calendar_types
  end

  defp sunset_calendar?(_calendar), do: false
end
