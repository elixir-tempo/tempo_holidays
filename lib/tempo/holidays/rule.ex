defmodule Tempo.Holidays.Rule do
  @moduledoc """
  A compiled holiday rule, and its projection onto a year.

  A rule is the calendar-agnostic *recurrence* behind a holiday, compiled
  from a [date-holidays](https://github.com/commenthol/date-holidays) rule
  string by `Tempo.Holidays.Compiler`. `materialise/2` projects it onto a
  concrete year, yielding the `t:Tempo.Interval.t/0` for that occurrence.

  Each `:kind` maps to the machinery that can express it: `:fixed`,
  `:weekday`, `:relative_weekday` and `:nested_weekday` (a weekday relative to
  a weekday-in-month, such as US Election Day) are Tempo-native date selections
  and arithmetic; `:easter` / `:orthodox` are computed through Calendrical's
  ecclesiastical calendar, since Easter is not expressible as an ISO 8601
  recurrence; and `:islamic`, `:hebrew` and `:persian` are materialised in
  their own calendar (Islamic via Umm al-Qura), returned as an
  `[u-ca=…]`-tagged value rather than converted to Gregorian. `:julian` is a
  fixed date in the Julian calendar (Orthodox Christmas and the like); it has
  no CLDR calendar tag, so it is converted to Gregorian.

  A rule may also carry an observed-date `t:substitute/0` — "if it falls on a
  weekend, observe it the following Monday" — as ordered clauses, each with its
  own mode (`:shift` moves the date, `:add` keeps it and adds the observed day,
  `:substitute_only` is the observed day alone); the first clause a date
  triggers fires and the rest leave it alone. Plus year conditions
  (`:from_year`/`:to_year`, even/odd `:year_parity`, and `:leap`) that gate
  whether it occurs at all.

  Finally it may carry date-holidays' occurrence-level metadata gates, applied
  to the computed dates: `:active` restricts the rule to one or more half-open
  `[from, to)` windows, `:disable` removes specific dates, and `:enable` adds
  explicit dates (a `:disable` + `:enable` pair is how the data *moves* an
  occurrence — the UK 2022 Spring bank holiday to the Jubilee Thursday).

  """

  alias Tempo.Interval

  @type kind ::
          :fixed
          | :weekday
          | :relative_weekday
          | :nested_weekday
          | :nested_after_date
          | :islamic
          | :hebrew
          | :persian
          | :julian
          | :lunisolar
          | :solar_term
          | :equinox
          | :solstice
          | :easter
          | :orthodox

  @typedoc """
  An observed-date substitution: ordered
  `{trigger_weekdays, direction, target_weekday, mode}` clauses in ISO weekday
  numbering (Monday = 1 … Sunday = 7). When a materialised date lands on one of
  a clause's trigger weekdays, that clause fires and no later clause touches the
  date; its `mode` decides what happens — `:shift` moves the holiday to the
  target weekday, `:add` keeps the original and adds the observed day, and
  `:substitute_only` yields the observed day alone (and drops the holiday when no
  clause fires). "If it falls on a weekend, take the following Monday" is
  `[{[6, 7], :next, 1, :shift}]`.
  """
  @type substitute :: [{[1..7], :next | :previous, 1..7, :shift | :add | :substitute_only}]

  @type t :: %__MODULE__{
          kind: kind(),
          month: pos_integer() | nil,
          day: pos_integer() | nil,
          count: integer() | nil,
          weekday: 1..7 | nil,
          inner_weekday: 1..7 | nil,
          direction: :before | :after | nil,
          offset: integer() | nil,
          calendar: module() | nil,
          leap_month: boolean() | nil,
          timezone: String.t() | nil,
          substitute: substitute() | nil,
          from_year: integer() | nil,
          to_year: integer() | nil,
          year_parity: :even | :odd | nil,
          leap: :leap | :non_leap | nil,
          every_years: pos_integer() | nil,
          weekday_gate: {:only | :except, [1..7]} | nil,
          active: [{Date.t() | nil, Date.t() | nil}] | nil,
          disable: [Date.t()] | nil,
          enable: [Date.t()] | nil,
          source: String.t() | nil
        }

  @enforce_keys [:kind]
  defstruct [
    :kind,
    :month,
    :day,
    :count,
    :weekday,
    :inner_weekday,
    :direction,
    :offset,
    :calendar,
    :leap_month,
    :timezone,
    :substitute,
    :from_year,
    :to_year,
    :year_parity,
    :leap,
    :every_years,
    :weekday_gate,
    :active,
    :disable,
    :enable,
    :source
  ]

  @doc """
  Project a rule onto a Gregorian `year`, returning its occurrences as
  intervals.

  Most holidays fall exactly once a year, but a lunar-calendar holiday can
  fall zero, one or two times within a single Gregorian year — Eid al-Fitr
  fell twice in 2000 — so the result is a list, earliest first.

  ### Arguments

  * `rule` is a `t:t/0`.

  * `year` is a year-resolution Gregorian `t:Tempo.t/0` such as `~o"2026"`.

  ### Returns

  * `{:ok, [t:Tempo.Interval.t/0]}` — the holiday's spans in that Gregorian
    year, earliest first. Usually one; empty when the rule does not fall in
    the year, two for a lunar holiday that recurs within it.

  * `{:error, reason}` when the rule cannot be projected.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("12-25")
      iex> {:ok, [interval]} = Tempo.Holidays.Rule.materialise(rule, ~o"2026")
      iex> Tempo.Interval.from(interval)
      ~o"2026Y12M25D"

  """
  @spec materialise(t(), Tempo.t()) :: {:ok, [Interval.t()]} | {:error, term()}
  def materialise(%__MODULE__{} = rule, %Tempo{} = year) do
    with {:ok, occurrences} <- gather_occurrences(rule, year) do
      move_disabled(occurrences, rule, year)
    end
  end

  # Gather the occurrences before the `disable`/`enable` post-step. The common
  # case is a single year; a substituted rule that could cross the Gregorian
  # year boundary is materialised across the target year and its neighbours and
  # filtered back to the target.
  defp gather_occurrences(rule, year) do
    target = Tempo.year(year)

    case boundary_years(rule, target) do
      [_only] ->
        occurrences_for_year(rule, year)

      years ->
        with {:ok, groups} <- reduce_ok(years, &occurrences_for(rule, &1)) do
          {:ok, groups |> List.flatten() |> Enum.filter(&in_gregorian_year?(&1, target))}
        end
    end
  end

  # A substitution can push an observed date across the Gregorian year boundary
  # — New Year on a Saturday observed the previous Friday, 31 December — and
  # date-holidays attributes each observed date to the year it falls in. So a
  # substituted rule is materialised across the target year and its two
  # neighbours and then filtered to the target; an unsubstituted rule, whose
  # base always lands in its own year, needs only the target year.
  defp boundary_years(%__MODULE__{substitute: substitute}, target)
       when substitute in [nil, []],
       do: [target]

  defp boundary_years(rule, target) do
    if boundary_capable?(rule), do: [target - 1, target, target + 1], else: [target]
  end

  # A substitution shifts a date by at most a week, so it can only cross a
  # Gregorian year boundary when the holiday itself falls within a week of 1
  # January or 31 December. A fixed or weekday rule whose month is February
  # through November never can; Easter is always spring; everything else
  # (January/December, and calendars whose Gregorian date drifts year to year)
  # is treated conservatively as boundary-capable.
  defp boundary_capable?(%__MODULE__{kind: kind}) when kind in [:easter, :orthodox], do: false

  defp boundary_capable?(%__MODULE__{kind: kind, month: month})
       when kind in [:fixed, :weekday, :nested_weekday, :relative_weekday] and is_integer(month),
       do: month in [1, 12]

  defp boundary_capable?(_rule), do: true

  # A neighbouring year, built from its integer, for the boundary case.
  defp occurrences_for(rule, year_int) do
    with {:ok, year} <- Tempo.from_iso8601(Integer.to_string(year_int)) do
      occurrences_for_year(rule, year)
    end
  end

  # The per-year gates: the year conditions, active windows, weekday gate and
  # substitution. `disable`/`enable` are a separate post-step (see
  # `move_disabled/3`) applied once to the gathered occurrences.
  defp occurrences_for_year(rule, year) do
    if active_in_year?(rule, Tempo.year(year)) do
      with {:ok, base} <- materialise_base(rule, year) do
        base
        |> filter_active(rule.active)
        |> gate_by_weekday(rule.weekday_gate)
        |> substitute_all(rule.substitute)
      end
    else
      {:ok, []}
    end
  end

  defp in_gregorian_year?(interval, target) do
    case occurrence_days(interval) do
      {:ok, days} -> Date.from_gregorian_days(days).year == target
      :error -> false
    end
  end

  # `on <weekday>` keeps an occurrence only when it lands on one of those
  # weekdays; `not on <weekday>` drops it when it does.
  defp gate_by_weekday(intervals, nil), do: intervals

  defp gate_by_weekday(intervals, {mode, weekdays}) do
    Enum.filter(intervals, fn interval ->
      weekday = Tempo.day_of_week(Interval.from(interval), :monday)

      case mode do
        :only -> weekday in weekdays
        :except -> weekday not in weekdays
      end
    end)
  end

  # ── occurrence-level metadata gates: active / disable / enable ──────
  #
  # date-holidays' `active`, `disable` and `enable` metadata operate on the
  # rule's *computed* dates (see the upstream `docs/specification.md`), so they
  # are applied to the materialised occurrences, not gated at the year level.

  # `disable`/`enable` are a *move*, mirroring date-holidays' `PostRule.disable`:
  # only when a `disable` date equals a computed occurrence is that occurrence
  # dropped and the year's `enable` dates added in its place. A `disable` that
  # matches nothing — or an `enable` with no matching `disable` — does nothing.
  defp move_disabled(occurrences, %__MODULE__{disable: disable}, _year)
       when disable in [nil, []],
       do: {:ok, occurrences}

  defp move_disabled(occurrences, rule, year) do
    blocked = MapSet.new(rule.disable, &date_days/1)
    {matched, survivors} = Enum.split_with(occurrences, &disabled?(&1, blocked))

    if matched == [], do: {:ok, survivors}, else: append_enabled(survivors, rule.enable, year)
  end

  defp disabled?(interval, blocked) do
    case occurrence_days(interval) do
      {:ok, days} -> MapSet.member?(blocked, days)
      :error -> false
    end
  end

  # `active` restricts the rule to one or more half-open `[from, to)` windows;
  # an occurrence whose date falls outside every window is dropped.
  defp filter_active(intervals, nil), do: intervals

  defp filter_active(intervals, ranges) do
    Enum.filter(intervals, fn interval ->
      case occurrence_days(interval) do
        {:ok, days} -> Enum.any?(ranges, &within_range?(days, &1))
        :error -> false
      end
    end)
  end

  defp within_range?(days, {from, to}) do
    (is_nil(from) or days >= date_days(from)) and (is_nil(to) or days < date_days(to))
  end

  # `enable` adds explicit observed dates — the target of a disable/enable move
  # — materialised as single days, keeping only those in the requested year.
  defp append_enabled(intervals, nil, _year), do: {:ok, intervals}

  defp append_enabled(intervals, enabled, year) do
    target = Tempo.year(year)

    with {:ok, added} <-
           enabled |> Enum.filter(&(&1.year == target)) |> reduce_ok(&enabled_interval/1) do
      {:ok, intervals ++ added}
    end
  end

  defp enabled_interval(%Date{} = date) do
    date |> Tempo.from_elixir() |> Tempo.to_interval() |> first_interval()
  end

  # An occurrence's date as a proleptic-Gregorian day count, so a value in any
  # calendar (an Islamic or Hebrew holiday) compares with the Gregorian
  # `active`/`disable` dates. `:error` when the value will not convert.
  defp occurrence_days(interval) do
    with tempo <- Interval.from(interval),
         {:ok, date} <- Tempo.to_date(tempo),
         {:ok, iso} <- Date.convert(date, Calendar.ISO) do
      {:ok, Date.to_gregorian_days(iso)}
    else
      _ -> :error
    end
  end

  defp date_days(%Date{} = date), do: Date.to_gregorian_days(date)

  # A `since <year>` / `prior to <year>` window, an even/odd-year filter, and a
  # leap/non-leap-year filter each gate the whole rule: when the year fails any
  # of them the holiday does not occur, so it materialises to nothing.
  defp active_in_year?(%__MODULE__{} = rule, year) do
    in_year_range?(rule.from_year, rule.to_year, year) and
      matches_parity?(rule.year_parity, year) and
      matches_leap?(rule.leap, year) and
      matches_every?(rule.every_years, rule.from_year, year)
  end

  defp matches_every?(nil, _from, _year), do: true
  defp matches_every?(n, from, year), do: rem(year - (from || year), n) == 0

  defp in_year_range?(from, to, year) do
    (is_nil(from) or year >= from) and (is_nil(to) or year < to)
  end

  defp matches_parity?(nil, _year), do: true
  defp matches_parity?(:even, year), do: rem(year, 2) == 0
  defp matches_parity?(:odd, year), do: rem(year, 2) == 1

  defp matches_leap?(nil, _year), do: true
  defp matches_leap?(:leap, year), do: Calendar.ISO.leap_year?(year)
  defp matches_leap?(:non_leap, year), do: not Calendar.ISO.leap_year?(year)

  defp materialise_base(
         %__MODULE__{kind: :fixed, month: month, day: day, count: count},
         %Tempo{} = year
       ) do
    with {:ok, selector} <- Tempo.from_iso8601(month_day(month, day)),
         {:ok, set} <- Tempo.select(year, selector),
         {:ok, interval} <- first_interval(set) do
      {:ok, [span_days(interval, Interval.from(interval), count)]}
    end
  end

  defp materialise_base(%__MODULE__{kind: :weekday} = rule, %Tempo{} = year) do
    with {:ok, recurrence} <- Tempo.from_iso8601(weekday_iso(rule)),
         {:ok, set} <- Tempo.to_interval(recurrence, bound: year) do
      case first_interval(set) do
        {:ok, interval} -> {:ok, [interval]}
        {:error, :no_occurrence} -> overflow_weekday(rule, year)
      end
    end
  end

  defp materialise_base(
         %__MODULE__{kind: :relative_weekday, weekday: target, direction: direction} = rule,
         %Tempo{} = year
       ) do
    with {:ok, anchor} <-
           Tempo.from_iso8601("#{Tempo.year(year)}-#{month_day(rule.month, rule.day)}") do
      shift =
        relative_shift(direction, Tempo.day_of_week(anchor, :monday), target, rule.count || 1)

      anchor
      |> Tempo.shift(day: shift)
      |> Tempo.to_interval()
      |> first_interval()
      |> wrap_one()
    end
  end

  # A nested weekday — "friday after 4th thursday in November" (Black Friday),
  # "Tuesday after 1st Monday in November" (US Election Day) — first places the
  # inner weekday-in-month, then steps to the outer weekday relative to it.
  defp materialise_base(
         %__MODULE__{kind: :nested_weekday, weekday: outer, inner_weekday: inner} = rule,
         %Tempo{} = year
       ) do
    inner_iso = "R/../P1Y/FL#{rule.month}M#{rule.count}I#{inner}KN"

    with {:ok, recurrence} <- Tempo.from_iso8601(inner_iso),
         {:ok, set} <- Tempo.to_interval(recurrence, bound: year),
         {:ok, inner_interval} <- first_interval(set) do
      anchor = Interval.from(inner_interval)
      shift = relative_shift(rule.direction, Tempo.day_of_week(anchor, :monday), outer, 1)

      anchor
      |> Tempo.shift(day: shift)
      |> Tempo.to_interval()
      |> first_interval()
      |> wrap_one()
    end
  end

  # "monday after 3rd sunday after 09-01": the Nth inner weekday on or after a
  # fixed date, then the outer weekday after that. Both steps use the inclusive
  # "after" that date-holidays applies.
  defp materialise_base(
         %__MODULE__{kind: :nested_after_date, weekday: outer, inner_weekday: inner} = rule,
         %Tempo{} = year
       ) do
    with {:ok, anchor} <-
           Tempo.from_iso8601("#{Tempo.year(year)}-#{month_day(rule.month, rule.day)}") do
      inner_date =
        Tempo.shift(anchor,
          day: relative_shift(:after, Tempo.day_of_week(anchor, :monday), inner, rule.count)
        )

      outer_shift = relative_shift(:after, Tempo.day_of_week(inner_date, :monday), outer, 1)

      inner_date
      |> Tempo.shift(day: outer_shift)
      |> Tempo.to_interval()
      |> first_interval()
      |> wrap_one()
    end
  end

  # A non-Gregorian-calendar holiday (Islamic, Hebrew, Persian) is calculated
  # and returned in its own calendar, per Tempo's calendar-awareness — not
  # converted to Gregorian. `year` is the *Gregorian* year, and `Calendrical`'s
  # `dates_in_gregorian_year/3` finds which occurrences of the calendar date
  # fall in it — zero, one, or (for a lunar date, as Eid al-Fitr in 2000) two.
  # A `count` greater than one spans that many days (the `P<n>D` form).
  defp materialise_base(
         %__MODULE__{kind: kind, calendar: calendar, month: month, day: day, count: count},
         %Tempo{} = year
       )
       when kind in [:islamic, :hebrew, :persian] do
    tag = calendar_tag(calendar)

    Tempo.year(year)
    |> calendar.dates_in_gregorian_year(month, day)
    |> reduce_ok(&calendar_interval(&1, tag, count))
  end

  # A lunisolar date — Chinese (`chinese …`) or Korean (`korean …`). date-holidays
  # writes `<month>-<leap>-<day>` in *traditional* month numbering, which drifts
  # from the calendar's ordinal months in a year carrying an intercalary month,
  # so Calendrical resolves the traditional month to a Gregorian date; that is
  # converted back into the source calendar (ordinal months) and returned
  # in-calendar (`[u-ca=chinese]`, `[u-ca=dangi]`).
  defp materialise_base(
         %__MODULE__{kind: :lunisolar, calendar: calendar} = rule,
         %Tempo{} = year
       ) do
    lunar_month = if rule.leap_month, do: {rule.month, :leap}, else: rule.month

    Tempo.year(year)
    |> calendar.gregorian_date_for_lunar(lunar_month, rule.day)
    |> lunisolar_interval(calendar, rule.count)
  end

  # A Chinese solar term — `chinese <term>-<day> solarterm`. The term index maps
  # to an ecliptic longitude (term 1 = 立春 at 315°, then every 15°), and the day
  # the sun reaches it, in China Standard Time, is the term's date; `<day>` is a
  # 1-based offset into the term. Solar, so returned as a Gregorian civil date.
  defp materialise_base(%__MODULE__{kind: :solar_term, count: term, day: day}, %Tempo{} = year) do
    longitude = rem(300 + term * 15, 360)
    start = Calendrical.Gregorian.date_to_iso_days(Tempo.year(year), 1, 1)

    moment =
      Calendrical.Lunisolar.solar_longitude_on_or_after(
        longitude,
        start,
        &Calendrical.Chinese.location/1
      )

    {term_year, term_month, term_day} =
      Calendrical.Gregorian.date_from_iso_days(trunc(moment))

    with {:ok, base} <- Tempo.from_iso8601("#{term_year}Y#{term_month}M#{term_day}D") do
      base
      |> Tempo.shift(day: day - 1)
      |> Tempo.to_interval()
      |> first_interval()
      |> wrap_one()
    end
  end

  # An equinox or solstice, its civil date in the rule's timezone (GMT when
  # none is named). Astro gives the UTC instant; a numeric offset (`+09:00`)
  # shifts it directly, a named zone (`America/Santiago`) needs the host app's
  # configured time-zone database and errors cleanly without one. `offset`
  # carries an `<n> days before/after` adjustment.
  defp materialise_base(
         %__MODULE__{kind: kind, month: month, offset: offset, timezone: timezone},
         %Tempo{} = year
       )
       when kind in [:equinox, :solstice] do
    with {:ok, utc} <- solar_event_utc(kind, month, Tempo.year(year)),
         {:ok, date} <- solar_event_date(utc, timezone),
         {:ok, base} <- Tempo.from_iso8601("#{date.year}Y#{date.month}M#{date.day}D") do
      base
      |> Tempo.shift(day: offset || 0)
      |> Tempo.to_interval()
      |> first_interval()
      |> wrap_one()
    end
  end

  # A Julian fixed date (Orthodox Christmas et al.). date-holidays writes these
  # as `julian MM-DD`; the Julian calendar has no CLDR `u-ca` tag, so each
  # occurrence is converted to Gregorian rather than returned in-calendar. A
  # single Gregorian year can hold zero, one or two, as with any calendar whose
  # year drifts against the Gregorian one.
  defp materialise_base(
         %__MODULE__{kind: :julian, month: month, day: day, count: count},
         %Tempo{} = year
       ) do
    Tempo.year(year)
    |> Calendrical.Julian.dates_in_gregorian_year(month, day)
    |> reduce_ok(&julian_interval(&1, count))
  end

  defp materialise_base(%__MODULE__{kind: kind, offset: offset, count: count}, %Tempo{} = year)
       when kind in [:easter, :orthodox] do
    base =
      easter_date(kind, Tempo.year(year))
      |> Tempo.from_elixir()
      |> Tempo.shift(day: offset || 0)

    with {:ok, interval} <- base |> Tempo.to_interval() |> first_interval() do
      {:ok, [span_days(interval, base, count)]}
    end
  end

  # One occurrence (a `t:Date.t/0` in the target calendar) becomes an interval
  # tagged with that calendar, spanning `count` days for a multi-day holiday.
  # The date's own calendar year is used, so the value stays in calendar rather
  # than being converted to Gregorian.
  defp calendar_interval(%Date{} = date, tag, count) do
    with {:ok, base} <-
           Tempo.from_iso8601("#{date.year}Y#{date.month}M#{date.day}D[u-ca=#{tag}]"),
         {:ok, interval} <- first_interval(Tempo.to_interval(base)) do
      {:ok, span_days(interval, base, count)}
    end
  end

  # One lunisolar occurrence: `gregorian_date_for_lunar/3` gives the Gregorian
  # date, which is converted into the source calendar (ordinal months) and
  # returned in-calendar, spanning `count` days.
  defp lunisolar_interval(%Date{} = gregorian, calendar, count) do
    tag = calendar_tag(calendar)

    with {:ok, in_calendar} <- Date.convert(gregorian, calendar),
         {:ok, base} <-
           Tempo.from_iso8601(
             "#{in_calendar.year}Y#{in_calendar.month}M#{in_calendar.day}D[u-ca=#{tag}]"
           ),
         {:ok, interval} <- first_interval(Tempo.to_interval(base)) do
      {:ok, [span_days(interval, base, count)]}
    end
  end

  # The UTC instant of the named event in the given Gregorian year.
  defp solar_event_utc(:equinox, 3, year), do: Astro.equinox(year, :march)
  defp solar_event_utc(:equinox, 9, year), do: Astro.equinox(year, :september)
  defp solar_event_utc(:solstice, 6, year), do: Astro.solstice(year, :june)
  defp solar_event_utc(:solstice, 12, year), do: Astro.solstice(year, :december)

  # The event's civil date in its timezone. No timezone is GMT; a numeric
  # offset shifts the UTC instant directly; a named zone goes through the host
  # app's configured time-zone database (a clean error, skipped upstream, when
  # none is configured).
  defp solar_event_date(%DateTime{} = utc, nil), do: {:ok, DateTime.to_date(utc)}

  defp solar_event_date(%DateTime{} = utc, timezone) do
    case offset_seconds(timezone) do
      {:ok, seconds} -> {:ok, utc |> DateTime.add(seconds, :second) |> DateTime.to_date()}
      :error -> named_zone_date(utc, timezone)
    end
  end

  defp named_zone_date(%DateTime{} = utc, timezone) do
    case DateTime.shift_zone(utc, timezone, Tz.TimeZoneDatabase) do
      {:ok, local} -> {:ok, DateTime.to_date(local)}
      {:error, _reason} = error -> error
    end
  end

  # A fixed UTC offset — `GMT`/`UTC`, `+09`, `+09:00`, `-0430` — as seconds,
  # or `:error` for a named zone.
  defp offset_seconds(timezone) do
    case Regex.run(~r/^\s*(?:GMT|UTC)?([+-])(\d{1,2}):?(\d{2})?\s*$/i, timezone) do
      [_, sign, hours | rest] ->
        minutes = rest |> List.first() |> to_minutes()
        magnitude = (String.to_integer(hours) * 60 + minutes) * 60
        {:ok, if(sign == "-", do: -magnitude, else: magnitude)}

      _no_offset ->
        if String.upcase(String.trim(timezone)) in ["GMT", "UTC", "Z"], do: {:ok, 0}, else: :error
    end
  end

  defp to_minutes(nil), do: 0
  defp to_minutes(""), do: 0
  defp to_minutes(minutes), do: String.to_integer(minutes)

  # One Julian occurrence, converted to Gregorian and spanning `count` days.
  # `Tempo.from_elixir/1` needs a Gregorian date, so the Julian date is
  # converted first; this also sidesteps Calendrical's Julian `day_of_week`.
  defp julian_interval(%Date{} = julian_date, count) do
    with {:ok, gregorian} <- Date.convert(julian_date, Calendrical.Gregorian),
         base <- Tempo.from_elixir(gregorian),
         {:ok, interval} <- first_interval(Tempo.to_interval(base)) do
      {:ok, span_days(interval, base, count)}
    end
  end

  # The BCP 47 `u-ca` calendar tag for a Calendrical module — its CLDR type
  # with underscores as hyphens (`:islamic_umalqura` → "islamic-umalqura").
  defp calendar_tag(calendar) do
    calendar.cldr_calendar_type() |> Atom.to_string() |> String.replace("_", "-")
  end

  # A one-day interval already spans a single day; a longer holiday moves
  # the exclusive upper bound forward by `days`, staying in the calendar.
  defp span_days(interval, _base, days) when days in [nil, 1], do: interval
  defp span_days(interval, base, days), do: %{interval | to: Tempo.shift(base, day: days)}

  # ── observed-date substitution ──────────────────────────────────────

  # Apply the ordered substitution clauses to every occurrence, mirroring
  # date-holidays: the first clause whose trigger a date matches fires and
  # locks the date, so no later clause touches it. A `:shift` clause moves the
  # date to the observed day; `:add` keeps the original and adds the observed
  # day; `:substitute_only` yields the observed day, and drops the occurrence
  # when no clause fires. A no-op when the rule names no substitution.
  defp substitute_all(intervals, nil), do: {:ok, intervals}
  defp substitute_all(intervals, []), do: {:ok, intervals}

  defp substitute_all(intervals, clauses) do
    with {:ok, per_occurrence} <- reduce_ok(intervals, &substitute_one(&1, clauses)) do
      {:ok, List.flatten(per_occurrence)}
    end
  end

  defp substitute_one(interval, clauses) do
    date = Interval.from(interval)
    weekday = Tempo.day_of_week(date, :monday)
    apply_clauses(clauses, interval, date, weekday, false)
  end

  # No clause fired: keep the occurrence, unless a `:substitute_only` clause it
  # failed to trigger has marked it for removal.
  defp apply_clauses([], interval, _date, _weekday, dropped) do
    {:ok, if(dropped, do: [], else: [interval])}
  end

  defp apply_clauses(
         [{triggers, direction, target, mode} | rest],
         interval,
         date,
         weekday,
         dropped
       ) do
    if weekday in triggers do
      # This clause fires and locks the date; `:add` also keeps the original.
      with {:ok, observed} <- observe_on(date, weekday, direction, target) do
        {:ok, if(mode == :add, do: [interval, observed], else: [observed])}
      end
    else
      apply_clauses(rest, interval, date, weekday, dropped or mode == :substitute_only)
    end
  end

  defp observe_on(date, weekday, :next, target) do
    shift_days(date, nonzero_shift(Integer.mod(target - weekday, 7), 7))
  end

  defp observe_on(date, weekday, :previous, target) do
    shift_days(date, nonzero_shift(-Integer.mod(weekday - target, 7), -7))
  end

  # date-holidays moves a full week when the observed target is the date's own
  # weekday, rather than leaving it in place.
  defp nonzero_shift(0, fallback), do: fallback
  defp nonzero_shift(offset, _fallback), do: offset

  defp shift_days(date, days) do
    date
    |> Tempo.shift(day: days)
    |> Tempo.to_interval()
    |> first_interval()
  end

  # ── projection helpers ──────────────────────────────────────────────

  # ISO 8601-2 recurring selection `R/../P1Y/FL<month>M<count>I<weekday>KN`
  # — "every year, the <count>th <weekday> of <month>" — materialised
  # against the target year by `Tempo.to_interval/2`. No `:anchor` is
  # needed; the bound year supplies it.
  defp weekday_iso(%__MODULE__{month: month, count: count, weekday: weekday}) do
    "R/../P1Y/FL#{month}M#{count}I#{weekday}KN"
  end

  # The signed day offset from an anchor date (whose weekday is
  # `anchor_weekday`) to the `count`-th `target` weekday from it. "before" is
  # strict — "the Monday before June 1" steps back even when June 1 is itself a
  # Monday — while "after" is inclusive, matching date-holidays: "the Monday
  # after May 27" is May 27 when that day is already a Monday.
  defp relative_shift(:before, anchor_weekday, target, count) do
    -(strict_step(anchor_weekday - target) + 7 * (count - 1))
  end

  defp relative_shift(:after, anchor_weekday, target, count) do
    inclusive_step(target - anchor_weekday) + 7 * (count - 1)
  end

  defp strict_step(delta) do
    case Integer.mod(delta, 7) do
      0 -> 7
      step -> step
    end
  end

  defp inclusive_step(delta), do: Integer.mod(delta, 7)

  # Orthodox Easter comes back in the Julian calendar; the holiday is asked for
  # a Gregorian year, so both anchors are normalised to Gregorian before the
  # offset and any weekday substitution are applied.
  defp easter_date(:easter, year) do
    year |> Calendrical.Ecclesiastical.easter_sunday() |> to_gregorian()
  end

  defp easter_date(:orthodox, year) do
    year |> Calendrical.Ecclesiastical.orthodox_easter_sunday() |> to_gregorian()
  end

  defp to_gregorian(%Date{calendar: Calendrical.Gregorian} = date), do: date

  defp to_gregorian(%Date{} = date) do
    case Date.convert(date, Calendrical.Gregorian) do
      {:ok, gregorian} -> gregorian
      {:error, _reason} -> date
    end
  end

  # `select/2` and `to_interval/2` return an interval set; a single value
  # materialises straight to an interval. Normalise both to the first
  # (and, for a holiday, only) member.
  defp first_interval({:ok, %Interval{} = interval}), do: {:ok, interval}
  defp first_interval({:ok, %Tempo.IntervalSet{} = set}), do: first_interval(set)
  defp first_interval({:error, _} = error), do: error

  defp first_interval(%Tempo.IntervalSet{} = set) do
    case Tempo.IntervalSet.first(set) do
      %Interval{} = interval -> {:ok, interval}
      nil -> {:error, :no_occurrence}
    end
  end

  # A single-occurrence kind yields one interval; lift it into the
  # one-element list `materialise/2` returns, propagating any error.
  defp wrap_one({:ok, %Interval{} = interval}), do: {:ok, [interval]}
  defp wrap_one({:error, _} = error), do: error

  # date-holidays counts the Nth weekday from the first of the month, so a
  # "5th monday in October" in a month with only four Mondays overflows into
  # the next month (the anniversary NZ-MBH observes as 1 November). A negative
  # count (`last`) cannot overflow, so it simply does not occur.
  defp overflow_weekday(%__MODULE__{count: count} = rule, year)
       when is_integer(count) and count > 0 do
    with {:ok, anchor} <- Tempo.from_iso8601("#{Tempo.year(year)}-#{month_day(rule.month, 1)}") do
      to_first = relative_shift(:after, Tempo.day_of_week(anchor, :monday), rule.weekday, 1)

      anchor
      |> Tempo.shift(day: to_first + (count - 1) * 7)
      |> Tempo.to_interval()
      |> first_interval()
      |> wrap_one()
    end
  end

  defp overflow_weekday(_rule, _year), do: {:ok, []}

  # Map an `{:ok, _} | {:error, _}` function over `items`, collecting the
  # values in order into `{:ok, list}`, or returning the first error.
  defp reduce_ok(items, fun) do
    items
    |> Enum.reduce_while([], &collect_ok(fun.(&1), &2))
    |> finish_ok()
  end

  defp collect_ok({:ok, value}, acc), do: {:cont, [value | acc]}
  defp collect_ok({:error, _} = error, _acc), do: {:halt, error}

  defp finish_ok({:error, _} = error), do: error
  defp finish_ok(acc) when is_list(acc), do: {:ok, Enum.reverse(acc)}

  defp month_day(month, day), do: "#{pad(month)}-#{pad(day)}"
  defp pad(number), do: String.pad_leading(Integer.to_string(number), 2, "0")
end
