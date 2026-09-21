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
  `[u-ca=…]`-tagged value rather than converted to Gregorian.

  A rule may also carry an observed-date `t:substitute/0` — "if it falls on a
  weekend, observe it the following Monday" — in one of three modes (`:add`
  keeps the date and adds the observed day, `:shift` moves it, `:substitute_only`
  is the observed day alone), plus year conditions (`:from_year`/`:to_year`,
  even/odd `:year_parity`, and `:leap`) that gate whether it occurs at all.

  """

  alias Tempo.Interval

  @type kind ::
          :fixed
          | :weekday
          | :relative_weekday
          | :nested_weekday
          | :islamic
          | :hebrew
          | :persian
          | :easter
          | :orthodox

  @typedoc """
  An observed-date substitution: `{trigger_weekdays, direction, target_weekday}`
  clauses in ISO weekday numbering (Monday = 1 … Sunday = 7). When the
  materialised date lands on one of the trigger weekdays, the holiday is
  observed on the nearest `:next` or `:previous` occurrence of the target
  weekday. "If it falls on a weekend, take the following Monday" is
  `[{[6, 7], :next, 1}]`; the US rule "Saturday → prior Friday, Sunday →
  next Monday" is `[{[6], :previous, 5}, {[7], :next, 1}]`.
  """
  @type substitute :: [{[1..7], :next | :previous, 1..7}]

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
          substitute: substitute() | nil,
          substitute_mode: :shift | :add | :substitute_only | nil,
          from_year: integer() | nil,
          to_year: integer() | nil,
          year_parity: :even | :odd | nil,
          leap: :leap | :non_leap | nil,
          every_years: pos_integer() | nil,
          weekday_gate: {:only | :except, [1..7]} | nil,
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
    :substitute,
    :substitute_mode,
    :from_year,
    :to_year,
    :year_parity,
    :leap,
    :every_years,
    :weekday_gate,
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
    if active_in_year?(rule, Tempo.year(year)) do
      with {:ok, intervals} <- materialise_base(rule, year) do
        intervals
        |> gate_by_weekday(rule.weekday_gate)
        |> substitute_all(rule.substitute, rule.substitute_mode)
      end
    else
      {:ok, []}
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
      wrap_one(first_interval(set))
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

  defp materialise_base(%__MODULE__{kind: kind, offset: offset}, %Tempo{} = year)
       when kind in [:easter, :orthodox] do
    easter_date(kind, Tempo.year(year))
    |> Tempo.from_elixir()
    |> Tempo.shift(day: offset || 0)
    |> Tempo.to_interval()
    |> first_interval()
    |> wrap_one()
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

  # Apply the substitution to every occurrence. date-holidays distinguishes
  # two forms: a bare "if <weekday> then <target>" *moves* the holiday to the
  # observed day (`:shift`), while "and if …" keeps the original date and
  # *adds* the observed day (`:add`). A no-op when the rule names no
  # substitution.
  defp substitute_all(intervals, nil, _mode), do: {:ok, intervals}
  defp substitute_all(intervals, [], _mode), do: {:ok, intervals}

  defp substitute_all(intervals, clauses, mode) do
    with {:ok, per_occurrence} <- reduce_ok(intervals, &substitute_one(&1, clauses, mode)) do
      {:ok, List.flatten(per_occurrence)}
    end
  end

  defp substitute_one(interval, clauses, mode) do
    date = Interval.from(interval)
    weekday = Tempo.day_of_week(date, :monday)

    case Enum.find(clauses, fn {triggers, _direction, _target} -> weekday in triggers end) do
      nil -> untriggered(interval, mode)
      {_triggers, direction, target} -> observed(interval, date, weekday, direction, target, mode)
    end
  end

  # A `substitutes …` rule *is* the substitute, so it contributes nothing on a
  # day that does not trigger it; the other modes keep the original date.
  defp untriggered(_interval, :substitute_only), do: {:ok, []}
  defp untriggered(interval, _mode), do: {:ok, [interval]}

  # `:add` keeps the original date and adds the observed day; `:shift` and
  # `:substitute_only` replace the original with the observed day.
  defp observed(interval, date, weekday, direction, target, :add) do
    with {:ok, day} <- observe_on(date, weekday, direction, target) do
      {:ok, [interval, day]}
    end
  end

  defp observed(_interval, date, weekday, direction, target, mode)
       when mode in [:shift, :substitute_only] do
    with {:ok, day} <- observe_on(date, weekday, direction, target) do
      {:ok, [day]}
    end
  end

  defp observe_on(date, weekday, :next, target) do
    shift_days(date, Integer.mod(target - weekday, 7))
  end

  defp observe_on(date, weekday, :previous, target) do
    shift_days(date, -Integer.mod(weekday - target, 7))
  end

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
