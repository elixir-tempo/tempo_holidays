defmodule Tempo.Holidays do
  @moduledoc """
  Holidays as Tempo recurrences, projectable onto any window.

  A holiday is a *recurrence*, not a date: "Christmas is the 25th of
  December", "Thanksgiving is the fourth Thursday of November". A territory's
  holidays are a `t:Tempo.RecurrenceSet.t/0` — one member per holiday, each
  tagged with the holiday's metadata — and materialising it onto a window
  gives the `t:Tempo.IntervalSet.t/0` of the holidays that fall there, each
  occurrence tagged the same way. Because both are Tempo values, holidays
  compose with anything else through set algebra.

  The data is the [date-holidays](https://github.com/commenthol/date-holidays)
  dataset for every territory, carrying every `:type` (public holidays through
  to observances). Fixed dates and weekday-in-month holidays are ISO 8601-2
  selections (`FL12M25DN`, `FL6M1K2IN`); Easter-relative holidays are windows
  off the computed `(easter)e` event; Islamic, Hebrew and other calendar
  holidays are recurrences in their own calendar, returned in it; a holiday
  observed on another day is a nested set of its own date and its observed
  days; and a bridge day or a holiday moved off another is a conditional member
  (`Tempo.RecurrenceSet.keep_when/2`, `move_when/2`), resolved against the
  others when the set materialises.

  Each holiday's metadata is `:id` (its date-holidays rule, unique within the
  set, where names repeat), `:name` and `:type`; an observed day adds
  `substitute: true`. The set's own metadata names its territory.

  ## Example

      {:ok, holidays} = Tempo.Holidays.recurrences(:AU)
      {:ok, this_year} = Tempo.Holidays.materialise(holidays, ~o"2026")

      {:ok, clashes} = Tempo.intersection(my_diary, holidays, metadata: :merge)

  > *"Australia's **holidays** are a set of recurrences. **This year's** are the
  > days they fall on in 2026; the diary's **clashes** are its entries that fall
  > on one, each labelled with the holiday it hit."*

  """

  alias Tempo.Holidays.{Data, DayStart, Holiday, Locale, Rule}
  alias Tempo.IntervalSet

  @typedoc """
  A holiday request's target: a positional CLDR territory code (atom or string,
  always a territory — never a language), a `t:Localize.LanguageTag.t/0`, or a
  keyword list carrying a `:territory` or `:locale` option.
  """
  @type target :: atom() | String.t() | Localize.LanguageTag.t() | keyword()

  @typedoc "The window a holiday set materialises over: a year, or any interval."
  @type window :: Tempo.t() | Tempo.Interval.t()

  # The calendars whose day begins at sunset, so `:day_start` projects their
  # holidays onto the evening before.
  @sunset_calendar_types [
    :hebrew,
    :islamic,
    :islamic_civil,
    :islamic_rgsa,
    :islamic_tbla,
    :islamic_umalqura
  ]

  defguardp is_window(value) when is_struct(value, Tempo) or is_struct(value, Tempo.Interval)

  @doc """
  Returns a territory's holidays as a recurrence set.

  Each member is one holiday — its recurrence, a nested set of its own date and
  its observed days, or a conditional member for a bridge day or a holiday moved
  off another — tagged with `:id`, `:name` and `:type` metadata. The set's own
  metadata names the territory, and the division and subdivision when given.

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

  * `{:ok, recurrence_set}` — a `t:Tempo.RecurrenceSet.t/0` of the holidays for
    the most specific level with data, falling back to the country.

  * `{:error, {:unknown_territory, territory}}` or `{:error, {:invalid_locale,
    target}}`.

  ### Examples

      iex> {:ok, holidays} = Tempo.Holidays.recurrences(:AU)
      iex> holidays |> Tempo.RecurrenceSet.members() |> Enum.map(&Tempo.metadata(&1).name) |> Enum.take(2)
      ["New Year's Day", "Australia Day"]
      iex> Tempo.RecurrenceSet.metadata(holidays)
      %{territory: "AU"}

  """
  @spec recurrences(target(), keyword()) ::
          {:ok, Tempo.RecurrenceSet.t()} | {:error, {atom(), term()}}
  def recurrences(target \\ [], options \\ [])

  def recurrences(options, extra) when is_list(options) do
    holiday_set(nil, Keyword.merge(options, extra))
  end

  def recurrences(target, options) do
    holiday_set(target, options)
  end

  defp holiday_set(target, options) do
    with {:ok, resolved} <- Locale.resolve(target, options),
         {:ok, holidays} <-
           Data.for_territory(resolved.territory, resolved.division, resolved.subdivision) do
      members = Enum.flat_map(holidays, &holiday_member/1)
      {:ok, Tempo.RecurrenceSet.new(members, metadata: set_metadata(resolved))}
    end
  end

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

  defp set_metadata(resolved) do
    resolved
    |> Map.take([:territory, :division, :subdivision])
    |> Map.reject(fn {_level, code} -> is_nil(code) end)
  end

  @doc """
  Projects holidays onto a window, earliest first.

  Called as `materialise(target, window, options)` with a positional territory
  (as for `recurrences/2`) or a recurrence set `recurrences/2` returned, or as
  `materialise(window, options)` with the target given by a `:territory` or
  `:locale` option.

  ### Arguments

  * `target` names the territory as for `recurrences/2`, or is a
    `t:Tempo.RecurrenceSet.t/0` of holidays.

  * `window` is a year (`~o"2026"`) or any interval (`~o"2026-07/2027-07"`).

  ### Options

  * `:territory` / `:locale` — the target, as for `recurrences/2`.

  * `:division`, `:subdivision` — override the state / region level (ignored when
    a recurrence set is given).

  * `:day_start` — how a sunset-starting-calendar holiday (Islamic, Hebrew) is
    projected onto the Gregorian timeline. `:midnight` (the default) returns the
    in-calendar day. `:evening` / `:sunset` return the datetime interval that
    begins the evening before — the 18:00 proxy, or true sunset — at the
    calendar's canonical reference (Mecca, Jerusalem); a `{:evening | :sunset,
    anchor}` pair takes it at an explicit IANA zone id or `{longitude, latitude}`
    location instead. See `t:Tempo.Holidays.DayStart.t/0`. Non-sunset holidays are
    unaffected.

  ### Returns

  * `{:ok, interval_set}` — a `t:Tempo.IntervalSet.t/0` of the holidays'
    occurrences starting in the window, each tagged with its holiday's metadata;
    abutting occurrences of one holiday (a period date-holidays splits at a year
    end) are one. Under a non-midnight `:day_start`, a sunset-starting holiday's
    occurrence is a Gregorian datetime interval rather than an in-calendar day.

  * `{:error, {:unknown_territory, territory}}` or `{:error, {:invalid_locale,
    locale}}`.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, holidays} = Tempo.Holidays.materialise(:AU, ~o"2026")
      iex> first = Tempo.IntervalSet.first(holidays)
      iex> {Tempo.metadata(first).name, Tempo.Interval.from(first)}
      {"New Year's Day", ~o"2026Y1M1D"}

  """
  @spec materialise(
          target() | Tempo.RecurrenceSet.t() | window(),
          window() | keyword(),
          keyword()
        ) ::
          {:ok, IntervalSet.t()} | {:error, term()}
  def materialise(target, window_or_options, options \\ [])

  def materialise(window, options, extra) when is_window(window) and is_list(options) do
    materialise_target(nil, window, Keyword.merge(options, extra))
  end

  def materialise(%Tempo.RecurrenceSet{} = holidays, window, options) when is_window(window) do
    materialise_set(holidays, window, options)
  end

  def materialise(target, window, options) when is_window(window) do
    materialise_target(target, window, options)
  end

  defp materialise_target(target, window, options) do
    with {:ok, holidays} <- recurrences(target, options) do
      materialise_set(holidays, window, options)
    end
  end

  defp materialise_set(holidays, window, options) do
    with {:ok, occurrences} <- Tempo.to_interval_set(holidays, bound: window),
         {:ok, coalesced} <- coalesce_by_name(occurrences) do
      project_day_start(coalesced, Keyword.get(options, :day_start, :midnight))
    end
  end

  # date-holidays splits a period that crosses a year boundary into two
  # back-to-back entries under one name, because its YAML cannot express a
  # cross-year range. Tempo can, so abutting occurrences of the *same*
  # holiday are merged into the single period they describe — while
  # genuinely distinct neighbours (Christmas the 25th, Boxing Day the 26th)
  # keep their own names and stay apart.
  defp coalesce_by_name(occurrences) do
    occurrences
    |> IntervalSet.to_list()
    |> Enum.group_by(&Tempo.metadata(&1)[:name])
    |> Enum.flat_map(fn {_name, group} -> coalesce_group(group) end)
    |> IntervalSet.new(metadata: IntervalSet.metadata(occurrences))
  end

  defp coalesce_group(group) do
    case IntervalSet.new(group, coalesce: true) do
      {:ok, set} -> IntervalSet.to_list(set)
      {:error, _} -> group
    end
  end

  # A day is just a day until it is projected onto the Gregorian timeline. With a
  # non-midnight `day_start`, each occurrence dated in a sunset-starting calendar
  # (Islamic, Hebrew) is projected to the datetime interval that begins when its
  # day begins, keeping its metadata; every other occurrence, and `:midnight`,
  # is left as the civil day it already is.
  defp project_day_start(occurrences, :midnight), do: {:ok, occurrences}

  defp project_day_start(occurrences, day_start) do
    occurrences
    |> IntervalSet.map(&project_occurrence(&1, day_start))
    |> IntervalSet.new(metadata: IntervalSet.metadata(occurrences))
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
