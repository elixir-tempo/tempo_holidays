defmodule Tempo.Holidays.Compiler do
  @moduledoc """
  Compiles [date-holidays](https://github.com/commenthol/date-holidays) rule
  strings into `t:Tempo.Holidays.Rule.t/0`.

  This is the slice covering the grammar tiers:

  * **Fixed** — `"MM-DD"` (e.g. `"12-25"`).

  * **Weekday-in-month** — `"<ordinal> <Weekday> in <Month>"`, where the
    ordinal is a word (`first` … `fifth`, `last`) or a numeral (`"2nd Monday
    in June"`, `"last Monday in May"`).

  * **Easter-relative** — `"easter"` / `"orthodox"` with an optional signed
    day offset (e.g. `"easter -2"` for Good Friday).

  Any of these may carry an **observed-date substitution** suffix — one or
  more `"if <weekdays> then (next|previous) <weekday>"` clauses, with
  `weekend` shorthand for `saturday,sunday`. "If it falls on a weekend, take
  the following Monday" and the US "if saturday then previous friday if
  sunday then next monday" both compile to the rule's
  `t:Tempo.Holidays.Rule.substitute/0`.

  Rule strings it does not yet understand return `{:error, {:unsupported,
  rule}}` rather than raising, so an unrecognised entry is skipped rather
  than crashing a caller.

  """

  alias Tempo.Holidays.Rule

  # ISO 8601 weekday numbers (Monday = 1 … Sunday = 7), as the `I<n>K`
  # instance selector expects: `FL6M2I1KN` is "the 2nd Monday of June".
  @weekdays %{
    "monday" => 1,
    "tuesday" => 2,
    "wednesday" => 3,
    "thursday" => 4,
    "friday" => 5,
    "saturday" => 6,
    "sunday" => 7
  }

  @months %{
    "january" => 1,
    "february" => 2,
    "march" => 3,
    "april" => 4,
    "may" => 5,
    "june" => 6,
    "july" => 7,
    "august" => 8,
    "september" => 9,
    "october" => 10,
    "november" => 11,
    "december" => 12
  }

  @doc """
  Compile a date-holidays rule string into a `t:Tempo.Holidays.Rule.t/0`.

  ### Arguments

  * `rule` is a date-holidays rule string.

  ### Returns

  * `{:ok, t:Tempo.Holidays.Rule.t/0}` on a recognised rule.

  * `{:error, {:unsupported, rule}}` for a rule outside this slice's tiers.

  ### Examples

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("12-25")
      iex> {rule.kind, rule.month, rule.day}
      {:fixed, 12, 25}

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("2nd Monday in June")
      iex> {rule.kind, rule.count, rule.weekday, rule.month}
      {:weekday, 2, 1, 6}

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("easter -2")
      iex> {rule.kind, rule.offset}
      {:easter, -2}

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("01-26 if weekend then next monday")
      iex> {rule.kind, rule.month, rule.day, rule.substitute}
      {:fixed, 1, 26, [{[6, 7], :next, 1}]}

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("last Monday in May")
      iex> {rule.kind, rule.count, rule.weekday, rule.month}
      {:weekday, -1, 1, 5}

  """
  @spec compile(String.t()) :: {:ok, Rule.t()} | {:error, {:unsupported, String.t()}}
  def compile(rule) when is_binary(rule) do
    {base, substitute} = extract_substitution(rule)

    case compile_fixed(base) || compile_weekday(base) || compile_easter(base) do
      {:ok, compiled} -> {:ok, %{compiled | substitute: substitute, source: rule}}
      nil -> {:error, {:unsupported, rule}}
    end
  end

  # ── fixed: "MM-DD" ──────────────────────────────────────────────────
  defp compile_fixed(rule) do
    case Regex.run(~r/^\s*(\d{1,2})-(\d{1,2})\s*$/, rule) do
      [_, month, day] ->
        {:ok,
         %Rule{
           kind: :fixed,
           month: String.to_integer(month),
           day: String.to_integer(day),
           source: rule
         }}

      nil ->
        nil
    end
  end

  # ── weekday-in-month: "2nd Monday in June", "last Monday in May" ─────
  defp compile_weekday(rule) do
    pattern = ~r/^\s*(\w+)\s+(\w+)\s+in\s+(\w+)\s*$/i

    with [_, ordinal, weekday, month] <- Regex.run(pattern, rule),
         {:ok, count} <- parse_ordinal(ordinal),
         {:ok, code} <- Map.fetch(@weekdays, String.downcase(weekday)),
         {:ok, month_number} <- Map.fetch(@months, String.downcase(month)) do
      {:ok,
       %Rule{
         kind: :weekday,
         count: count,
         weekday: code,
         month: month_number,
         source: rule
       }}
    else
      _ -> nil
    end
  end

  # An ordinal is a word (`first` … `fifth`, `last`) or a digit with an
  # English suffix (`1st`, `2nd`). `last` is `-1` — the ISO `-1I` selector.
  @word_ordinals %{
    "first" => 1,
    "second" => 2,
    "third" => 3,
    "fourth" => 4,
    "fifth" => 5,
    "last" => -1
  }

  defp parse_ordinal(ordinal) do
    case Map.fetch(@word_ordinals, String.downcase(ordinal)) do
      {:ok, count} ->
        {:ok, count}

      :error ->
        case Regex.run(~r/^(\d+)(?:st|nd|rd|th)$/i, ordinal) do
          [_, digits] -> {:ok, String.to_integer(digits)}
          nil -> :error
        end
    end
  end

  # ── easter-relative: "easter", "easter -2", "orthodox 1" ────────────
  defp compile_easter(rule) do
    case Regex.run(~r/^\s*(easter|orthodox)\s*([+-]?\d+)?\s*$/i, rule) do
      [_, anchor | rest] ->
        offset = rest |> List.first() |> parse_offset()

        {:ok,
         %Rule{
           kind: String.to_existing_atom(String.downcase(anchor)),
           offset: offset,
           source: rule
         }}

      nil ->
        nil
    end
  end

  defp parse_offset(nil), do: 0
  defp parse_offset(""), do: 0
  defp parse_offset(number), do: String.to_integer(number)

  # ── observed-date substitution: "… if weekend then next monday" ─────
  #
  # Splits any `if <weekdays> then (next|previous) <weekday>` clauses off
  # the base rule and compiles them to `{trigger_weekdays, direction,
  # target_weekday}` in ISO numbering. `weekend` expands to Saturday and
  # Sunday; a comma list (`saturday,sunday`) is taken verbatim. Several
  # clauses may chain — the US rule is `if saturday then previous friday
  # if sunday then next monday`.
  @substitute_pattern ~r/if\s+([a-z,]+)\s+then\s+(next|previous)\s+([a-z]+)/i

  defp extract_substitution(rule) do
    clauses =
      @substitute_pattern
      |> Regex.scan(rule)
      |> Enum.flat_map(&parse_substitute_clause/1)

    base =
      rule
      |> String.replace(@substitute_pattern, "")
      |> String.replace(~r/\s+and\s*$/i, "")
      |> String.trim()

    {base, if(clauses == [], do: nil, else: clauses)}
  end

  defp parse_substitute_clause([_match, triggers, direction, target]) do
    with {:ok, trigger_days} <- parse_weekday_set(triggers),
         {:ok, target_day} <- Map.fetch(@weekdays, String.downcase(target)) do
      [{trigger_days, direction_atom(String.downcase(direction)), target_day}]
    else
      _ -> []
    end
  end

  defp direction_atom("next"), do: :next
  defp direction_atom("previous"), do: :previous

  defp parse_weekday_set(triggers) do
    case String.downcase(triggers) do
      "weekend" ->
        {:ok, [6, 7]}

      list ->
        days = list |> String.split(",") |> Enum.map(&Map.get(@weekdays, &1))
        if days != [] and Enum.all?(days, &is_integer/1), do: {:ok, days}, else: :error
    end
  end
end
