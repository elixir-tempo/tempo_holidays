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
          known_unsupported: %{atom() => non_neg_integer()},
          mismatched: %{atom() => non_neg_integer()},
          divergent: %{atom() => non_neg_integer()},
          samples: [map()],
          prepared: %{{String.t(), [Rule.t()] | nil} => Rule.t()}
        }

  @doc "Run conformance over the given fixtures, returning aggregate stats."
  @spec run([Tempo.Holidays.Fixtures.fixture()], keyword()) :: stats()
  def run(fixtures, options \\ []) do
    sample_limit = Keyword.get(options, :samples, 25)
    gate_indices = gate_indices(fixtures)

    fixtures
    |> Enum.reduce(initial(), &check_fixture(&1, &2, gate_indices, sample_limit))
  end

  defp initial do
    %{
      rules: 0,
      matched: 0,
      unsupported: %{},
      known_unsupported: %{},
      mismatched: %{},
      divergent: %{},
      samples: [],
      prepared: %{}
    }
  end

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
    {code, division, subdivision} = split_territory(territory)

    case Data.for_territory(code, division, subdivision) do
      {:ok, holidays} -> Enum.group_by(holidays, & &1.rule.source, & &1.rule)
      {:error, _absent} -> %{}
    end
  end

  # A fixture territory is `<country>[-<state>[-<region>]]`, e.g. `US-CA` or
  # `BR-SP-SP`.
  defp split_territory(territory) do
    case String.split(territory, "-", parts: 3) do
      [code] -> {code, nil, nil}
      [code, division] -> {code, division, nil}
      [code, division, subdivision] -> {code, division, subdivision}
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
      holidays: holidays,
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
    context = Map.merge(base, %{rule: rule, expected: expected, present: present_fun(base, rule)})

    case prepared_rule(rule, context.gates, acc) do
      {:ok, prepared, acc} -> check_materialised(prepared, context, acc)
      {:error, acc} -> record_unsupported(acc, rule)
    end
  end

  # Compile, gate and prepare each distinct rule once — keyed by its source and
  # the gates the territory's built data gives it — so its recurrence is built a
  # single time however many fixtures exercise it.
  defp prepared_rule(rule, gates, acc) do
    key = {rule, Map.get(gates, rule)}

    case Map.fetch(acc.prepared, key) do
      {:ok, prepared} -> {:ok, prepared, acc}
      :error -> compile_and_prepare(Compiler.compile(rule), gates, key, acc)
    end
  end

  defp compile_and_prepare({:ok, compiled}, gates, key, acc) do
    prepared = compiled |> attach_gates(gates) |> Rule.prepare()
    {:ok, prepared, %{acc | prepared: Map.put(acc.prepared, key, prepared)}}
  end

  defp compile_and_prepare({:error, _reason}, _gates, _key, acc), do: {:error, acc}

  # A rule that does not compile is a defect unless it is an accepted known gap
  # (`accepted_unsupported?/1`), which is tracked in its own bucket — the way
  # `divergent` sits apart from `mismatched`.
  defp record_unsupported(acc, rule) do
    bucket = if accepted_unsupported?(rule), do: :known_unsupported, else: :unsupported
    bump(acc, bucket, feature(rule))
  end

  # Rules we knowingly do not compile yet, excluded from the `unsupported` gate.
  # `bengali-revised` needs a Bengali calendar in Calendrical before a
  # `tempo_holidays` tier can exist; the other two are a rare compound Easter
  # offset and an expired doubly-nested US rule, tracked as deferred follow-ups.
  # All are gaps, not defects.
  defp accepted_unsupported?(rule) do
    String.starts_with?(rule, "bengali") or
      rule =~ ~r/^Thursday before easter/i or
      rule =~ ~r/^friday before 1st monday before 06-01/i
  end

  # A `(gregorian_days, type) -> boolean()` for the conditional second pass,
  # built from date-holidays' own output: the fixture's other entries, of the
  # right type, on that day. The rule under test is excluded by identity —
  # exactly as `PostRule` skips the rule it is resolving — so an if-holiday day
  # never coincides with itself.
  defp present_fun(%{holidays: holidays}, current_rule) do
    date_types =
      holidays
      |> Enum.reject(&(&1.rule == current_rule))
      |> Enum.reduce(MapSet.new(), fn holiday, set ->
        case fixture_days(holiday.date) do
          nil -> set
          days -> MapSet.put(set, {days, fixture_type(holiday.type)})
        end
      end)

    fn days, type -> MapSet.member?(date_types, {days, type}) end
  end

  defp fixture_days(date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> Date.to_gregorian_days(date)
      {:error, _} -> nil
    end
  end

  @fixture_types %{
    "public" => :public,
    "bank" => :bank,
    "school" => :school,
    "observance" => :observance,
    "optional" => :optional
  }

  defp fixture_type(type), do: Map.get(@fixture_types, type, :public)

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
        ours = compiled |> resolve_if_conditional(intervals, context) |> to_date_set()

        if MapSet.subset?(context.expected, ours) and MapSet.subset?(ours, context.all_dates) do
          %{acc | matched: acc.matched + 1}
        else
          record(acc, context, %{expected: context.expected, ours: ours})
        end

      {:error, _} ->
        record(acc, context, %{error: :materialise})
    end
  end

  # A bridge / if-holiday rule's base occurrences are resolved against the
  # year's holidays (`context.present`) in the second pass, mirroring
  # `Tempo.Holidays.materialise/2`; every other rule stands as materialised.
  defp resolve_if_conditional(compiled, intervals, context) do
    if Rule.conditional?(compiled) do
      case Rule.resolve_conditional(compiled, intervals, context.year_tempo, context.present) do
        {:ok, resolved} -> resolved
        {:error, _} -> intervals
      end
    else
      intervals
    end
  end

  defp to_date_set(intervals), do: intervals |> Enum.map(&gregorian/1) |> MapSet.new()

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
    known_unsupported = stats.known_unsupported |> Map.values() |> Enum.sum()
    mismatched = stats.mismatched |> Map.values() |> Enum.sum()
    divergent = stats.divergent |> Map.values() |> Enum.sum()

    """
    rules checked:     #{stats.rules}
    matched:           #{stats.matched}
    unsupported:       #{unsupported}  #{inspect(sorted(stats.unsupported))}
    known unsupported: #{known_unsupported}  #{inspect(sorted(stats.known_unsupported))}  (accepted gaps: Bengali calendar, two rare shapes)
    mismatched:        #{mismatched}  #{inspect(sorted(stats.mismatched))}
    divergent:         #{divergent}  #{inspect(sorted(stats.divergent))}  (accepted reference differences)
    """
  end

  defp sorted(map), do: Enum.sort_by(map, fn {_k, v} -> -v end)
end
