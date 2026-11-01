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

  `compile_days/2` turns that into holidays, keeping each rule string with
  its dataset dates where `Tempo.DateRule.parse/2` reads it, and dropping the
  entries it does not (an `if equal` clause). It is the source-agnostic
  core the `mix tempo.holidays.update` task feeds a downloaded, parsed bundle
  into.

  """

  alias Tempo.Holidays.Holiday
  alias Tempo.RecurrenceSet

  @types %{
    "public" => :public,
    "bank" => :bank,
    "school" => :school,
    "optional" => :optional,
    "observance" => :observance
  }

  # The language codes date-holidays writes that are not CLDR's, and the
  # CLDR code each is: Japanese, Czech, Georgian, Latin and Norwegian
  # Bokmål. A name is kept under the CLDR code a locale names it by.
  @language_codes %{"jp" => "ja", "cz" => "cs", "ge" => "ka", "lat" => "la", "no" => "nb"}

  # Keys of a name map that are no language: date-holidays writes a
  # holiday's `type` among its names in a few places.
  @not_languages ["type"]

  @doc """
  Compile a country's `days` map into a list of holidays.

  ### Arguments

  * `days` is the date-holidays `days` map — rule string to metadata.

  ### Options

  * `:language` is the ISO 639-1 code used to pick a localized name, falling
    back to English then the raw `_name`. Defaults to `"en"`.

  ### Returns

  * A list of `t:Tempo.Holidays.Holiday.t/0`, one per entry whose rule
    `Tempo.DateRule` reads. The others are omitted.

  ### Examples

      iex> days = %{
      ...>   "12-25" => %{"name" => %{"en" => "Christmas Day"}},
      ...>   "2nd sunday after 05-01 if equal easter 49 then 3rd sunday after 05-01" => %{"name" => %{"en" => "A moved Sunday"}}
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

  * `[]` when `Tempo.DateRule` does not read the rule, when the entry is
    disabled (`meta` is `false`, date-holidays' way of removing an inherited
    holiday), or when the entry is otherwise malformed.

  ### Examples

      iex> meta = %{"name" => %{"en" => "Independence Day"}, "substitute" => true}
      iex> [holiday] = Tempo.Holidays.DateHolidays.compile_day("07-04", meta, "en")
      iex> {holiday.name, holiday.type, holiday.rule}
      {"Independence Day", :public, "07-04"}

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
    holiday = %Holiday{
      name: name(meta, language, names, rule),
      names: translations(meta, names),
      type: type(meta),
      rule: rule,
      active: active_ranges(meta),
      disable: iso_dates(Map.get(meta, "disable")),
      enable: iso_dates(Map.get(meta, "enable"))
    }

    case read(holiday) do
      {:ok, holiday} -> [holiday]
      {:error, _unread} -> []
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

  # Every name the dataset gives a holiday: its `_name` reference's, and its
  # own inline names, which win for a language both give.
  defp translations(meta, names) do
    meta
    |> referenced_translations(names)
    |> Map.merge(inline_translations(meta))
    |> Map.drop(@not_languages)
    |> Enum.reduce(%{}, &by_language_code/2)
  end

  # A name under the CLDR code of its language; where date-holidays writes a
  # language under both codes (`cs` and `cz`), the CLDR code's name is kept.
  defp by_language_code({code, name}, kept) do
    cldr = language_code(code)

    if code != cldr and Map.has_key?(kept, cldr) do
      kept
    else
      Map.put(kept, cldr, name)
    end
  end

  @doc """
  The CLDR code of a language code date-holidays writes: `"ja"` for its
  `"jp"`, and any code that is already CLDR's unchanged.

  ### Arguments

  * `code` is a language code from the dataset, such as `"jp"` or `"de-ch"`.

  ### Returns

  * The code as CLDR writes it.

  ### Examples

      iex> Tempo.Holidays.DateHolidays.language_code("jp")
      "ja"

      iex> Tempo.Holidays.DateHolidays.language_code("de-ch")
      "de-ch"

  """
  @spec language_code(String.t()) :: String.t()
  def language_code(code) when is_binary(code) do
    Map.get(@language_codes, code, code)
  end

  defp inline_translations(%{"name" => translations}) when is_map(translations) do
    translations
  end

  defp inline_translations(_meta) do
    %{}
  end

  defp referenced_translations(%{"_name" => reference}, names) when is_binary(reference) do
    case Map.get(names, reference) do
      %{"name" => translations} when is_map(translations) -> translations
      _absent -> %{}
    end
  end

  defp referenced_translations(_meta, _names) do
    %{}
  end

  defp type(%{"type" => type}) when is_binary(type), do: Map.get(@types, type, :public)
  defp type(_meta), do: :public

  # A holiday whose rule `Tempo.DateRule` reads, with its dataset dates; a
  # `substitutes` entry, only observed days, reads to no date with
  # `observed: :none`.
  defp read(%Holiday{rule: rule} = holiday) do
    options = [active: holiday.active, disable: holiday.disable, enable: holiday.enable]

    with {:ok, _expression} <- Tempo.DateRule.parse(rule, options),
         {:ok, gazetted} <- Tempo.DateRule.parse(rule, [observed: :none] ++ options) do
      {:ok, %{holiday | substitute: not match?([_ | _], RecurrenceSet.members(gazetted))}}
    end
  end

  # ── occurrence-level metadata ───────────────────────────────────────
  #
  # date-holidays' `active` windows, `disable`d dates and `enable`d dates
  # (see the upstream `docs/specification.md`), as `Tempo.DateRule.parse/2`
  # takes them. Malformed entries in downloaded data are dropped, never
  # raised on.

  # `active` is a list of `%{"from" => bound, "to" => bound}` windows, each
  # bound an integer year (meaning its January 1st) or an ISO date, half-open.
  defp active_ranges(%{"active" => ranges}) when is_list(ranges) do
    Enum.flat_map(ranges, &active_range/1)
  end

  defp active_ranges(_meta), do: []

  defp active_range(range) when is_map(range) do
    [{active_bound(Map.get(range, "from")), active_bound(Map.get(range, "to"))}]
  end

  defp active_range(_other), do: []

  defp active_bound(year) when is_integer(year), do: date_or_nil(Date.new(year, 1, 1))
  defp active_bound(string) when is_binary(string), do: date_or_nil(Date.from_iso8601(string))
  defp active_bound(_absent), do: nil

  defp iso_dates(list) when is_list(list) do
    Enum.flat_map(list, &iso_date/1)
  end

  defp iso_dates(_absent), do: []

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
