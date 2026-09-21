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
      ...>   "monday before 06-01" => %{"name" => %{"en" => "Memorial Day"}}
      ...> }
      iex> holidays = Tempo.Holidays.DateHolidays.compile_days(days)
      iex> Enum.map(holidays, & &1.name)
      ["Christmas Day"]

  """
  @spec compile_days(map(), keyword()) :: [Holiday.t()]
  def compile_days(days, options \\ []) when is_map(days) do
    language = Keyword.get(options, :language, "en")
    Enum.flat_map(days, fn {rule, meta} -> compile_day(rule, meta, language) end)
  end

  @doc """
  Compile a single `{rule, metadata}` entry into a holiday.

  ### Arguments

  * `rule` is the date-holidays rule string (the map key).

  * `meta` is its metadata map (`"name"`, `"_name"`, `"type"`, …).

  * `language` is the ISO 639-1 code for name selection.

  ### Returns

  * `[t:Tempo.Holidays.Holiday.t/0]` — a one-element list on a supported
    rule, so it splices cleanly into `Enum.flat_map/2`.

  * `[]` when the rule's grammar is not yet supported.

  ### Examples

      iex> meta = %{"name" => %{"en" => "Independence Day"}, "substitute" => true}
      iex> [holiday] = Tempo.Holidays.DateHolidays.compile_day("07-04", meta, "en")
      iex> {holiday.name, holiday.type, holiday.rule.kind}
      {"Independence Day", :public, :fixed}

  """
  @spec compile_day(String.t(), map(), String.t()) :: [Holiday.t()]
  def compile_day(rule, meta, language) when is_binary(rule) and is_map(meta) do
    case Compiler.compile(rule) do
      {:ok, compiled} ->
        [%Holiday{name: name(meta, language, rule), type: type(meta), rule: compiled}]

      {:error, _unsupported} ->
        []
    end
  end

  # Prefer the requested language, then English, then the `_name` reference
  # (resolved against `names.yaml` in a later pass), then the rule itself.
  defp name(meta, language, fallback) do
    inline_name(meta, language) || underscore_name(meta) || fallback
  end

  defp inline_name(%{"name" => names}, language) when is_map(names) do
    Map.get(names, language) || Map.get(names, "en")
  end

  defp inline_name(_meta, _language), do: nil

  defp underscore_name(%{"_name" => reference}) when is_binary(reference), do: reference
  defp underscore_name(_meta), do: nil

  defp type(%{"type" => type}) when is_binary(type), do: Map.get(@types, type, :public)
  defp type(_meta), do: :public
end
