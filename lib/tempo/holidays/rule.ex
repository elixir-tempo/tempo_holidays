defmodule Tempo.Holidays.Rule do
  @moduledoc """
  A compiled holiday rule, and its projection onto a year.

  A rule is the calendar-agnostic *recurrence* behind a holiday, compiled
  from a [date-holidays](https://github.com/commenthol/date-holidays) rule
  string by `Tempo.Holidays.Compiler`. `materialise/2` projects it onto a
  concrete year, yielding the `t:Tempo.Interval.t/0` for that occurrence.

  Each `:kind` maps to the machinery that can express it: `:fixed` and
  `:weekday` are Tempo-native ISO 8601-2 selections (`FL12M25DN`,
  `FL6M2I1KN`); `:easter` / `:orthodox` are computed through Calendrical's
  ecclesiastical calendar, since Easter is not expressible as an ISO 8601
  recurrence.

  A rule may also carry an observed-date `t:substitute/0` — "if it falls on
  a weekend, observe it the following Monday" — applied after the base date
  is placed, using `Tempo.day_of_week/2` and `Tempo.shift/2`.

  """

  alias Tempo.Interval

  @type kind :: :fixed | :weekday | :relative_weekday | :islamic | :easter | :orthodox

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
          direction: :before | :after | nil,
          offset: integer() | nil,
          substitute: substitute() | nil,
          source: String.t() | nil
        }

  @enforce_keys [:kind]
  defstruct [:kind, :month, :day, :count, :weekday, :direction, :offset, :substitute, :source]

  @doc """
  Project a rule onto `year`, returning the occurrence as an interval.

  ### Arguments

  * `rule` is a `t:t/0`.

  * `year` is a year-resolution `t:Tempo.t/0` such as `~o"2026"`.

  ### Returns

  * `{:ok, t:Tempo.Interval.t/0}` — the holiday's span in that year.

  * `{:error, reason}` when the rule cannot be projected.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("12-25")
      iex> {:ok, interval} = Tempo.Holidays.Rule.materialise(rule, ~o"2026")
      iex> Tempo.Interval.from(interval)
      ~o"2026Y12M25D"

  """
  @spec materialise(t(), Tempo.t()) :: {:ok, Interval.t()} | {:error, term()}
  def materialise(%__MODULE__{} = rule, %Tempo{} = year) do
    with {:ok, interval} <- materialise_base(rule, year) do
      apply_substitute(interval, rule.substitute)
    end
  end

  defp materialise_base(%__MODULE__{kind: :fixed, month: month, day: day}, %Tempo{} = year) do
    with {:ok, selector} <- Tempo.from_iso8601(month_day(month, day)),
         {:ok, set} <- Tempo.select(year, selector) do
      first_interval(set)
    end
  end

  defp materialise_base(%__MODULE__{kind: :weekday} = rule, %Tempo{} = year) do
    with {:ok, recurrence} <- Tempo.from_iso8601(weekday_iso(rule)),
         {:ok, set} <- Tempo.to_interval(recurrence, bound: year) do
      first_interval(set)
    end
  end

  defp materialise_base(
         %__MODULE__{kind: :relative_weekday, weekday: target, direction: direction} = rule,
         %Tempo{} = year
       ) do
    with {:ok, anchor} <-
           Tempo.from_iso8601("#{Tempo.year(year)}-#{month_day(rule.month, rule.day)}") do
      shift = relative_shift(direction, Tempo.day_of_week(anchor, :monday), target)

      anchor
      |> Tempo.shift(day: shift)
      |> Tempo.to_interval()
      |> first_interval()
    end
  end

  # An Islamic holiday is calculated — and returned — in the Islamic
  # calendar, per Tempo's calendar-awareness: `year` names the *Hijri* year,
  # and the result is an `[u-ca=islamic-civil]` interval, not a Gregorian
  # conversion. A `count` greater than one spans that many days (the `P<n>D`
  # form, e.g. the four days of Eid al-Fitr).
  defp materialise_base(
         %__MODULE__{kind: :islamic, month: month, day: day, count: count},
         %Tempo{} = year
       ) do
    with {:ok, base} <-
           Tempo.from_iso8601("#{Tempo.year(year)}Y#{month}M#{day}D[u-ca=islamic-civil]"),
         {:ok, interval} <- first_interval(Tempo.to_interval(base)) do
      {:ok, span_days(interval, base, count)}
    end
  end

  defp materialise_base(%__MODULE__{kind: kind, offset: offset}, %Tempo{} = year)
       when kind in [:easter, :orthodox] do
    easter_date(kind, Tempo.year(year))
    |> Tempo.from_elixir()
    |> Tempo.shift(day: offset || 0)
    |> Tempo.to_interval()
    |> first_interval()
  end

  # A one-day interval already spans a single day; a longer holiday moves
  # the exclusive upper bound forward by `days`, staying in the calendar.
  defp span_days(interval, _base, days) when days in [nil, 1], do: interval
  defp span_days(interval, base, days), do: %{interval | to: Tempo.shift(base, day: days)}

  # ── observed-date substitution ──────────────────────────────────────

  # When the holiday lands on a trigger weekday, observe it on the next
  # occurrence of the target weekday. A no-op when the rule names no
  # substitution or the date is not triggered.
  defp apply_substitute(interval, nil), do: {:ok, interval}
  defp apply_substitute(interval, []), do: {:ok, interval}

  defp apply_substitute(interval, clauses) do
    date = Interval.from(interval)
    weekday = Tempo.day_of_week(date, :monday)

    case Enum.find(clauses, fn {triggers, _direction, _target} -> weekday in triggers end) do
      nil -> {:ok, interval}
      {_triggers, direction, target} -> observe_on(date, weekday, direction, target)
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
  # `anchor_weekday`) to the nearest `target` weekday strictly before or
  # after it. "The Monday before June 1" steps back to the previous Monday
  # even when June 1 is itself a Monday.
  defp relative_shift(:before, anchor_weekday, target), do: -strict_step(anchor_weekday - target)
  defp relative_shift(:after, anchor_weekday, target), do: strict_step(target - anchor_weekday)

  defp strict_step(delta) do
    case Integer.mod(delta, 7) do
      0 -> 7
      step -> step
    end
  end

  defp easter_date(:easter, year), do: Calendrical.Ecclesiastical.easter_sunday(year)
  defp easter_date(:orthodox, year), do: Calendrical.Ecclesiastical.orthodox_easter_sunday(year)

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

  defp month_day(month, day), do: "#{pad(month)}-#{pad(day)}"
  defp pad(number), do: String.pad_leading(Integer.to_string(number), 2, "0")
end
