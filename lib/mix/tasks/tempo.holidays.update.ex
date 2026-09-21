defmodule Mix.Tasks.Tempo.Holidays.Update do
  @shortdoc "Download date-holidays data and compile it to priv/holidays/"

  @moduledoc """
  Download the [date-holidays](https://github.com/commenthol/date-holidays)
  dataset, compile each territory's rules, and write the result to
  `priv/holidays/<CC>.etf`.

  The data is fetched from a pinned version of the compiled `holidays.json`
  bundle on jsDelivr over TLS — via Localize's HTTP client, which applies the
  erlef secure-connection guidelines — parsed with the standard-library
  `:json`, and compiled through `Tempo.Holidays.DateHolidays`. Rules whose
  grammar this library does not yet understand are skipped.

  Each territory is written as an Erlang term (ETF), so loading the data at
  runtime needs no JSON support — which matters on the OTP 26 rows of the
  matrix, where neither Elixir's `JSON` nor Erlang's `:json` exists.

  ## Usage

      mix tempo.holidays.update            # the built-in territories (AU, US)
      mix tempo.holidays.update US GB FR   # named CLDR territories
      mix tempo.holidays.update --language es

  ## Options

  * `--language` — the ISO 639-1 code for holiday names (default `en`).

  * `--source` — override the bundle URL (default the pinned jsDelivr URL).

  Parsing the download uses Erlang's `:json`. On OTP 26, where that module
  is absent, add `{:json_polyfill, "~> 0.2 or ~> 1.0"}` to your deps to run
  this task; on OTP 27+ it is built in. The compiled data it writes is ETF,
  so *loading* it never needs JSON on any release.

  """

  use Mix.Task

  alias Localize.Utils.Http
  alias Tempo.Holidays.{Data, DateHolidays}

  @source "https://cdn.jsdelivr.net/npm/date-holidays@3/data/holidays.json"
  @priv_subdir "holidays"

  @impl Mix.Task
  def run(argv) do
    {options, territories} = parse_args(argv)
    Mix.Task.run("app.start")
    {:ok, _apps} = Application.ensure_all_started(:ssl)
    require_json!()

    source = Keyword.get(options, :source, @source)
    language = Keyword.get(options, :language, "en")
    codes = territory_codes(territories)

    Mix.shell().info("Fetching #{source} …")

    case fetch_and_decode(source) do
      {:ok, bundle} -> write_all(bundle, codes, language)
      {:error, reason} -> Mix.raise("tempo.holidays.update failed: #{inspect(reason)}")
    end
  end

  @doc """
  Compile one territory's holidays from an already-decoded bundle.

  Pure — no network or filesystem — so the compile step is testable on its
  own. Returns `[]` for a territory the bundle does not carry.

  ### Arguments

  * `bundle` is the decoded `holidays.json` map.

  * `code` is the territory's CLDR/IANA code as a string, such as `"US"`.

  * `language` is the ISO 639-1 code for name selection.

  ### Returns

  * A list of `t:Tempo.Holidays.Holiday.t/0`.

  """
  @spec holidays_from_bundle(map(), String.t(), String.t()) :: [Tempo.Holidays.Holiday.t()]
  def holidays_from_bundle(bundle, code, language) do
    case get_in(bundle, ["holidays", code, "days"]) do
      days when is_map(days) -> DateHolidays.compile_days(days, language: language)
      _absent -> []
    end
  end

  # ── pipeline ────────────────────────────────────────────────────────

  defp fetch_and_decode(source) do
    case Http.get(source) do
      {:ok, body} -> decode(body)
      {:error, _reason} = error -> error
    end
  end

  defp decode(body) do
    {:ok, :json.decode(body)}
  rescue
    error -> {:error, {:invalid_json, error}}
  end

  defp write_all(bundle, codes, language) do
    directory = Path.join("priv", @priv_subdir)
    File.mkdir_p!(directory)

    Enum.each(codes, fn code ->
      holidays = holidays_from_bundle(bundle, code, language)
      path = Path.join(directory, "#{code}.etf")
      File.write!(path, :erlang.term_to_binary(holidays))
      Mix.shell().info("  #{code}: #{length(holidays)} holidays → #{path}")
    end)
  end

  # ── arguments ───────────────────────────────────────────────────────

  defp parse_args(argv) do
    {options, territories, _invalid} =
      OptionParser.parse(argv, strict: [language: :string, source: :string])

    {options, territories}
  end

  # Named territories win; otherwise fall back to the built-in seed set.
  # Codes are upper-cased strings to match the bundle's keys.
  defp territory_codes([]) do
    Enum.map(Data.territories(), &Atom.to_string/1)
  end

  defp territory_codes(territories) do
    Enum.map(territories, &String.upcase/1)
  end

  defp require_json! do
    if not Code.ensure_loaded?(:json) do
      Mix.raise(
        "mix tempo.holidays.update parses the download with Erlang's :json, which " <>
          "OTP 26 lacks. Add {:json_polyfill, \"~> 0.2 or ~> 1.0\"} to your deps to run " <>
          "this task on OTP 26; on OTP 27+ :json is built in."
      )
    end
  end
end
