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

  @type kind :: :fixed | :weekday | :easter | :orthodox

  @typedoc """
  An observed-date substitution: `{trigger_weekdays, target_weekday}` clauses
  in ISO weekday numbering (Monday = 1 … Sunday = 7). When the materialised
  date lands on one of the trigger weekdays, the holiday is observed on the
  next occurrence of the target weekday. "If it falls on a weekend, take the
  following Monday" is `[{[6, 7], 1}]`.
  """
  @type substitute :: [{[1..7], 1..7}]

  @type t :: %__MODULE__{
          kind: kind(),
          month: pos_integer() | nil,
          day: pos_integer() | nil,
          count: integer() | nil,
          weekday: 1..7 | nil,
          offset: integer() | nil,
          substitute: substitute() | nil,
          source: String.t() | nil
        }

  @enforce_keys [:kind]
  defstruct [:kind, :month, :day, :count, :weekday, :offset, :substitute, :source]

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

  defp materialise_base(%__MODULE__{kind: kind, offset: offset}, %Tempo{} = year)
       when kind in [:easter, :orthodox] do
    easter_date(kind, Tempo.year(year))
    |> Tempo.from_elixir()
    |> Tempo.shift(day: offset || 0)
    |> Tempo.to_interval()
    |> first_interval()
  end

  # ── observed-date substitution ──────────────────────────────────────

  # When the holiday lands on a trigger weekday, observe it on the next
  # occurrence of the target weekday. A no-op when the rule names no
  # substitution or the date is not triggered.
  defp apply_substitute(interval, nil), do: {:ok, interval}
  defp apply_substitute(interval, []), do: {:ok, interval}

  defp apply_substitute(interval, clauses) do
    date = Interval.from(interval)
    weekday = Tempo.day_of_week(date, :monday)

    case Enum.find(clauses, fn {triggers, _target} -> weekday in triggers end) do
      nil -> {:ok, interval}
      {_triggers, target} -> observe_on(date, weekday, target)
    end
  end

  defp observe_on(date, weekday, target) do
    days_forward = Integer.mod(target - weekday, 7)

    date
    |> Tempo.shift(day: days_forward)
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
