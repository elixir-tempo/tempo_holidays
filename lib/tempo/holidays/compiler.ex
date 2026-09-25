defmodule Tempo.Holidays.Compiler do
  @moduledoc """
  Compiles [date-holidays](https://github.com/commenthol/date-holidays) rule
  strings into `t:Tempo.Holidays.Rule.t/0`.

  This is the slice covering the grammar tiers:

  * **Fixed** — `"MM-DD"` (e.g. `"12-25"`).

  * **Weekday-in-month** — `"<ordinal> <Weekday> in <Month>"`, where the
    ordinal is a word (`first` … `fifth`, `last`) or a numeral (`"2nd Monday
    in June"`, `"last Monday in May"`).

  * **Relative weekday** — `"<weekday> before|after <MM-DD>"`, the nearest
    weekday strictly before or after a fixed date (`"monday before 06-01"`
    is US Memorial Day).

  * **Calendar dates** — `"<day> <month>"` in the Islamic (`"9 Dhu al-Hijjah
    P4D"`), Hebrew (`"15 Nisan"`) or Persian (`"1 Farvardin"`) calendar, with
    an optional `P<n>D` span. Materialised in that calendar.

  * **Julian fixed** — `"julian MM-DD"` (`"julian 12-25"` is Orthodox
    Christmas), a fixed date in the Julian calendar, converted to Gregorian.

  * **Lunisolar** — Chinese `"chinese <month>-<leap>-<day>"` (`"chinese
    01-0-01"` is Chinese New Year), Korean `"korean <month>-<leap>-<day>"`
    (`"korean 01-0-01"` is Seollal) and Vietnamese `"vietnamese
    <month>-<leap>-<day>"` (`"vietnamese 1-0-1"` is Tết), returned in that
    calendar; plus the Chinese solar term `"chinese <term>-<day> solarterm"`
    (`"chinese 5-01 solarterm"` is Qingming), the day the sun reaches the term's
    longitude in China Standard Time.

  * **Equinox / solstice** — `"march equinox in +09:00"` (Japan's Vernal
    Equinox Day), `"december solstice"`, with an optional `"<n> days
    before/after"` and `"in <timezone>"`. A named zone needs the host app's
    time-zone database; a numeric offset and GMT do not.

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

  # ISO 8601 weekday numbers (Monday = 1 … Sunday = 7), as the `<n>K<i>I`
  # weekday-then-position selector expects: `FL6M1K2IN` is "the 2nd Monday of June".
  @weekdays %{
    "monday" => 1,
    "tuesday" => 2,
    "wednesday" => 3,
    "thursday" => 4,
    "friday" => 5,
    "saturday" => 6,
    "sunday" => 7
  }

  # Weekday-gate patterns (`on friday, monday`, `not on tuesday, saturday`),
  # precompiled from the weekday alternation.
  @weekday_alt "monday|tuesday|wednesday|thursday|friday|saturday|sunday|weekend"
  @weekday_gate_match ~r/\b(not\s+on|on)\s+((?:#{@weekday_alt})(?:\s*,\s*(?:#{@weekday_alt}))*)/i
  @weekday_gate_strip ~r/\b(?:not\s+)?on\s+(?:#{@weekday_alt})(?:\s*,\s*(?:#{@weekday_alt}))*/i

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

  # date-holidays' holiday-type vocabulary (`_type` in the grammar), the type a
  # bridge / if-holiday condition matches against. Absent means `:public`.
  @types %{
    "public" => :public,
    "bank" => :bank,
    "school" => :school,
    "observance" => :observance,
    "optional" => :optional
  }

  # Islamic (Hijri) month numbers, spelled as date-holidays writes them.
  @islamic_months %{
    "muharram" => 1,
    "safar" => 2,
    "rabi al-awwal" => 3,
    "rabi al-thani" => 4,
    "jumada al-awwal" => 5,
    "jumada al-thani" => 6,
    "rajab" => 7,
    "shaban" => 8,
    "ramadan" => 9,
    "shawwal" => 10,
    "dhu al-qadah" => 11,
    "dhu al-hijjah" => 12
  }

  # Persian (Solar Hijri) month numbers — fixed 1–12, no leap month.
  @persian_months %{
    "farvardin" => 1,
    "ordibehesht" => 2,
    "khordad" => 3,
    "tir" => 4,
    "mordad" => 5,
    "shahrivar" => 6,
    "mehr" => 7,
    "aban" => 8,
    "azar" => 9,
    "dey" => 10,
    "bahman" => 11,
    "esfand" => 12
  }

  # Hebrew month names → the traditional (RFC 7529) month numbers, which name
  # the same month in every year (Tishrei = 1 … Elul = 12); Tempo's `<n>m`
  # resolves each to its position in the year. The Adar that carries Purim is
  # 6 — Adar in an ordinary year, Adar II in a leap year — and date-holidays
  # writes it "AdarII" (the Adar before Nisan) in every year, so both "adar"
  # and "adarii" map to 6. Adar I, the leap month, follows month 5:
  # `{5, :leap}`. Common alternate spellings are included.
  @hebrew_months %{
    "tishrei" => 1,
    "tishri" => 1,
    "cheshvan" => 2,
    "heshvan" => 2,
    "marcheshvan" => 2,
    "kislev" => 3,
    "tevet" => 4,
    "shvat" => 5,
    "shevat" => 5,
    "adari" => {5, :leap},
    "adar" => 6,
    "adarii" => 6,
    "nisan" => 7,
    "iyyar" => 8,
    "iyar" => 8,
    "sivan" => 9,
    "tamuz" => 10,
    "tammuz" => 10,
    "av" => 11,
    "elul" => 12
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
      {:fixed, 1, 26, [{[6, 7], :next, 1, :shift}]}

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("last Monday in May")
      iex> {rule.kind, rule.count, rule.weekday, rule.month}
      {:weekday, -1, 1, 5}

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("monday before 06-01")
      iex> {rule.kind, rule.weekday, rule.direction, rule.month, rule.day}
      {:relative_weekday, 1, :before, 6, 1}

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("9 Dhu al-Hijjah P4D")
      iex> {rule.kind, rule.month, rule.day, rule.count}
      {:islamic, 12, 9, 4}

  """
  @spec compile(term()) :: {:ok, Rule.t()} | {:error, {:unsupported, term()}}
  def compile(rule) when is_binary(rule) do
    {without_conditions, conditions} =
      rule |> strip_time() |> strip_index() |> extract_year_conditions()

    {without_if_holiday, conditional} = extract_if_holiday(without_conditions)
    {base, substitute} = extract_substitution(without_if_holiday)

    case compile_base(base) do
      {:ok, compiled} ->
        {:ok, apply_conditions(compiled, conditions, substitute, conditional, rule)}

      nil ->
        {:error, {:unsupported, rule}}
    end
  end

  # An entry without a rule string (or any non-binary input) is not a
  # compilable rule; a library function never raises on caller input.
  def compile(other), do: {:error, {:unsupported, other}}

  # Each grammar tier, tried in order; the first to match the base rule
  # (conditions and substitution already stripped) wins, else `nil`.
  defp compile_base(base) do
    [
      &compile_bridge/1,
      &compile_specific_date/1,
      &compile_fixed/1,
      &compile_weekday/1,
      &compile_nested_weekday/1,
      &compile_nested_after_date/1,
      &compile_relative_weekday/1,
      &compile_julian/1,
      &compile_lunisolar/1,
      &compile_day_offset/1,
      &compile_chinese_solar/1,
      &compile_solar_event/1,
      &compile_calendar/1,
      &compile_easter/1
    ]
    |> Enum.find_value(fn tier -> tier.(base) end)
  end

  # A specific `YYYY-MM-DD` is a one-off holiday: a fixed date active only in
  # that year.
  defp compile_specific_date(rule) do
    case Regex.run(~r/^\s*(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+P\d+D)?\s*$/, rule) do
      [_, year, month, day] ->
        active = String.to_integer(year)

        {:ok,
         %Rule{
           kind: :fixed,
           month: String.to_integer(month),
           day: String.to_integer(day),
           from_year: active,
           to_year: active + 1,
           source: rule
         }}

      nil ->
        nil
    end
  end

  # A *bridge* day (`09-22 if 09-21 and 09-23 is public holiday`): a fixed date
  # kept only when every named date is itself a holiday of the type that year —
  # date-holidays' `PostRule.bridge`. The condition dates are carried as
  # `{month, day}` pairs on a `:bridge` conditional, resolved in the second pass
  # against the year's holiday set.
  @bridge_pattern ~r/^\s*(?:0*\d{1,4}-)?0?(?<month>\d{1,2})-0?(?<day>\d{1,2})\s+if\s+(?<on>.+?)\s+is\s+(?:(?<type>public|bank|school|observance|optional)\s+)?holiday\s*$/i

  defp compile_bridge(rule) do
    case Regex.named_captures(@bridge_pattern, rule) do
      %{"month" => month, "day" => day, "on" => on, "type" => type} ->
        compile_bridge(rule, month, day, on, type)

      nil ->
        nil
    end
  end

  defp compile_bridge(rule, month, day, on, type) do
    case parse_on_dates(on) do
      [] ->
        nil

      dates ->
        {:ok,
         %Rule{
           kind: :fixed,
           month: String.to_integer(month),
           day: String.to_integer(day),
           conditional: %{kind: :bridge, type: holiday_type(type), on: dates},
           source: rule
         }}
    end
  end

  # The `if <date> and <date> …` condition dates of a bridge, each `MM-DD` (an
  # optional year is ignored — the conditions are checked within the same year).
  defp parse_on_dates(string) do
    string
    |> String.split(~r/\s+and\s+/i)
    |> Enum.map(&parse_on_date/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_on_date(string) do
    case Regex.run(~r/(?:0*\d{1,4}-)?0?(\d{1,2})-0?(\d{1,2})/, String.trim(string)) do
      [_, month, day] -> {String.to_integer(month), String.to_integer(day)}
      _ -> nil
    end
  end

  # Carry the year conditions onto the compiled rule. A tier that set its own
  # window (a specific date) keeps it when the rule named no `since`/`until`;
  # an `if is … holiday then …` conditional stripped ahead of the base takes
  # precedence over a `:bridge` conditional a tier (`compile_bridge/1`) set.
  defp apply_conditions(compiled, conditions, substitute, conditional, rule) do
    %{
      compiled
      | substitute: substitute,
        active: conditions.active,
        from_year: conditions.from_year || compiled.from_year,
        to_year: conditions.to_year || compiled.to_year,
        year_parity: conditions.year_parity,
        leap: conditions.leap,
        every_years: conditions.every_years,
        weekday_gate: conditions.weekday_gate,
        conditional: conditional || compiled.conditional,
        source: rule
    }
  end

  # `since <year>` sets the first active year; `prior to <year>` / `until
  # <year>` set an exclusive last year; `in even|odd years` and `in
  # leap|non-leap years` add parity and leap-year filters. All are stripped
  # from the base rule and returned as conditions the materialiser gates on.
  defp extract_year_conditions(rule) do
    conditions = %{
      from_year: extract_year(rule, ~r/\bsince\s+(\d{4})(?!-)/i),
      to_year: extract_year(rule, ~r/\b(?:prior\s+to|until)\s+(\d{4})(?!-)/i),
      active: date_precise_window(rule),
      year_parity: extract_parity(rule),
      leap: extract_leap(rule),
      every_years: extract_every(rule),
      weekday_gate: extract_weekday_gate(rule)
    }

    base =
      rule
      |> String.replace(~r/\b(?:and\s+)?since\s+\d{4}(?:-\d{2}-\d{2})?(?:\s+and\b)?/i, "")
      |> String.replace(
        ~r/\b(?:and\s+)?(?:prior\s+to|until)\s+\d{4}(?:-\d{2}-\d{2})?(?:\s+and\b)?/i,
        ""
      )
      |> String.replace(~r/\bin\s+(?:even|odd|non-?leap|leap)\s+years?\b/i, "")
      |> String.replace(~r/\bevery\s+\d+\s+years?\b/i, "")
      |> String.replace(@weekday_gate_strip, "")
      |> String.trim()

    {base, conditions}
  end

  defp extract_every(rule) do
    case Regex.run(~r/\bevery\s+(\d+)\s+years?\b/i, rule) do
      [_, count] -> String.to_integer(count)
      nil -> nil
    end
  end

  # `on <weekday[, …]>` keeps the holiday only on those weekdays (`:only`);
  # `not on <weekday[, …]>` drops it on them (`:except`).
  defp extract_weekday_gate(rule) do
    case Regex.run(@weekday_gate_match, rule) do
      [_, prefix, days] ->
        case parse_weekday_set(days) do
          {:ok, weekdays} -> {gate_mode(prefix), weekdays}
          :error -> nil
        end

      nil ->
        nil
    end
  end

  defp gate_mode(prefix), do: if(Regex.match?(~r/not/i, prefix), do: :except, else: :only)

  defp extract_parity(rule) do
    cond do
      Regex.match?(~r/\bin\s+even\s+years?\b/i, rule) -> :even
      Regex.match?(~r/\bin\s+odd\s+years?\b/i, rule) -> :odd
      true -> nil
    end
  end

  defp extract_leap(rule) do
    cond do
      Regex.match?(~r/\bin\s+non-?leap\s+years?\b/i, rule) -> :non_leap
      Regex.match?(~r/\bin\s+leap\s+years?\b/i, rule) -> :leap
      true -> nil
    end
  end

  defp extract_year(rule, pattern) do
    case Regex.run(pattern, rule) do
      [_, year] -> String.to_integer(year)
      nil -> nil
    end
  end

  # A date-precise `since YYYY-MM-DD` / `prior to YYYY-MM-DD` gates by the
  # occurrence's date, not just its year (Norfolk Island's holiday moved on
  # 2022-09-09), so it becomes a half-open `active` window `[from, to)` that the
  # materialiser applies to the computed date. `nil` when neither is date-precise.
  defp date_precise_window(rule) do
    from = extract_date(rule, ~r/\bsince\s+(\d{4})-(\d{2})-(\d{2})/i)
    to = extract_date(rule, ~r/\b(?:prior\s+to|until)\s+(\d{4})-(\d{2})-(\d{2})/i)

    if is_nil(from) and is_nil(to), do: nil, else: [{from, to}]
  end

  defp extract_date(rule, pattern) do
    case Regex.run(pattern, rule) do
      [_, year, month, day] ->
        case Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
          {:ok, date} -> date
          {:error, _reason} -> nil
        end

      nil ->
        nil
    end
  end

  # A time of day does not change which day a holiday falls on, so a time
  # token (`12:00`) and any time-valued substitution (`if sunday then 00:00`)
  # are dropped before the date grammar is matched. The `\d{1,2}:\d{2}` clock
  # is guarded by a lookbehind so it does not eat the `HH:MM` of a timezone
  # offset (`march equinox in +09:00`).
  defp strip_time(rule) do
    rule
    |> String.replace(~r/(?:\band\b\s*)?if\s+[a-z, ]+?\s+then\s+\d{1,2}:\d{2}/i, "")
    |> String.replace(~r/(?<![+\-\d])\d{1,2}:\d{2}/, "")
    |> String.replace(~r/\s+PT\S+/i, "")
    |> String.trim()
  end

  # A trailing `#<n>` disambiguates two holidays that share a date; it does not
  # affect the date, so it is dropped.
  defp strip_index(rule) do
    rule |> String.replace(~r/\s*#\d+\s*$/, "") |> String.trim()
  end

  # ── fixed: "MM-DD", "MM-DD P<n>D" ───────────────────────────────────
  #
  # An optional `P<n>D` span (in days) carries into `count`; a bare date is a
  # single day. A trailing `T` (`P2DT`) is tolerated as a degenerate duration.
  defp compile_fixed(rule) do
    case Regex.run(~r/^\s*(\d{1,2})-(\d{1,2})(?:\s+P(\d+)DT?)?\s*$/, rule) do
      [_, month, day | rest] ->
        {:ok,
         %Rule{
           kind: :fixed,
           month: String.to_integer(month),
           day: String.to_integer(day),
           count: rest |> List.first() |> parse_span(),
           source: rule
         }}

      nil ->
        nil
    end
  end

  # ── weekday-in-month: "2nd Monday in June", "last Monday in May" ─────
  defp compile_weekday(rule) do
    pattern = ~r/^\s*(\w+)\s+(\w+)\s+in\s+(\w+)(?:\s+P\d+D)?\s*$/i

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

  # ── relative weekday: "monday before 06-01", "1st Friday after 07-10",
  #    "monday before October" ────────────────────────────────────────
  #
  # An optional ordinal (`1st`, `2nd`, …) picks the Nth such weekday from the
  # anchor (default the 1st, the nearest); the anchor is a fixed `MM-DD` or a
  # month name (its first day); a trailing `P<n>D` span is ignored, since the
  # date-set turns on the start day.
  defp compile_relative_weekday(rule) do
    pattern =
      ~r/^\s*(?:(\d+)(?:st|nd|rd|th)\s+)?(\w+)\s+(before|after)\s+(\d{1,2}-\d{1,2}|[a-z]+)(?:\s+P\d+D)?\s*$/i

    with [_, ordinal, weekday, direction, anchor] <- Regex.run(pattern, rule),
         {:ok, code} <- Map.fetch(@weekdays, String.downcase(weekday)),
         {:ok, {month, day}} <- relative_anchor(anchor) do
      {:ok,
       %Rule{
         kind: :relative_weekday,
         count: parse_ordinal_count(ordinal),
         weekday: code,
         direction: relative_direction(direction),
         month: month,
         day: day,
         source: rule
       }}
    else
      _ -> nil
    end
  end

  # A relative-weekday anchor is either a fixed `MM-DD` date or a month name
  # (anchored on its first day).
  defp relative_anchor(anchor) do
    case Regex.run(~r/^(\d{1,2})-(\d{1,2})$/, anchor) do
      [_, month, day] ->
        {:ok, {String.to_integer(month), String.to_integer(day)}}

      nil ->
        case Map.fetch(@months, String.downcase(anchor)) do
          {:ok, month} -> {:ok, {month, 1}}
          :error -> :error
        end
    end
  end

  defp parse_ordinal_count(""), do: 1
  defp parse_ordinal_count(digits), do: String.to_integer(digits)

  defp relative_direction(direction) do
    case String.downcase(direction) do
      "before" -> :before
      "after" -> :after
    end
  end

  # ── nested weekday: "friday after 4th thursday in November" ──────────
  #
  # An outer weekday relative to an inner weekday-in-month: Black Friday is
  # "friday after 4th thursday in November", US Election Day is "Tuesday after
  # 1st Monday in November".
  defp compile_nested_weekday(rule) do
    pattern = ~r/^\s*(\w+)\s+(before|after)\s+(\d+)(?:st|nd|rd|th)\s+(\w+)\s+in\s+(\w+)\s*$/i

    with [_, outer, direction, ordinal, inner, month] <- Regex.run(pattern, rule),
         {:ok, outer_code} <- Map.fetch(@weekdays, String.downcase(outer)),
         {:ok, inner_code} <- Map.fetch(@weekdays, String.downcase(inner)),
         {:ok, month_number} <- Map.fetch(@months, String.downcase(month)) do
      {:ok,
       %Rule{
         kind: :nested_weekday,
         weekday: outer_code,
         inner_weekday: inner_code,
         direction: relative_direction(direction),
         count: String.to_integer(ordinal),
         month: month_number,
         source: rule
       }}
    else
      _ -> nil
    end
  end

  # ── nested weekday after a date: "monday after 3rd sunday after 09-01" ─
  #
  # An outer weekday relative to the Nth inner weekday *after a fixed date* —
  # "monday after 3rd sunday after 09-01" is the Monday after the third Sunday
  # on or after 1 September. Distinct from `compile_nested_weekday`, whose inner
  # anchor is a weekday-in-month.
  defp compile_nested_after_date(rule) do
    pattern =
      ~r/^\s*(\w+)\s+after\s+(\d+)(?:st|nd|rd|th)\s+(\w+)\s+after\s+(\d{1,2})-(\d{1,2})\s*$/i

    with [_, outer, ordinal, inner, month, day] <- Regex.run(pattern, rule),
         {:ok, outer_code} <- Map.fetch(@weekdays, String.downcase(outer)),
         {:ok, inner_code} <- Map.fetch(@weekdays, String.downcase(inner)) do
      {:ok,
       %Rule{
         kind: :nested_after_date,
         weekday: outer_code,
         inner_weekday: inner_code,
         count: String.to_integer(ordinal),
         month: String.to_integer(month),
         day: String.to_integer(day),
         source: rule
       }}
    else
      _ -> nil
    end
  end

  # ── julian fixed date: "julian 12-25", "julian 12-25 P2D" ───────────
  #
  # A fixed date in the Julian calendar — Orthodox Christmas is `julian 12-25`
  # (Gregorian 7 January). The materialiser projects it onto the Gregorian year
  # through Calendrical's Julian calendar and converts it to Gregorian. An
  # optional `P<n>D` span carries into `count`.
  defp compile_julian(rule) do
    case Regex.run(~r/^\s*julian\s+(\d{1,2})-(\d{1,2})(?:\s+P(\d+)DT?)?\s*$/i, rule) do
      [_, month, day | rest] ->
        {:ok,
         %Rule{
           kind: :julian,
           calendar: Calendrical.Julian,
           month: String.to_integer(month),
           day: String.to_integer(day),
           count: rest |> List.first() |> parse_span(),
           source: rule
         }}

      nil ->
        nil
    end
  end

  # date-holidays writes its lunisolar calendars — Chinese (`chinese …`), Korean
  # (`korean …`) and Vietnamese (`vietnamese …`) — with the same shape, so they
  # share a compiler tier. Vietnamese is the Chinese system at the UTC+7 meridian
  # (`Calendrical.Vietnamese`), so Tết can land a day off Chinese New Year.
  @lunisolar_calendars %{
    "chinese" => Calendrical.Chinese,
    "korean" => Calendrical.Korean,
    "vietnamese" => Calendrical.Vietnamese
  }

  # ── lunisolar: "chinese|korean <month>-<leap>-<day>" ────────────────
  #
  # The lunar form in *traditional* month numbering: `<leap>` is `1` for a leap
  # month, `0` otherwise. `chinese 01-0-01` is Chinese New Year, `chinese
  # 01-0-00` its eve (day 0 = the day before); `korean 01-0-01` is Seollal. The
  # optional absolute `<cycle>-<year>` prefix is used by no holiday, so it is
  # not accepted.
  defp compile_lunisolar(rule) do
    case Regex.run(
           ~r/^\s*(chinese|korean|vietnamese)\s+(\d{1,2})-([01])-(\d{1,2})(?:\s+P(\d+)D)?\s*$/i,
           rule
         ) do
      [_, system, month, leap, day | rest] ->
        {:ok,
         %Rule{
           kind: :lunisolar,
           calendar: Map.fetch!(@lunisolar_calendars, String.downcase(system)),
           month: String.to_integer(month),
           day: String.to_integer(day),
           leap_month: leap == "1",
           count: rest |> List.first() |> parse_span(),
           source: rule
         }}

      nil ->
        nil
    end
  end

  # ── day-offset before/after a lunisolar date ────────────────────────
  #
  # `<n> day[s] (before|after) <lunisolar rule> [P<n>D]` — Vietnam's Tết eve
  # (`1 day before vietnamese 1-0-1 P5D`) starts the day before Tết and runs
  # five days. The offset shifts the computed Gregorian date; the span carries
  # into `count`. Only a lunisolar base takes an offset (no other rule uses this
  # form), so a non-lunisolar base falls through to the other tiers.
  defp compile_day_offset(rule) do
    case Regex.run(~r/^\s*(\d+)\s+days?\s+(before|after)\s+(.+?)(?:\s+P(\d+)D)?\s*$/i, rule) do
      [_, count, direction, base | rest] ->
        offset = offset_sign(String.downcase(direction)) * String.to_integer(count)
        wrap_day_offset(compile_base(base), offset, List.first(rest), rule)

      nil ->
        nil
    end
  end

  defp offset_sign("before"), do: -1
  defp offset_sign("after"), do: 1

  defp wrap_day_offset({:ok, %Rule{kind: :lunisolar} = compiled}, offset, span, rule) do
    {:ok, %{compiled | offset: offset, count: parse_span(span), source: rule}}
  end

  defp wrap_day_offset(_compiled, _offset, _span, _rule), do: nil

  # ── chinese solar term: "chinese <term>-<day> solarterm" ────────────
  #
  # The `<term>` is the 1-based index into the 24 solar terms (1 = 立春 Lichun,
  # 5 = 清明 Qingming); `<day>` is the 1-based day within that term (day 1 is the
  # term's own date). The materialiser resolves the term to the day the sun
  # reaches its ecliptic longitude, in China Standard Time.
  defp compile_chinese_solar(rule) do
    case Regex.run(~r/^\s*chinese\s+(\d{1,2})-(\d{1,2})\s+solarterm\s*$/i, rule) do
      [_, term, day] ->
        {:ok,
         %Rule{
           kind: :solar_term,
           calendar: Calendrical.Chinese,
           count: String.to_integer(term),
           day: String.to_integer(day),
           source: rule
         }}

      nil ->
        nil
    end
  end

  # ── calendar date: "1 Muharram", "9 Dhu al-Hijjah P4D", "1 Farvardin" ─
  #
  # `<day> <calendar month>`, with an optional `P<n>D` span. The month name
  # picks the calendar (Islamic Umm al-Qura, Hebrew, or Persian); the
  # materialiser projects it onto the Gregorian year through that calendar.
  defp compile_calendar(rule) do
    pattern = ~r/^\s*(\d{1,2})\s+([a-z][a-z' -]+?)(?:\s+P(\d+)D(?:T\S*)?)?\s*$/i

    with [_, day, month_name | rest] <- Regex.run(pattern, rule),
         {kind, calendar, month} <- calendar_month(String.downcase(String.trim(month_name))) do
      {month, leap_month} = split_leap_month(month)

      {:ok,
       %Rule{
         kind: kind,
         calendar: calendar,
         month: month,
         leap_month: leap_month,
         day: String.to_integer(day),
         count: rest |> List.first() |> parse_span(),
         source: rule
       }}
    else
      _ -> nil
    end
  end

  # Resolve a calendar month name to `{kind, calendar_module, month_number}`,
  # or `nil` when it names no known calendar's month.
  defp calendar_month(name) do
    cond do
      Map.has_key?(@islamic_months, name) ->
        {:islamic, Calendrical.Islamic.UmmAlQura, @islamic_months[name]}

      Map.has_key?(@hebrew_months, name) ->
        {:hebrew, Calendrical.Hebrew, @hebrew_months[name]}

      Map.has_key?(@persian_months, name) ->
        {:persian, Calendrical.Persian, @persian_months[name]}

      true ->
        nil
    end
  end

  # A leap month (Hebrew Adar I) is `{month, :leap}`: the rule keeps the month
  # it follows and marks it a leap month.
  defp split_leap_month({month, :leap}), do: {month, true}
  defp split_leap_month(month), do: {month, nil}

  defp parse_span(nil), do: 1
  defp parse_span(""), do: 1
  defp parse_span(days), do: String.to_integer(days)

  # ── equinox / solstice: "march equinox in +09:00", "december solstice" ─
  #
  # `(<n> days (before|after) )?(march|september) equinox | (june|december)
  # solstice( in <timezone>)?`. The season must match the event (a March
  # solstice is rejected). No timezone means GMT; a numeric offset or a named
  # zone fixes the civil date. `<n> days before/after` shifts it.
  defp compile_solar_event(rule) do
    pattern =
      ~r/^\s*(?:(\d+)\s+days?\s+(before|after)\s+)?(march|september|june|december)\s+(equinox|solstice)(?:\s+in\s+(\S+))?\s*$/i

    with [_, days, direction, season, event | rest] <- Regex.run(pattern, rule),
         kind <- solar_event_kind(String.downcase(event)),
         {:ok, month} <- solar_event_month(String.downcase(season), kind) do
      {:ok,
       %Rule{
         kind: kind,
         month: month,
         offset: solar_event_offset(days, direction),
         timezone: rest |> List.first() |> presence(),
         source: rule
       }}
    else
      _ -> nil
    end
  end

  defp solar_event_kind("equinox"), do: :equinox
  defp solar_event_kind("solstice"), do: :solstice

  # The season must belong to the event, giving the month that identifies it.
  defp solar_event_month("march", :equinox), do: {:ok, 3}
  defp solar_event_month("september", :equinox), do: {:ok, 9}
  defp solar_event_month("june", :solstice), do: {:ok, 6}
  defp solar_event_month("december", :solstice), do: {:ok, 12}
  defp solar_event_month(_season, _kind), do: :error

  defp solar_event_offset(days, _direction) when days in [nil, ""], do: 0

  defp solar_event_offset(days, direction) do
    magnitude = String.to_integer(days)
    if String.downcase(direction) == "before", do: -magnitude, else: magnitude
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value

  # ── easter-relative: "easter", "easter -2", "orthodox 1" ────────────
  defp compile_easter(rule) do
    case Regex.run(~r/^\s*(easter|orthodox)\s*([+-]?\d+)?(?:\s+P(\d+)D(?:T\S*)?)?\s*$/i, rule) do
      [_, anchor | rest] ->
        offset = rest |> Enum.at(0) |> parse_offset()
        count = rest |> Enum.at(1) |> parse_span()
        {:ok, %Rule{kind: easter_kind(anchor), offset: offset, count: count, source: rule}}

      nil ->
        nil
    end
  end

  # An explicit map, never `String.to_existing_atom/1`: the atoms are
  # interned here rather than depending on `:easter`/`:orthodox` already
  # existing when a rule string is compiled (and the regex guarantees one
  # of these two).
  defp easter_kind(anchor) do
    case String.downcase(anchor) do
      "easter" -> :easter
      "orthodox" -> :orthodox
    end
  end

  defp parse_offset(nil), do: 0
  defp parse_offset(""), do: 0
  defp parse_offset(number), do: String.to_integer(number)

  # ── observed-date substitution: "… if weekend then next monday" ─────
  #
  # Splits any `(and )?if <weekdays> then (next|previous) <weekday>` clauses off
  # the base rule and compiles them to `{trigger_weekdays, direction,
  # target_weekday, mode}` in ISO numbering. Each clause's mode follows
  # date-holidays' *persistent* modifier: a bare `if` moves the holiday
  # (`:shift`); an `and` before a clause makes it — and every later clause —
  # add the observed day (`:add`); a `substitutes` prefix makes the leading
  # clauses observed-only (`:substitute_only`) until an `and` overrides. So the
  # US `and if sunday … if saturday …` is all-add, while Tonga's `if … then …
  # and if … then …` is shift-then-add. `weekend` expands to Saturday and
  # Sunday; a comma list (`saturday,sunday`) is taken verbatim.
  # The target is always a weekday name; bounding it (rather than a greedy
  # `[a-z]+`) keeps a missing space between chained clauses — date-holidays'
  # Taiwan New Year writes `…next Saturdayif Wednesday…` — from swallowing the
  # next clause's `if` into the target and derailing the whole chain.
  @substitute_pattern ~r/(\band\b\s+)?if\s+([a-z, ]+?)\s+then\s+(next|previous)\s+(#{@weekday_alt})/i

  defp extract_substitution(rule) do
    initial_mode = if Regex.match?(~r/\bsubstitutes\b/i, rule), do: :substitute_only, else: :shift

    {clauses, _final_mode} =
      @substitute_pattern
      |> Regex.scan(rule)
      |> Enum.flat_map_reduce(initial_mode, &parse_substitute_clause/2)

    base =
      rule
      |> String.replace(@substitute_pattern, "")
      |> String.replace(~r/^\s*substitutes\s+/i, "")
      |> String.replace(~r/\s+and\s*$/i, "")
      |> String.trim()

    {base, if(clauses == [], do: nil, else: clauses)}
  end

  # `and` before a clause flips the running mode to `:add` and it persists to
  # every later clause; otherwise the mode carries over unchanged.
  defp parse_substitute_clause([_match, and_group, triggers, direction, target], mode) do
    mode = if and_group == "", do: mode, else: :add

    with {:ok, trigger_days} <- parse_weekday_set(triggers),
         {:ok, target_day} <- Map.fetch(@weekdays, String.downcase(target)) do
      {[{trigger_days, direction_atom(String.downcase(direction)), target_day, mode}], mode}
    else
      _ -> {[], mode}
    end
  end

  # `if is <type>? holiday then <count>? <direction> <weekday|day> omit <days>?`
  # — date-holidays' `ruleIfHoliday`: when the base date coincides with another
  # holiday of the type, move it (`dateDir`). The move is stripped from the base
  # and carried as an `:if_holiday` conditional resolved in the second pass.
  @weekday_alt_days "#{@weekday_alt}|day"
  @if_holiday_pattern ~r/\bif\s+is\s+(?:(public|bank|school|observance|optional)\s+)?holiday\s+then\s+(?:(\d+)(?:st|nd|rd|th)?\s+)?(before|after|next|previous|in)\s+(#{@weekday_alt_days})s?(?:\s+omit\s+((?:#{@weekday_alt_days})(?:\s*,\s*(?:#{@weekday_alt_days}))*))?/i

  defp extract_if_holiday(rule) do
    case Regex.run(@if_holiday_pattern, rule) do
      [match, type, count, direction, weekday | rest] ->
        conditional = %{
          kind: :if_holiday,
          type: holiday_type(type),
          move: %{
            count: parse_count(count),
            direction: move_direction(String.downcase(direction)),
            target: move_target(String.downcase(weekday)),
            omit: parse_omit(List.first(rest))
          }
        }

        {rule |> String.replace(match, "") |> String.trim(), conditional}

      nil ->
        {rule, nil}
    end
  end

  defp parse_count(""), do: 1
  defp parse_count(count), do: String.to_integer(count)

  defp move_target("day"), do: :day
  defp move_target(weekday), do: Map.fetch!(@weekdays, weekday)

  # An `omit` list of weekdays, taken verbatim as the days a `:day`-target move
  # steps over; a missing list is none.
  defp parse_omit(nil), do: []
  defp parse_omit(""), do: []

  defp parse_omit(days) do
    days
    |> String.split(",")
    |> Enum.map(&(&1 |> String.trim() |> then(fn day -> Map.get(@weekdays, day) end)))
    |> Enum.reject(&is_nil/1)
  end

  defp holiday_type(type) when type in [nil, ""], do: :public
  defp holiday_type(type), do: Map.get(@types, String.downcase(type), :public)

  defp direction_atom("next"), do: :next
  defp direction_atom("previous"), do: :previous

  # A move's direction spans the full `_direction` vocabulary; only `next`
  # applies the "already on the target weekday" step, so the four are kept
  # distinct (see `Tempo.Holidays.Rule` `dateDir`).
  defp move_direction("next"), do: :next
  defp move_direction("after"), do: :after
  defp move_direction("before"), do: :before
  defp move_direction("in"), do: :after
  defp move_direction("previous"), do: :previous

  defp parse_weekday_set(triggers) do
    case String.downcase(triggers) do
      "weekend" ->
        {:ok, [6, 7]}

      list ->
        days =
          list
          |> String.split(",")
          |> Enum.map(&(&1 |> String.trim() |> then(fn day -> Map.get(@weekdays, day) end)))

        if days != [] and Enum.all?(days, &is_integer/1), do: {:ok, days}, else: :error
    end
  end
end
