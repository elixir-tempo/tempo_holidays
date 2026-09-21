defmodule Tempo.Holidays.Build do
  @moduledoc """
  Build-time generation of the compiled holiday data.

  Downloads a pinned [date-holidays](https://github.com/commenthol/date-holidays)
  bundle and compiles every territory to one nested `priv/holidays/<CC>.etf` —
  the country's holidays plus each state's and region's *own* holidays and the
  rule keys they override, which `Tempo.Holidays.Data` merges at load time (so
  the country's holidays are not duplicated into every state). The version is
  pinned exactly (not a range), so a build is reproducible: the same input
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
    case resolve_days(bundle, code) do
      days when map_size(days) > 0 ->
        DateHolidays.compile_days(days, language: language, names: Map.get(bundle, "names", %{}))

      _absent ->
        []
    end
  end

  # ── generation ──────────────────────────────────────────────────────

  # Writes one nested file per country — `%{country: [...], states: %{STATE =>
  # %{holidays: [...], keys: [...], regions: %{...}}}}`. date-holidays inherits:
  # a state's holidays are the country's overridden by its own, but rather than
  # duplicate the country's holidays into every state file, each state stores
  # only its *own* holidays plus the rule keys it defines (`keys`), and the
  # loader merges at read time — a state key overrides or, when `false`,
  # disables the country's holiday with the same key.
  defp write_territory(directory, bundle, code, language) do
    names = Map.get(bundle, "names", %{})
    country = compile_days(resolve_days(bundle, code), names, language)

    states =
      ["holidays", code, "states"]
      |> then(&get_in(bundle, &1))
      |> as_map()
      |> Enum.map(fn {state, data} -> {state, compile_state(data, names, language)} end)
      |> Enum.reject(fn {_state, entry} -> empty_state?(entry) end)
      |> Map.new()

    write_country(directory, code, %{country: country, states: states})
  end

  defp compile_state(state_data, names, language) do
    days = sub_days(state_data)

    regions =
      state_data
      |> sub_regions()
      |> Enum.map(fn {region, data} ->
        {region, compile_level(sub_days(data), names, language)}
      end)
      |> Enum.reject(fn {_region, entry} -> entry.keys == [] end)
      |> Map.new()

    days |> compile_level(names, language) |> Map.put(:regions, regions)
  end

  defp compile_level(days, names, language) do
    %{holidays: compile_days(days, names, language), keys: Map.keys(days)}
  end

  defp compile_days(days, names, language) do
    days |> as_days() |> DateHolidays.compile_days(language: language, names: names)
  end

  # date-holidays lets a territory inherit another's holidays via `_days` (JE
  # inherits GB, the French overseas territories inherit FR — 22 in all). The
  # `_days` value is a path into the holidays tree; the referenced `days` are
  # the base, the territory's own `days` override by rule key, and a `false`
  # value removes an inherited rule (mirrors `date-holidays-parser`'s
  # `Data._assign`).
  defp resolve_days(bundle, code) do
    inherited =
      case get_in(bundle, ["holidays", code, "_days"]) do
        nil -> %{}
        reference -> as_days(get_in(bundle, ["holidays"] ++ List.wrap(reference) ++ ["days"]))
      end

    inherited
    |> Map.merge(as_days(get_in(bundle, ["holidays", code, "days"])))
    |> Enum.reject(fn {_rule, meta} -> meta == false end)
    |> Map.new()
  end

  defp empty_state?(%{holidays: [], keys: [], regions: regions}), do: regions == %{}
  defp empty_state?(_entry), do: false

  defp as_days(days) when is_map(days), do: days
  defp as_days(_absent), do: %{}
  defp as_map(map) when is_map(map), do: map
  defp as_map(_absent), do: %{}
  defp sub_days(data), do: as_days(is_map(data) && Map.get(data, "days"))
  defp sub_regions(data), do: as_map(is_map(data) && Map.get(data, "regions"))

  defp write_country(_directory, _code, %{country: [], states: states})
       when map_size(states) == 0,
       do: 0

  defp write_country(directory, code, territory) do
    File.write!(Path.join(directory, "#{code}.etf"), :erlang.term_to_binary(territory))
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
