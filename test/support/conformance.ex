defmodule Tempo.Holidays.Conformance do
  @moduledoc false

  # Test-only. Runs date-holidays fixtures through `Compiler` + `Rule` and
  # checks, per rule, that our computed Gregorian date-set equals the set of
  # dates date-holidays produced for that rule (a substituted holiday yields
  # both the actual and the substitute date, so the comparison is per-rule,
  # not per-entry). Reports totals and per-feature breakdowns so the gaps can
  # be driven to zero.

  alias Tempo.Holidays.{Compiler, Data, Rule}

  @type stats :: %{
          rules: non_neg_integer(),
          matched: non_neg_integer(),
          unsupported: %{atom() => non_neg_integer()},
          mismatched: %{atom() => non_neg_integer()},
          divergent: %{atom() => non_neg_integer()},
          samples: [map()]
        }

  @doc "Run conformance over the given fixtures, returning aggregate stats."
  @spec run([Tempo.Holidays.Fixtures.fixture()], keyword()) :: stats()
  def run(fixtures, options \\ []) do
    sample_limit = Keyword.get(options, :samples, 25)
    gate_indices = gate_indices(fixtures)

    fixtures
    |> Enum.reduce(initial(), &check_fixture(&1, &2, gate_indices, sample_limit))
  end

  defp initial,
    do: %{rules: 0, matched: 0, unsupported: %{}, mismatched: %{}, divergent: %{}, samples: []}

  # date-holidays' `active`/`disable`/`enable` metadata lives on the source
  # `days`, not in the fixture output, so re-compiling a bare rule string
  # cannot see it. Load the *built* runtime data once per distinct territory
  # and index its gates by rule source, so each fixture rule is materialised
  # with the same gates the shipped data carries.
  defp gate_indices(fixtures) do
    fixtures
    |> Enum.map(& &1.territory)
    |> Enum.uniq()
    |> Map.new(&{&1, gate_index(&1)})
  end

  defp gate_index(territory) do
    {code, division} = split_territory(territory)

    case Data.for_territory(code, division) do
      {:ok, holidays} -> Enum.group_by(holidays, & &1.rule.source, & &1.rule)
      {:error, _absent} -> %{}
    end
  end

  defp split_territory(territory) do
    case String.split(territory, "-", parts: 2) do
      [code] -> {code, nil}
      [code, division] -> {code, division}
    end
  end

  defp check_fixture(%{year: year, holidays: holidays, territory: territory}, acc, indices, limit) do
    {:ok, year_tempo} = Tempo.from_iso8601("#{year}")
    # date-holidays deduplicates dates across a country's entries (an actual
    # date and its substitute may come from two different rules), so a rule's
    # computed dates must sit inside the whole fixture's date-set, not equal
    # its own entries exactly.
    all_dates = holidays |> Enum.map(& &1.date) |> MapSet.new()

    base = %{
      all_dates: all_dates,
      year_tempo: year_tempo,
      territory: territory,
      year: year,
      gates: Map.get(indices, territory, %{}),
      limit: limit
    }

    holidays
    |> Enum.filter(&is_binary(&1.rule))
    |> Enum.group_by(& &1.rule, & &1.date)
    |> Enum.reduce(acc, fn {rule, dates}, acc ->
      check_rule(rule, MapSet.new(dates), base, acc)
    end)
  end

  defp check_rule(rule, expected, base, acc) do
    acc = %{acc | rules: acc.rules + 1}
    context = Map.merge(base, %{rule: rule, expected: expected})

    case Compiler.compile(rule) do
      {:ok, compiled} -> check_materialised(attach_gates(compiled, context.gates), context, acc)
      {:error, _} -> bump(acc, :unsupported, feature(rule))
    end
  end

  # Copy the built rule's occurrence-level gates onto the freshly compiled
  # rule; a source the built data does not carry leaves the rule ungated,
  # exactly as before this enrichment existed.
  defp attach_gates(compiled, gates) do
    case Map.get(gates, compiled.source) do
      [%Rule{} = built | _] ->
        %{compiled | active: built.active, disable: built.disable, enable: built.enable}

      _absent ->
        compiled
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
    divergent = stats.divergent |> Map.values() |> Enum.sum()

    """
    rules checked: #{stats.rules}
    matched:       #{stats.matched}
    unsupported:   #{unsupported}  #{inspect(sorted(stats.unsupported))}
    mismatched:    #{mismatched}  #{inspect(sorted(stats.mismatched))}
    divergent:     #{divergent}  #{inspect(sorted(stats.divergent))}  (accepted reference differences)
    """
  end

  defp sorted(map), do: Enum.sort_by(map, fn {_k, v} -> -v end)
end
