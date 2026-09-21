defmodule Tempo.Holidays do
  @moduledoc """
  Public holidays as Tempo recurrences, projectable onto any year.

  A holiday is a *recurrence*, not a date: "Christmas is the 25th of
  December", "the King's Birthday is the second Monday of June". Each is
  held as a `t:Tempo.Holidays.Holiday.t/0` — a name and a
  `t:Tempo.Holidays.Rule.t/0` — and `materialise/2` projects it onto a
  concrete year to obtain the interval it occupies there.

  Fixed dates and weekday-in-month holidays are native ISO 8601-2 selections
  (`FL12M25DN`, `FL6M2I1KN`); Easter-relative holidays are computed through
  Calendrical's ecclesiastical calendar, since Easter has no ISO 8601 form.

  ## Example

      territory = :AU

      {:ok, holidays}  = Tempo.Holidays.recurrences(territory)
      {:ok, this_year} = Tempo.Holidays.materialise(territory, ~o"2026")

  > *"The recurrences are Australia's public holidays. Materialised onto
  > 2026, each one lands on the day it falls that year."*

  """

  alias Tempo.Holidays.{Data, Holiday, Rule}

  @doc """
  Return the holiday recurrences for a territory.

  ### Arguments

  * `territory` is a CLDR territory code as an atom, such as `:AU`.

  ### Returns

  * `{:ok, [t:Tempo.Holidays.Holiday.t/0]}` — each holiday paired with the
    recurrence rule that places it in any year.

  * `{:error, {:unknown_territory, territory}}` when there is no data for
    the territory.

  ### Examples

      iex> {:ok, holidays} = Tempo.Holidays.recurrences(:AU)
      iex> Enum.map(holidays, & &1.name) |> Enum.take(2)
      ["New Year's Day", "Australia Day"]

  """
  @spec recurrences(term()) :: {:ok, [Holiday.t()]} | {:error, {:unknown_territory, term()}}
  def recurrences(territory), do: Data.for_territory(territory)

  @doc """
  Project a territory's holidays onto `year`, date-sorted.

  ### Arguments

  * `territory` is a CLDR territory code as an atom, such as `:AU`.

  * `year` is a year-resolution `t:Tempo.t/0` such as `~o"2026"`.

  ### Returns

  * `{:ok, [{t:Tempo.Holidays.Holiday.t/0, t:Tempo.Interval.t/0}]}` — each
    holiday paired with the interval it occupies that year, earliest first.

  * `{:error, {:unknown_territory, territory}}` when there is no data for
    the territory.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, holidays} = Tempo.Holidays.materialise(:AU, ~o"2026")
      iex> {holiday, interval} = hd(holidays)
      iex> {holiday.name, Tempo.Interval.from(interval)}
      {"New Year's Day", ~o"2026Y1M1D"}

  """
  @spec materialise(term() | [Holiday.t()], Tempo.t()) ::
          {:ok, [{Holiday.t(), Tempo.Interval.t()}]} | {:error, {:unknown_territory, term()}}
  def materialise(holidays, %Tempo{} = year) when is_list(holidays) do
    {:ok, materialise_all(holidays, year)}
  end

  def materialise(territory, %Tempo{} = year) do
    with {:ok, holidays} <- Data.for_territory(territory) do
      {:ok, materialise_all(holidays, year)}
    end
  end

  # A holiday whose rule cannot land in this year is dropped rather than
  # failing the whole set — the same partial-support contract the compiler
  # keeps. The seed slice materialises cleanly in every year.
  defp materialise_all(holidays, year) do
    holidays
    |> Enum.flat_map(&materialise_one(&1, year))
    |> coalesce_by_name()
    |> Enum.sort_by(fn {_holiday, interval} -> Tempo.Interval.from(interval) end, Tempo)
  end

  defp materialise_one(%Holiday{rule: rule} = holiday, year) do
    case Rule.materialise(rule, year) do
      {:ok, interval} -> [{holiday, interval}]
      {:error, _} -> []
    end
  end

  # date-holidays splits a period that crosses a year boundary into two
  # back-to-back entries under one name, because its YAML cannot express a
  # cross-year range. Tempo can, so abutting occurrences of the *same*
  # holiday are merged into the single period they describe — while
  # genuinely distinct neighbours (Christmas the 25th, Boxing Day the 26th)
  # keep their own names and stay apart.
  defp coalesce_by_name(pairs) do
    pairs
    |> Enum.group_by(fn {holiday, _interval} -> holiday.name end)
    |> Enum.flat_map(fn {_name, group} -> coalesce_group(group) end)
  end

  defp coalesce_group([{holiday, _interval} | _] = group) do
    intervals = Enum.map(group, fn {_holiday, interval} -> interval end)

    case Tempo.IntervalSet.new(intervals, coalesce: true) do
      {:ok, set} -> Enum.map(Tempo.IntervalSet.to_list(set), &{holiday, &1})
      {:error, _} -> group
    end
  end

  defp coalesce_group([]), do: []
end
