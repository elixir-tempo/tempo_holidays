defmodule Tempo.Holidays do
  @moduledoc """
  Holidays as Tempo recurrences, projectable onto any year.

  A holiday is a *recurrence*, not a date: "Christmas is the 25th of
  December", "Thanksgiving is the fourth Thursday of November". Each is
  held as a `t:Tempo.Holidays.Holiday.t/0` — a name, a `:type`, and a
  `t:Tempo.Holidays.Rule.t/0` — and `materialise/2` projects it onto a
  concrete year to obtain the interval it occupies there.

  The data is the [date-holidays](https://github.com/commenthol/date-holidays)
  dataset for every territory, carrying every `:type` (public holidays through
  to observances). Fixed dates and weekday-in-month holidays are native ISO
  8601-2 selections (`FL12M25DN`, `FL6M2I1KN`); Easter-relative holidays are
  computed through Calendrical's ecclesiastical calendar; Islamic holidays are
  projected onto the Gregorian year through Calendrical and returned in the
  Islamic calendar. A lunar holiday can fall twice in one Gregorian year, so
  `materialise/2` returns a list of occurrences.

  ## Example

      territory = :SA

      {:ok, holidays}  = Tempo.Holidays.recurrences(territory)
      {:ok, this_year} = Tempo.Holidays.materialise(territory, ~o"2026")

  > *"The recurrences are Saudi Arabia's holidays. Materialised onto 2026,
  > each one lands on the day it falls that year — Eid al-Fitr and Eid
  > al-Adha in the Islamic calendar."*

  """

  alias Tempo.Holidays.{Data, DayStart, Holiday, Locale, Rule}

  @typedoc """
  A holiday request's target: a positional CLDR territory code (atom or string,
  always a territory — never a language), a `t:Localize.LanguageTag.t/0`, or a
  keyword list carrying a `:territory` or `:locale` option.
  """
  @type target :: atom() | String.t() | Localize.LanguageTag.t() | keyword()

  @doc """
  Return the holiday recurrences for a territory.

  ### Arguments

  * `target` names the territory — a positional CLDR territory code (`:AU`,
    `"AU"`, always a territory, never a language) or a `t:Localize.LanguageTag.t/0`.
    Omit it and pass the target by option instead. See `Tempo.Holidays.Locale`.

  ### Options

  * `:territory` — an explicit CLDR territory code, validated (`territory: :SA`
    is Saudi Arabia).

  * `:locale` — a BCP 47 locale identifier or `t:Localize.LanguageTag.t/0` whose
    territory is derived (`locale: "en-US-u-sd-usca"` selects California).

  * `:division`, `:subdivision` — override the state / region level.

  ### Returns

  * `{:ok, [t:Tempo.Holidays.Holiday.t/0]}` — the holidays for the most specific
    level with data, falling back to the country.

  * `{:error, {:unknown_territory, territory}}` or `{:error, {:invalid_locale,
    target}}`.

  ### Examples

      iex> {:ok, holidays} = Tempo.Holidays.recurrences(:AU)
      iex> Enum.map(holidays, & &1.name) |> Enum.take(2)
      ["New Year's Day", "Australia Day"]

  """
  @spec recurrences(target(), keyword()) :: {:ok, [Holiday.t()]} | {:error, {atom(), term()}}
  def recurrences(target \\ [], options \\ [])

  def recurrences(options, extra) when is_list(options) do
    resolve_holidays(nil, Keyword.merge(options, extra))
  end

  def recurrences(target, options) do
    resolve_holidays(target, options)
  end

  defp resolve_holidays(target, options) do
    with {:ok, resolved} <- Locale.resolve(target, options) do
      Data.for_territory(resolved.territory, resolved.division, resolved.subdivision)
    end
  end

  @doc """
  Project a territory's holidays onto `year`, date-sorted.

  Called as `materialise(target, year, options)` with a positional territory or
  holiday list (as for `recurrences/2`), or as `materialise(year, options)` with
  the target given by a `:territory` or `:locale` option.

  ### Arguments

  * `target` names the territory as for `recurrences/2`, or is a list of
    `t:Tempo.Holidays.Holiday.t/0` to project directly.

  * `year` is a year-resolution `t:Tempo.t/0` such as `~o"2026"`.

  ### Options

  * `:territory` / `:locale` — the target, as for `recurrences/2`.

  * `:division`, `:subdivision` — override the state / region level (ignored when
    a holiday list is given).

  * `:day_start` — how a sunset-starting-calendar holiday (Islamic, Hebrew) is
    projected onto the Gregorian timeline. `:midnight` (the default) returns the
    in-calendar day. `:evening` / `:sunset` return the datetime interval that
    begins the evening before — the 18:00 proxy, or true sunset — at the
    calendar's canonical reference (Mecca, Jerusalem); a `{:evening | :sunset,
    anchor}` pair takes it at an explicit IANA zone id or `{longitude, latitude}`
    location instead. See `t:Tempo.Holidays.DayStart.t/0`. Non-sunset holidays are
    unaffected.

  ### Returns

  * `{:ok, [{t:Tempo.Holidays.Holiday.t/0, t:Tempo.Interval.t/0}]}` — each
    holiday paired with the interval it occupies that year, earliest first. Under
    a non-midnight `:day_start`, a sunset-starting holiday's interval is a
    Gregorian datetime interval rather than an in-calendar day.

  * `{:error, {:unknown_territory, territory}}` or `{:error, {:invalid_locale,
    locale}}`.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, holidays} = Tempo.Holidays.materialise(:AU, ~o"2026")
      iex> {holiday, interval} = hd(holidays)
      iex> {holiday.name, Tempo.Interval.from(interval)}
      {"New Year's Day", ~o"2026Y1M1D"}

  """
  @spec materialise(target() | [Holiday.t()] | Tempo.t(), Tempo.t() | keyword(), keyword()) ::
          {:ok, [{Holiday.t(), Tempo.Interval.t()}]} | {:error, {atom(), term()}}
  def materialise(target, year_or_options, options \\ [])

  def materialise(%Tempo{} = year, options, extra) when is_list(options) do
    materialise_target(nil, year, Keyword.merge(options, extra))
  end

  def materialise(holidays, %Tempo{} = year, options) when is_list(holidays) do
    {:ok, materialise_all(holidays, year, day_start(options))}
  end

  def materialise(target, %Tempo{} = year, options) do
    materialise_target(target, year, options)
  end

  defp materialise_target(target, year, options) do
    with {:ok, holidays} <- resolve_holidays(target, options) do
      {:ok, materialise_all(holidays, year, day_start(options))}
    end
  end

  defp day_start(options), do: Keyword.get(options, :day_start, :midnight)

  # A holiday whose rule cannot land in this year is dropped rather than
  # failing the whole set — the same partial-support contract the compiler
  # keeps.
  #
  # Materialisation is two passes, because a *conditional* holiday (a bridge
  # day, or an `if is … holiday then …` move) depends on the *other* holidays of
  # the year. The first pass materialises every holiday's base occurrences and
  # tallies the year's holiday days by type; the second resolves each
  # conditional against that tally (`Tempo.Holidays.Rule.resolve_conditional/4`).
  defp materialise_all(holidays, year, day_start) do
    base = Enum.map(holidays, fn holiday -> {holiday, base_occurrences(holiday, year)} end)
    counts = occurrence_counts(base)

    base
    |> Enum.flat_map(&resolve_occurrences(&1, year, counts))
    |> coalesce_by_name()
    |> project_day_start(day_start)
    |> Enum.sort_by(fn {_holiday, interval} -> Tempo.Interval.from(interval) end, Tempo)
  end

  # A day is just a day until it is projected onto the Gregorian timeline. With a
  # non-midnight `day_start`, each sunset-starting-calendar occurrence (Islamic,
  # Hebrew) is projected to the datetime interval that begins when its day begins;
  # every other holiday, and `:midnight`, is left as the civil day it already is.
  defp project_day_start(pairs, :midnight), do: pairs

  defp project_day_start(pairs, day_start) do
    Enum.map(pairs, fn {holiday, interval} ->
      {holiday, project_occurrence(holiday, interval, day_start)}
    end)
  end

  defp project_occurrence(
         %Holiday{rule: %Rule{kind: kind, calendar: calendar}},
         interval,
         day_start
       )
       when kind in [:islamic, :hebrew] do
    case DayStart.project(interval, calendar, day_start) do
      {:ok, projected} -> projected
      {:error, _} -> interval
    end
  end

  defp project_occurrence(_holiday, interval, _day_start), do: interval

  defp base_occurrences(%Holiday{rule: rule}, year) do
    case Rule.materialise(rule, year) do
      {:ok, intervals} -> intervals
      {:error, _} -> []
    end
  end

  # The year's holiday days as a `{gregorian_days, type} => count` tally, over
  # every holiday's base occurrences.
  defp occurrence_counts(base) do
    Enum.reduce(base, %{}, fn {holiday, occurrences}, counts ->
      tally(counts, occurrences, holiday.type)
    end)
  end

  defp tally(counts, occurrences, type) do
    Enum.reduce(occurrences, counts, &tally_one(&2, &1, type))
  end

  defp tally_one(counts, interval, type) do
    case Rule.occurrence_days(interval) do
      {:ok, days} -> Map.update(counts, {days, type}, 1, &(&1 + 1))
      :error -> counts
    end
  end

  defp resolve_occurrences({%Holiday{rule: rule} = holiday, occurrences}, year, counts) do
    if Rule.conditional?(rule) do
      present? = present_excluding(holiday, occurrences, counts)

      case Rule.resolve_conditional(rule, occurrences, year, present?) do
        {:ok, intervals} -> Enum.map(intervals, &{holiday, &1})
        {:error, _} -> []
      end
    else
      Enum.map(occurrences, &{holiday, &1})
    end
  end

  # A `(gregorian_days, type) -> boolean()` for the second pass: does *another*
  # holiday of `type` fall on `days`? A holiday never satisfies its own
  # condition, so its own occurrences are discounted from the tally — mirroring
  # date-holidays skipping the rule under test.
  defp present_excluding(%Holiday{type: own_type}, occurrences, counts) do
    own = tally(%{}, occurrences, own_type)

    fn days, type ->
      mine = if type == own_type, do: Map.get(own, {days, own_type}, 0), else: 0
      Map.get(counts, {days, type}, 0) - mine > 0
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
