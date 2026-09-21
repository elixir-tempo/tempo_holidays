defmodule Tempo.Holidays.Build do
  @moduledoc """
  Build-time generation of the compiled holiday data.

  Downloads a pinned [date-holidays](https://github.com/commenthol/date-holidays)
  bundle and compiles every territory to `priv/holidays/<CC>.etf`. The version
  is pinned exactly (not a range), so a build is reproducible: the same input
  yields the same output, and the data need not be vendored in git.

  `ensure_built/0` runs from the `:holidays` Mix compiler and is a no-op once
  the current pinned data is in place — so warm builds, and every consumer
  build (where the etf ships in the package), do no network I/O. `build/1`
  forces a fresh download and is what `mix tempo.holidays.update` runs.

  This module is Mix-only: it runs at the maintainer's build time, never at a
  consumer's runtime.

  """

  alias Localize.Utils.Http
  alias Tempo.Holidays.{DateHolidays, Holiday}

  @pinned_version "3.37.0"
  @source "https://cdn.jsdelivr.net/npm/date-holidays@#{@pinned_version}/data/holidays.json"
  @language "en"

  @doc "The exact date-holidays version the data is built from."
  def pinned_version, do: @pinned_version

  @doc "The pinned bundle URL."
  def source_url, do: @source

  @doc """
  Generate the etf data unless it is already present for the pinned version.

  Returns `:noop` when the current data is in place — the common case on a warm
  build and on every consumer build, so neither touches the network.
  """
  def ensure_built do
    if built?() do
      :noop
    else
      build()
      :ok
    end
  end

  @doc """
  Download the pinned bundle and (re)write every territory's etf, returning
  `{:ok, territory_count}`. Forces the work regardless of what is already on
  disk.
  """
  def build(options \\ []) do
    language = Keyword.get(options, :language, @language)
    directory = output_dir()
    File.mkdir_p!(directory)

    bundle = fetch_bundle()

    written =
      bundle
      |> Map.get("holidays", %{})
      |> Enum.reduce(0, fn {code, _country}, count ->
        count + write_territory(directory, bundle, code, language)
      end)

    File.write!(marker_path(), @pinned_version)
    {:ok, written}
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
  @spec holidays_from_bundle(map(), String.t(), String.t()) :: [Holiday.t()]
  def holidays_from_bundle(bundle, code, language) do
    case get_in(bundle, ["holidays", code, "days"]) do
      days when is_map(days) ->
        DateHolidays.compile_days(days, language: language, names: Map.get(bundle, "names", %{}))

      _absent ->
        []
    end
  end

  # ── generation ──────────────────────────────────────────────────────

  # A territory is written only when at least one of its rules compiles, so a
  # lookup distinguishes "known, no compilable holidays yet" (absent) from an
  # empty result.
  defp write_territory(directory, bundle, code, language) do
    bundle
    |> holidays_from_bundle(code, language)
    |> write_etf(directory, code)
  end

  defp write_etf([], _directory, _code), do: 0

  defp write_etf(holidays, directory, code) do
    File.write!(Path.join(directory, "#{code}.etf"), :erlang.term_to_binary(holidays))
    1
  end

  # ── download ────────────────────────────────────────────────────────

  # Erlang's `:json.decode/1` raises on malformed input; from a pinned,
  # immutable CDN artefact that is a build-time fault we want to fail loudly on,
  # so it is not caught.
  defp fetch_bundle do
    ensure_json!()
    _ = Application.ensure_all_started(:ssl)
    _ = Application.ensure_all_started(:inets)

    case Http.get(@source) do
      {:ok, body} ->
        :json.decode(body)

      {:error, reason} ->
        Mix.raise("tempo_holidays: could not download #{@source}: #{inspect(reason)}")
    end
  end

  # Parsing the bundle needs Erlang's `:json`, absent on OTP 26. json_polyfill
  # (a dev/test dep here) supplies it; a consumer refreshing the data on OTP 26
  # adds it too. Loading the shipped etf needs no JSON on any OTP.
  defp ensure_json! do
    if not Code.ensure_loaded?(:json) do
      Mix.raise(
        "tempo_holidays: building the data parses the download with Erlang's :json, " <>
          "which OTP 26 lacks. Add {:json_polyfill, \"~> 0.2 or ~> 1.0\"} to run the " <>
          "build on OTP 26; on OTP 27+ :json is built in."
      )
    end
  end

  # ── paths ───────────────────────────────────────────────────────────

  defp built? do
    File.read(marker_path()) == {:ok, @pinned_version}
  end

  defp marker_path, do: Path.join(output_dir(), "VERSION")

  defp output_dir do
    Path.join([Path.dirname(Mix.Project.project_file()), "priv", "holidays"])
  end
end
