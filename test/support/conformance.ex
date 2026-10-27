defmodule Tempo.Holidays.Conformance do
  @moduledoc false

  # Test-only. Runs date-holidays fixtures through the public path: for each
  # territory and year, the holidays `Tempo.Holidays.holidays/2` gives with
  # `dates: :both` (the dates as date-holidays gives them, a substituted
  # holiday's own date and its substitute), converted over the year, and
  # checks, rule by rule, that the days our occurrences of a rule start on hold
  # every date date-holidays gives that rule and lie among the dates it gives
  # the year. Reports totals and per-feature breakdowns so the gaps can be
  # driven to zero.

  alias Tempo.Holidays
  alias Tempo.Holidays.Data
  alias Tempo.Interval
  alias Tempo.IntervalSet

  @type stats :: %{
          rules: non_neg_integer(),
          matched: non_neg_integer(),
          unsupported: %{atom() => non_neg_integer()},
          known_unsupported: %{atom() => non_neg_integer()},
          mismatched: %{atom() => non_neg_integer()},
          divergent: %{atom() => non_neg_integer()},
          samples: [map()]
        }

  @doc "Run conformance over the given fixtures, returning aggregate stats."
  @spec run([Tempo.Holidays.Fixtures.fixture()], keyword()) :: stats()
  def run(fixtures, options \\ []) do
    sample_limit = Keyword.get(options, :samples, 25)
    Enum.reduce(fixtures, initial(), &check_fixture(&1, &2, sample_limit))
  end

  defp initial do
    %{
      rules: 0,
      matched: 0,
      unsupported: %{},
      known_unsupported: %{},
      mismatched: %{},
      divergent: %{},
      samples: []
    }
  end

  defp check_fixture(%{year: year, holidays: holidays, territory: territory}, acc, limit) do
    # date-holidays deduplicates dates across a country's entries (an actual
    # date and its substitute may come from two different rules), so a rule's
    # computed dates must sit inside the whole fixture's date-set, not equal
    # its own entries exactly.
    all_dates = for %{date: %Date{} = date} <- holidays, into: MapSet.new(), do: date
    {code, subdivision} = split_territory(territory)

    context = %{
      all_dates: all_dates,
      territory: territory,
      year: year,
      limit: limit,
      ours: our_occurrences(code, subdivision, year),
      rules: our_rules(code, subdivision),
      parent_rules: parent_rules(code, subdivision),
      unknown_subdivision: unknown_subdivision?(code, subdivision)
    }

    holidays
    |> Enum.filter(&(is_binary(&1.rule) and is_struct(&1.date, Date)))
    |> Enum.group_by(& &1.rule, & &1.date)
    |> Enum.reduce(acc, fn {rule, dates}, acc ->
      check_rule(rule, MapSet.new(dates), context, acc)
    end)
  end

  # A fixture territory is `<country>[-<state>[-<region>]]`, e.g. `US-CA` or
  # `BR-SP-SP`: the country, and the subdivision's path within it.
  defp split_territory(territory) do
    case String.split(territory, "-", parts: 2) do
      [code] -> {code, nil}
      [code, subdivision] -> {code, subdivision}
    end
  end

  # Our occurrences that year: by rule, the days they start on in the year,
  # as date-holidays lists a holiday in the year it starts in; and every
  # occurrence the year holds, as the dates it runs from and to.
  defp our_occurrences(code, subdivision, year) do
    with {:ok, holidays} <- holidays_for(code, subdivision),
         {:ok, window} <- Tempo.new(year: year),
         {:ok, occurrences} <- Tempo.to_interval(holidays, within: window) do
      members = IntervalSet.members(occurrences)
      {:ok, %{starts: starts_by_rule(members, year), spans: spans(members)}}
    end
  end

  defp starts_by_rule(occurrences, year) do
    for occurrence <- occurrences,
        {:ok, date} <- [date_of(Interval.from(occurrence))],
        date.year == year,
        reduce: %{} do
      starts ->
        Map.update(
          starts,
          Tempo.metadata(occurrence)[:id],
          MapSet.new([date]),
          &MapSet.put(&1, date)
        )
    end
  end

  defp spans(occurrences) do
    for occurrence <- occurrences,
        {:ok, from} <- [date_of(Interval.from(occurrence))],
        {:ok, to} <- [date_of(Interval.to(occurrence))] do
      {from, to}
    end
  end

  # date-holidays gives a subdivision it holds no data for the country's
  # holidays, and its fixtures for such a subdivision (Mauritius' districts)
  # are the country's. The library refuses an unknown subdivision; the harness
  # reads the country's for it, as date-holidays does.
  defp holidays_for(code, subdivision) do
    case Holidays.holidays(code, subdivision: subdivision, dates: :both) do
      {:error, {:unknown_subdivision, _subdivision}} -> Holidays.holidays(code, dates: :both)
      result -> result
    end
  end

  # The rules the built data holds for the territory.
  defp our_rules(code, subdivision) do
    result =
      case Data.for_territory(code, subdivision) do
        {:error, {:unknown_subdivision, _subdivision}} -> Data.for_territory(code)
        result -> result
      end

    case result do
      {:ok, holidays} -> MapSet.new(holidays, & &1.rule)
      {:error, _reason} -> MapSet.new()
    end
  end

  # A subdivision date-holidays' data does not define: its fixtures (Mauritius'
  # districts) are the country's of an older release, and list rules the
  # data no longer holds.
  defp unknown_subdivision?(_code, nil) do
    false
  end

  defp unknown_subdivision?(code, subdivision) do
    match?({:error, {:unknown_subdivision, _subdivision}}, Data.subdivision(code, subdivision))
  end

  # The rules of the level a subdivision is in: a region's state, a state's
  # country, and none for the country itself.
  defp parent_rules(_code, nil) do
    MapSet.new()
  end

  defp parent_rules(code, subdivision) do
    case String.split(subdivision, "-", parts: 2) do
      [state, _region] -> our_rules(code, state)
      [_state] -> our_rules(code, nil)
    end
  end

  defp check_rule(rule, expected, context, acc) do
    acc = %{acc | rules: acc.rules + 1}
    context = Map.merge(context, %{rule: rule, expected: expected})

    case context.ours do
      {:ok, ours} -> check_ours(Map.fetch(ours.starts, rule), ours, context, acc)
      {:error, reason} -> record(acc, context, %{error: reason})
    end
  end

  defp check_ours({:ok, starts}, _ours, context, acc) do
    if MapSet.subset?(context.expected, starts) and MapSet.subset?(starts, context.all_dates) do
      %{acc | matched: acc.matched + 1}
    else
      record(acc, context, %{expected: context.expected, ours: starts})
    end
  end

  # A rule with no occurrence of its own that year: the January half of a
  # period date-holidays splits at the year end, which we hold as one period
  # begun before its date; a rule a subdivision's data removes (`false`) from
  # the level above, which date-holidays gives it all the same, an accepted
  # difference; a rule our data does not hold; or a mismatch.
  defp check_ours(:error, ours, context, acc) do
    cond do
      Enum.all?(context.expected, &continued?(&1, ours.spans)) ->
        %{acc | matched: acc.matched + 1}

      removed_by_subdivision?(context) ->
        bump(acc, :divergent, :removed_by_subdivision)

      context.unknown_subdivision and not MapSet.member?(context.rules, context.rule) ->
        bump(acc, :divergent, :stale_subdivision_fixture)

      not MapSet.member?(context.rules, context.rule) ->
        record_unsupported(acc, context.rule)

      true ->
        record(acc, context, %{expected: context.expected, ours: MapSet.new()})
    end
  end

  defp removed_by_subdivision?(context) do
    MapSet.member?(context.parent_rules, context.rule) and
      not MapSet.member?(context.rules, context.rule)
  end

  defp continued?(date, spans) do
    Enum.any?(spans, fn {from, to} ->
      Date.compare(from, date) == :lt and Date.compare(date, to) != :gt
    end)
  end

  # A rule our data does not hold is a defect unless it is an accepted gap
  # (`accepted_unsupported?/1`), which is tracked in its own bucket — the way
  # `divergent` sits apart from `mismatched`.
  defp record_unsupported(acc, rule) do
    bucket = if accepted_unsupported?(rule), do: :known_unsupported, else: :unsupported
    bump(acc, bucket, feature(rule))
  end

  # The rules `Tempo.DateRule` does not read: the Bengali calendar, which
  # needs a Bengali calendar in Calendrical. A gap, not a defect.
  defp accepted_unsupported?(rule) do
    String.starts_with?(rule, "bengali")
  end

  defp record(acc, context, detail) do
    feature = feature(context.rule)

    if accepted_divergence?(feature) do
      # A known, accepted difference between date-holidays and our upstream —
      # not a defect — so it is tracked apart from `mismatched` and not sampled.
      bump(acc, :divergent, feature)
    else
      sample =
        Map.merge(%{territory: context.territory, year: context.year, rule: context.rule}, detail)

      acc
      |> bump(:mismatched, feature)
      |> add_sample(sample, context.limit)
    end
  end

  # Islamic civil dates diverge because date-holidays uses a fixed lookup table
  # with a 6pm (sunset-approximation) day-start converted to the country's
  # timezone, while Calendrical uses the authoritative Umm al-Qura anchored at
  # midnight. This is a reference-model difference, not a defect; pending a
  # decision on whether to offer a sunset day-start, these are recorded as
  # divergent rather than mismatched.
  defp accepted_divergence?(:islamic), do: true
  defp accepted_divergence?(_feature), do: false

  # The date a day of an occurrence is, in the calendar of the fixture's dates
  # (`Calendar.ISO`), so the two are compared as dates.
  defp date_of(day) do
    with {:ok, date} <- Tempo.to_date(day), do: Date.convert(date, Calendar.ISO)
  end

  # ── bookkeeping ─────────────────────────────────────────────────────

  defp bump(acc, key, category) do
    Map.update!(acc, key, &Map.update(&1, category, 1, fn n -> n + 1 end))
  end

  defp add_sample(%{samples: samples} = acc, _sample, limit) when length(samples) >= limit,
    do: acc

  defp add_sample(acc, sample, _limit), do: %{acc | samples: [sample | acc.samples]}

  # ── coarse feature classification for reporting ─────────────────────

  @features [
    islamic:
      ~r/ramadan|shawwal|muharram|hijjah|rajab|sha'?ban|rabi|jumada|dhu |safar|hijri|islamic/,
    hebrew:
      ~r/tishrei|cheshvan|kislev|tevet|shevat|adar|nisan|iyar|sivan|tammuz|elul|hebrew|hanukkah|yom |rosh /,
    chinese: ~r/chinese|lunar|solar term|dongzhi|qingming|buddha/,
    astronomical: ~r/solstice|equinox/,
    other_calendar: ~r/persian|bengali|ethiopian|coptic|julian|nepal|thai/,
    year_filter: ~r/\bsince\b|\buntil\b|in even|in odd|\d{4}-\d{2}-\d{2}/,
    substitutes: ~r/substitutes/,
    time_of_day: ~r/\d{1,2}:\d{2}/,
    month_anchor:
      ~r/(before|after) (january|february|march|april|may|june|july|august|september|october|november|december)/,
    nested_weekday: ~r/(before|after) \d?\d?(st|nd|rd|th)?\s*\w+day/
  ]

  @doc "A coarse feature label for a rule string, for grouping the gaps."
  @spec feature(String.t()) :: atom()
  def feature(rule) do
    downcased = String.downcase(rule)

    Enum.find_value(@features, :other, fn {label, regex} ->
      if Regex.match?(regex, downcased), do: label
    end)
  end

  @doc "Format stats as a readable multi-line summary."
  @spec summary(stats()) :: String.t()
  def summary(stats) do
    unsupported = stats.unsupported |> Map.values() |> Enum.sum()
    known_unsupported = stats.known_unsupported |> Map.values() |> Enum.sum()
    mismatched = stats.mismatched |> Map.values() |> Enum.sum()
    divergent = stats.divergent |> Map.values() |> Enum.sum()

    """
    rules checked:     #{stats.rules}
    matched:           #{stats.matched}
    unsupported:       #{unsupported}  #{inspect(sorted(stats.unsupported))}
    known unsupported: #{known_unsupported}  #{inspect(sorted(stats.known_unsupported))}  (accepted gap: the Bengali calendar)
    mismatched:        #{mismatched}  #{inspect(sorted(stats.mismatched))}
    divergent:         #{divergent}  #{inspect(sorted(stats.divergent))}  (accepted reference differences)
    """
  end

  defp sorted(map), do: Enum.sort_by(map, fn {_k, v} -> -v end)
end
