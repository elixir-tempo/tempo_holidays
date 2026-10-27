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

  alias Tempo.Holidays.{Data, DayStart, Holiday, Locale}
  alias Tempo.Interval
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
         {:ok, read} <- read_holidays(resolved.territory, subdivision, dates) do
      members =
        for {holiday, expression} <- read,
            holiday.type in types,
            member <- holiday_member(holiday, expression, read, types, dates),
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

  # A territory's holidays, each with its rule read by `Tempo.DateRule` as
  # `:dates` observes it, kept for the life of the VM: a territory, a
  # subdivision and a reading is one `:persistent_term` entry, written once.
  defp read_holidays(territory, subdivision, dates) do
    key = {__MODULE__, territory, subdivision, dates}

    case :persistent_term.get(key, nil) do
      nil -> read_and_keep(key, territory, subdivision, dates)
      read -> {:ok, read}
    end
  end

  defp read_and_keep(key, territory, subdivision, dates) do
    with {:ok, holidays} <- Data.for_territory(territory, subdivision) do
      read =
        holidays
        |> observed_entries(dates)
        |> read_each(dates)
        |> joined_year_ends()

      :persistent_term.put(key, read)
      {:ok, read}
    end
  end

  # A substitute entry gives nothing under `:gazetted`, and under
  # `:substitute` stands in for the holidays of its own type, so a selection
  # by type keeps or drops both together.
  defp observed_entries(holidays, :gazetted) do
    Enum.reject(holidays, & &1.substitute)
  end

  defp observed_entries(holidays, _dates) do
    holidays
  end

  # Each holiday with its rule read; one that reads to no date has no member.
  defp read_each(holidays, dates) do
    for holiday <- holidays,
        {:ok, expression} <- [read(holiday, holidays, dates, [])],
        match?([_ | _], RecurrenceSet.members(expression)) do
      {holiday, expression}
    end
  end

  defp read(%Holiday{} = holiday, holidays, dates, options) do
    dated = [active: holiday.active, disable: holiday.disable, enable: holiday.enable]
    replacing = replaced_by(holiday, holidays, dates)

    Tempo.DateRule.parse(
      holiday.rule,
      [observed: observed(dates)] ++ dated ++ replacing ++ options
    )
  end

  defp observed(:substitute) do
    :moved
  end

  defp observed(:gazetted) do
    :none
  end

  defp observed(:both) do
    :as_written
  end

  # Under `:substitute` the substitute entries of a holiday's type stand in
  # for it, each in its `active` windows; `Tempo.DateRule` takes those of the
  # holiday's own date.
  defp replaced_by(holiday, holidays, :substitute) do
    entries =
      for entry <- holidays, entry.substitute, entry.type == holiday.type, entry != holiday do
        {entry.rule, active: entry.active}
      end

    [replaced_by: entries]
  end

  defp replaced_by(_holiday, _holidays, _dates) do
    []
  end

  # date-holidays cannot run a period past the year end, so it writes one as
  # two dated entries under one name; they are one member here, the period
  # they describe, the 31st of December within it.
  defp joined_year_ends(read) do
    {joined, continuations} =
      Enum.map_reduce(read, [], fn {holiday, _expression} = entry, continuations ->
        case Enum.find_value(read, &continuation(entry, &1)) do
          {january, period} -> {{holiday, period}, [january | continuations]}
          nil -> {entry, continuations}
        end
      end)

    Enum.reject(joined, fn {holiday, _expression} -> holiday in continuations end)
  end

  defp continuation(
         {%Holiday{name: name, type: type} = december, december_expression},
         {%Holiday{name: name, type: type} = january, january_expression}
       )
       when december != january do
    year_end_period(single_span(december_expression), single_span(january_expression), january)
  end

  defp continuation(_december, _january) do
    nil
  end

  defp single_span(expression) do
    case Tempo.to_interval(expression) do
      {:ok, occurrences} -> one_span(IntervalSet.members(occurrences))
      {:error, _reason} -> :none
    end
  end

  defp one_span([span]) do
    {:ok, span}
  end

  defp one_span(_spans) do
    :none
  end

  # A December period that ends with the year or the day before, and a
  # January one from the 1st of the next, are the one period from the first
  # through the last.
  defp year_end_period({:ok, december}, {:ok, january}, january_holiday) do
    if year_end?(Interval.to(december), Interval.from(january)) do
      joined_period(
        Interval.new(from: Interval.from(december), to: Interval.to(january)),
        january_holiday
      )
    end
  end

  defp year_end_period(_december, _january, _january_holiday) do
    nil
  end

  defp year_end?(last, first) do
    dated_year_end?(Tempo.to_date(last), Tempo.to_date(first))
  end

  defp dated_year_end?({:ok, last}, {:ok, %Date{month: 1, day: 1} = first}) do
    Date.diff(first, last) in [1, 2]
  end

  defp dated_year_end?(_last, _first) do
    false
  end

  defp joined_period({:ok, period}, january) do
    {january, period}
  end

  defp joined_period({:error, _reason}, _january) do
    nil
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

  # A holiday is one member: its expression, tagged with the holiday's id,
  # name and type over any metadata the expression carries. A conditional
  # (a bridge, an `if is holiday` move) reads the rest of the territory as it
  # would unselected: when the type it falls on is left out, it reads those
  # holidays as its own `:falls_on` set.
  defp holiday_member(holiday, expression, read, types, dates) do
    type = conditional_type(expression)

    if is_nil(type) or type in types do
      [tagged(expression, holiday)]
    else
      carried_member(holiday, read, type, dates)
    end
  end

  defp carried_member(holiday, read, type, dates) do
    carried =
      for {other, expression} <- read,
          other.type == type,
          other != holiday,
          do: tagged(expression, other)

    holidays = Enum.map(read, &elem(&1, 0))

    case read_falling_on(holiday, holidays, dates, carried) do
      {:ok, expression} -> [tagged(expression, holiday)]
      {:error, _reason} -> []
    end
  end

  defp read_falling_on(holiday, holidays, dates, carried) do
    with {:ok, falls_on} <- RecurrenceSet.new(carried) do
      read(holiday, holidays, dates, falls_on: falls_on)
    end
  end

  # The type of the holidays a conditional is decided against.
  defp conditional_type(%Tempo{form: {:when, _member, conditions}}) do
    Enum.find_value(conditions, &condition_type/1)
  end

  defp conditional_type(_expression) do
    nil
  end

  defp condition_type({_condition, options}) do
    case Keyword.get(options, :falls_on) do
      %{type: type} -> type
      _other -> nil
    end
  end

  # A holiday of another calendar than the Gregorian says so, as a set of
  # occurrences is in one calendar: the day of an Islamic holiday beside
  # Gregorian ones is a Gregorian day, and its calendar is what is left to say
  # that its day begins at sunset (`day_start/2`).
  defp tagged(expression, %Holiday{rule: rule, name: name, type: type}) do
    metadata =
      expression
      |> Tempo.metadata()
      |> Map.merge(%{id: rule, name: name, type: type})
      |> Map.merge(calendar_metadata(expression))

    Tempo.put_metadata(expression, metadata)
  end

  defp calendar_metadata(%Tempo{calendar: Calendar.ISO}) do
    %{}
  end

  defp calendar_metadata(%Tempo{calendar: calendar}) do
    %{calendar: calendar}
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
