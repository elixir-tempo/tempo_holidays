defmodule Tempo.Holidays.DateHolidays do
  @moduledoc """
  Ingest a [date-holidays](https://github.com/commenthol/date-holidays)
  `days` map into `t:Tempo.Holidays.Holiday.t/0`.

  A country's `days` is a map of *rule string* to metadata, exactly as the
  upstream `holidays.json` (and `holidays.yaml`) hold it — the format the
  specification defines:

      %{
        "12-25" => %{"_name" => "12-25"},
        "4th thursday in November" => %{"name" => %{"en" => "Thanksgiving Day"}},
        "07-04 and if sunday then next monday if saturday then previous friday" =>
          %{"substitute" => true, "name" => %{"en" => "Independence Day"}}
      }

  `compile_days/2` turns that into holidays, compiling each rule string
  through `Tempo.Holidays.Compiler` and dropping the entries whose grammar
  this slice does not yet cover — partial support is correct for partial
  coverage. It is the source-agnostic core the `mix tempo.holidays.update`
  task feeds a downloaded, parsed bundle into.

  """

  alias Tempo.Holidays.{Compiler, Holiday}

  @types %{
    "public" => :public,
    "bank" => :bank,
    "school" => :school,
    "optional" => :optional,
    "observance" => :observance
  }

  @doc """
  Compile a country's `days` map into a list of holidays.

  ### Arguments

  * `days` is the date-holidays `days` map — rule string to metadata.

  ### Options

  * `:language` is the ISO 639-1 code used to pick a localized name, falling
    back to English then the raw `_name`. Defaults to `"en"`.

  ### Returns

  * A list of `t:Tempo.Holidays.Holiday.t/0`, one per entry whose rule the
    compiler understands. Unsupported entries are omitted.

  ### Examples

      iex> days = %{
      ...>   "12-25" => %{"name" => %{"en" => "Christmas Day"}},
      ...>   "bengali-revised 1-1" => %{"name" => %{"en" => "Bengali New Year"}}
      ...> }
      iex> holidays = Tempo.Holidays.DateHolidays.compile_days(days)
      iex> Enum.map(holidays, & &1.name)
      ["Christmas Day"]

  """
  @spec compile_days(term(), keyword()) :: [Holiday.t()]
  def compile_days(days, options \\ [])

  def compile_days(days, options) when is_map(days) do
    language = Keyword.get(options, :language, "en")
    names = Keyword.get(options, :names, %{})
    Enum.flat_map(days, fn {rule, meta} -> compile_day(rule, meta, language, names) end)
  end

  # Downloaded data is external input: a `days` that is not a map yields no
  # holidays rather than a crash.
  def compile_days(_days, _options), do: []

  @doc """
  Compile a single `{rule, metadata}` entry into a holiday.

  ### Arguments

  * `rule` is the date-holidays rule string (the map key).

  * `meta` is its metadata map (`"name"`, `"_name"`, `"type"`, …).

  * `language` is the ISO 639-1 code for name selection.

  * `names` is the bundle's shared `_name` translation table — the
    top-level `"names"` map — used to resolve a `_name` reference. Defaults
    to `%{}` (references then stand in for their own names).

  ### Returns

  * `[t:Tempo.Holidays.Holiday.t/0]` — a one-element list on a supported
    rule, so it splices cleanly into `Enum.flat_map/2`.

  * `[]` when the rule's grammar is not yet supported, when the entry is
    disabled (`meta` is `false`, date-holidays' way of removing an inherited
    holiday), or when the entry is otherwise malformed.

  ### Examples

      iex> meta = %{"name" => %{"en" => "Independence Day"}, "substitute" => true}
      iex> [holiday] = Tempo.Holidays.DateHolidays.compile_day("07-04", meta, "en")
      iex> {holiday.name, holiday.type, holiday.rule.kind}
      {"Independence Day", :public, :fixed}

      iex> names = %{"01-01" => %{"name" => %{"en" => "New Year's Day", "fr" => "Nouvel An"}}}
      iex> [holiday] = Tempo.Holidays.DateHolidays.compile_day("01-01", %{"_name" => "01-01"}, "fr", names)
      iex> holiday.name
      "Nouvel An"

      iex> Tempo.Holidays.DateHolidays.compile_day("1st monday in May", false, "en")
      []

  """
  @spec compile_day(term(), term(), String.t(), map()) :: [Holiday.t()]
  def compile_day(rule, meta, language, names \\ %{})

  def compile_day(rule, meta, language, names) when is_binary(rule) and is_map(meta) do
    case Compiler.compile(rule) do
      {:ok, compiled} ->
        holiday = %Holiday{
          name: name(meta, language, names, rule),
          type: type(meta),
          rule: with_gates(compiled, meta)
        }

        [holiday]

      {:error, _unsupported} ->
        []
    end
  end

  # `<rule>: false` disables an inherited holiday, and downloaded data may be
  # malformed; neither yields a holiday.
  def compile_day(_rule, _meta, _language, _names), do: []

  # Prefer the requested language on an inline name, then the `_name`
  # reference resolved against the bundle's shared names table (by language,
  # then English), then the reference or rule string — so a name always
  # comes out.
  defp name(meta, language, names, fallback) do
    inline_name(meta, language) || referenced_name(meta, names, language) || fallback
  end

  defp inline_name(%{"name" => translations}, language) when is_map(translations) do
    Map.get(translations, language) || Map.get(translations, "en")
  end

  defp inline_name(_meta, _language), do: nil

  defp referenced_name(%{"_name" => reference}, names, language) when is_binary(reference) do
    resolve_reference(names, reference, language) || reference
  end

  defp referenced_name(_meta, _names, _language), do: nil

  defp resolve_reference(names, reference, language) do
    case Map.get(names, reference) do
      %{"name" => translations} when is_map(translations) ->
        Map.get(translations, language) || Map.get(translations, "en")

      _absent ->
        nil
    end
  end

  defp type(%{"type" => type}) when is_binary(type), do: Map.get(@types, type, :public)
  defp type(_meta), do: :public

  # ── occurrence-level metadata gates ─────────────────────────────────
  #
  # Attach date-holidays' `active` windows, `disable`d dates and `enable`d
  # dates (see the upstream `docs/specification.md`) onto the compiled rule.
  # Malformed entries in downloaded data are dropped, never raised on.
  defp with_gates(rule, meta) do
    %{
      rule
      | active: merge_active(rule.active, active_ranges(meta)),
        disable: iso_dates(Map.get(meta, "disable")),
        enable: iso_dates(Map.get(meta, "enable"))
    }
  end

  # The compiler may already have set an `active` window from a date-precise
  # `since`/`prior to`; keep it, and add the metadata windows when present.
  defp merge_active(nil, meta), do: meta
  defp merge_active(rule_active, nil), do: rule_active
  defp merge_active(rule_active, meta), do: rule_active ++ meta

  # `active` is a list of `%{"from" => bound, "to" => bound}` windows, each
  # bound an integer year (meaning its January 1st) or an ISO date, half-open.
  defp active_ranges(%{"active" => ranges}) when is_list(ranges) do
    case Enum.flat_map(ranges, &active_range/1) do
      [] -> nil
      parsed -> parsed
    end
  end

  defp active_ranges(_meta), do: nil

  defp active_range(range) when is_map(range) do
    [{active_bound(Map.get(range, "from")), active_bound(Map.get(range, "to"))}]
  end

  defp active_range(_other), do: []

  defp active_bound(year) when is_integer(year), do: date_or_nil(Date.new(year, 1, 1))
  defp active_bound(string) when is_binary(string), do: date_or_nil(Date.from_iso8601(string))
  defp active_bound(_absent), do: nil

  defp iso_dates(list) when is_list(list) do
    case Enum.flat_map(list, &iso_date/1) do
      [] -> nil
      dates -> dates
    end
  end

  defp iso_dates(_absent), do: nil

  defp iso_date(string) when is_binary(string) do
    case Date.from_iso8601(string) do
      {:ok, date} -> [date]
      {:error, _reason} -> []
    end
  end

  defp iso_date(_other), do: []

  defp date_or_nil({:ok, %Date{} = date}), do: date
  defp date_or_nil({:error, _reason}), do: nil
end
