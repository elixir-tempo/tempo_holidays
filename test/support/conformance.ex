defmodule Tempo.Holidays.Conformance do
  @moduledoc false

  # Test-only. Runs date-holidays fixtures through `Compiler` + `Rule` and
  # checks, per rule, that our computed Gregorian date-set equals the set of
  # dates date-holidays produced for that rule (a substituted holiday yields
  # both the actual and the substitute date, so the comparison is per-rule,
  # not per-entry). Reports totals and per-feature breakdowns so the gaps can
  # be driven to zero.

  alias Tempo.Holidays.{Compiler, Rule}

  @type stats :: %{
          rules: non_neg_integer(),
          matched: non_neg_integer(),
          unsupported: %{atom() => non_neg_integer()},
          mismatched: %{atom() => non_neg_integer()},
          samples: [map()]
        }

  @doc "Run conformance over the given fixtures, returning aggregate stats."
  @spec run([Tempo.Holidays.Fixtures.fixture()], keyword()) :: stats()
  def run(fixtures, options \\ []) do
    sample_limit = Keyword.get(options, :samples, 25)

    fixtures
    |> Enum.reduce(initial(), &check_fixture(&1, &2, sample_limit))
  end

  defp initial, do: %{rules: 0, matched: 0, unsupported: %{}, mismatched: %{}, samples: []}

  defp check_fixture(%{year: year, holidays: holidays, territory: territory}, acc, limit) do
    {:ok, year_tempo} = Tempo.from_iso8601("#{year}")
    # date-holidays deduplicates dates across a country's entries (an actual
    # date and its substitute may come from two different rules), so a rule's
    # computed dates must sit inside the whole fixture's date-set, not equal
    # its own entries exactly.
    all_dates = holidays |> Enum.map(& &1.date) |> MapSet.new()

    holidays
    |> Enum.filter(&is_binary(&1.rule))
    |> Enum.group_by(& &1.rule, & &1.date)
    |> Enum.reduce(acc, fn {rule, dates}, acc ->
      check_rule(rule, MapSet.new(dates), all_dates, year_tempo, territory, year, acc, limit)
    end)
  end

  defp check_rule(rule, expected, all_dates, year_tempo, territory, year, acc, limit) do
    acc = %{acc | rules: acc.rules + 1}

    context = %{
      rule: rule,
      expected: expected,
      all_dates: all_dates,
      year_tempo: year_tempo,
      territory: territory,
      year: year,
      limit: limit
    }

    case Compiler.compile(rule) do
      {:ok, compiled} -> check_materialised(compiled, context, acc)
      {:error, _} -> bump(acc, :unsupported, feature(rule))
    end
  end

  defp check_materialised(compiled, context, acc) do
    case Rule.materialise(compiled, context.year_tempo) do
      {:ok, intervals} ->
        ours = intervals |> Enum.map(&gregorian/1) |> MapSet.new()

        if MapSet.subset?(context.expected, ours) and MapSet.subset?(ours, context.all_dates) do
          %{acc | matched: acc.matched + 1}
        else
          record(acc, context, %{expected: context.expected, ours: ours})
        end

      {:error, _} ->
        record(acc, context, %{error: :materialise})
    end
  end

  defp record(acc, context, detail) do
    sample =
      Map.merge(%{territory: context.territory, year: context.year, rule: context.rule}, detail)

    acc
    |> bump(:mismatched, feature(context.rule))
    |> add_sample(sample, context.limit)
  end

  # ── our Gregorian date for one materialised interval ────────────────

  defp gregorian(interval) do
    with tempo <- Tempo.Interval.from(interval),
         {:ok, date} <- Tempo.to_date(tempo),
         {:ok, gregorian} <- Date.convert(date, Calendrical.Gregorian) do
      Calendar.strftime(gregorian, "%Y-%m-%d")
    else
      _ -> "??"
    end
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
    mismatched = stats.mismatched |> Map.values() |> Enum.sum()

    """
    rules checked: #{stats.rules}
    matched:       #{stats.matched}
    unsupported:   #{unsupported}  #{inspect(sorted(stats.unsupported))}
    mismatched:    #{mismatched}  #{inspect(sorted(stats.mismatched))}
    """
  end

  defp sorted(map), do: Enum.sort_by(map, fn {_k, v} -> -v end)
end
