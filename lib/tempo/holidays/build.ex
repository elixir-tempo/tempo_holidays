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
  the current pinned data is in place, in the current data format — so warm
  builds, and every consumer build (where the etf ships in the package), do no
  network I/O, while a change to the serialised structs regenerates it.
  `build/1` forces a fresh download and is what `mix tempo.holidays.update` runs.

  Each rule is read with `Tempo.DateRule` as it is built, to leave out one it
  does not read, and reading a rule can work out a date: an equinox needs
  Astro's ephemeris, and a date of another calendar needs Calendrical. So
  `build/1` starts Tempo's applications (`:ex_tempo`, which starts Astro
  before Calendrical) before it reads, as the `:holidays` compiler runs
  before anything is started.

  This module is Mix-only: it runs at the maintainer's build time, never at a
  consumer's runtime.

  """

  alias Localize.Utils.Http
  alias Tempo.Holidays.{Data, DateHolidays, Holiday}

  @pinned_version "3.38.0"
  @language "en"
  @version_format ~r/\A\d+\.\d+\.\d+\z/

  @doc "The exact date-holidays version the data is built from."
  def pinned_version, do: @pinned_version

  @doc "The pinned bundle URL."
  def source_url, do: source_url(@pinned_version)

  @doc "The bundle URL of a date-holidays version, such as `\"3.38.0\"`."
  def source_url(version) do
    "https://cdn.jsdelivr.net/npm/date-holidays@#{version}/data/holidays.json"
  end

  @doc "The directory the package's own data is written to: its `priv/holidays`."
  def default_directory do
    Path.join([Path.dirname(Mix.Project.project_file()), "priv", "holidays"])
  end

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
  Download a date-holidays bundle and (re)write every territory's etf, returning
  `{:ok, territory_count, unsupported}`, where `unsupported` lists the rules
  the bundle holds that are not compiled yet and so are left out of the data.
  Forces the work regardless of what is already on disk.

  Options: `:version`, the date-holidays release (the pinned one by default);
  `:directory`, where the etf is written (`default_directory/0` by default);
  `:language`, the ISO 639-1 code for names (`"en"` by default).
  """
  def build(options \\ []) do
    language = Keyword.get(options, :language, @language)
    version = Keyword.get(options, :version, @pinned_version)
    directory = Keyword.get(options, :directory, default_directory())
    valid_version!(version)
    File.mkdir_p!(directory)
    {:ok, _started} = Application.ensure_all_started(:ex_tempo)

    bundle = fetch_bundle(version)

    written =
      bundle
      |> Map.get("holidays", %{})
      |> Enum.reduce(0, fn {code, _country}, count ->
        count + write_territory(directory, bundle, code, language)
      end)

    File.write!(Path.join(directory, "VERSION"), Data.marker(version))
    {:ok, written, unsupported(bundle)}
  end

  # The rules of a bundle `Tempo.DateRule` does not read, which its data leaves out. A
  # rule written `false` disables an inherited one and is no rule.
  defp unsupported(bundle) do
    bundle
    |> Map.get("holidays", %{})
    |> rules_in()
    |> Enum.uniq()
    |> Enum.filter(&match?({:error, _}, Tempo.DateRule.parse(&1)))
    |> Enum.sort()
  end

  defp rules_in(%{} = map) do
    Enum.flat_map(map, fn
      {"days", days} when is_map(days) -> for {rule, meta} <- days, meta != false, do: rule
      {_key, value} -> rules_in(value)
    end)
  end

  defp rules_in(_other) do
    []
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
      bundle
      |> subdivisions_of(code)
      |> Map.new(fn {state, data} -> {state, compile_state(bundle, data, names, language)} end)

    write_country(directory, code, %{country: country, states: states})
  end

  # A country's first level of subdivisions: its `states`, and its `regions`
  # where it writes them at the top (Andorra's parishes, Croatia's counties),
  # which date-holidays-parser takes as states, ahead of a state of the same
  # code.
  defp subdivisions_of(bundle, code) do
    territory = as_map(get_in(bundle, ["holidays", code]))
    Map.merge(as_map(Map.get(territory, "states")), as_map(Map.get(territory, "regions")))
  end

  # A state or a region with no days of its own is kept: date-holidays lists
  # it (New Orleans, `US-LA-NO`), and it has the holidays of the level above.
  defp compile_state(bundle, state_data, names, language) do
    regions =
      state_data
      |> sub_regions()
      |> Map.new(fn {region, data} ->
        {region, compile_level(level_days(bundle, data), names, language)}
      end)

    bundle
    |> level_days(state_data)
    |> compile_level(names, language)
    |> Map.put(:regions, regions)
  end

  # A state's or a region's days: those its `_days` names (Saint Barthélemy
  # the territory `BL`'s, a Canary Island its region of `IC`), with its own
  # over them, `false` among them to remove one of the level above's.
  defp level_days(bundle, data) do
    inherited = referenced_days(bundle, is_map(data) && Map.get(data, "_days"))
    Map.merge(inherited, sub_days(data))
  end

  defp referenced_days(bundle, reference) when is_binary(reference) or is_list(reference) do
    as_days(get_in(bundle, ["holidays"] ++ List.wrap(reference) ++ ["days"]))
  end

  defp referenced_days(_bundle, _none) do
    %{}
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
  defp fetch_bundle(version) do
    _ = Application.ensure_all_started(:ssl)
    _ = Application.ensure_all_started(:inets)
    source = source_url(version)

    case Http.get(source) do
      {:ok, body} ->
        :json.decode(body)

      {:error, reason} ->
        Mix.raise("tempo_holidays: could not download #{source}: #{inspect(reason)}")
    end
  end

  defp valid_version!(version) do
    if is_binary(version) and Regex.match?(@version_format, version) do
      :ok
    else
      Mix.raise(
        "tempo_holidays: a date-holidays version is three numbers, such as 3.38.0, not #{inspect(version)}"
      )
    end
  end

  # ── paths ───────────────────────────────────────────────────────────

  # The data on disk is current when it was built from the pinned version in the
  # current data format.
  defp built? do
    File.read(Path.join(default_directory(), "VERSION")) == {:ok, Data.marker(@pinned_version)}
  end
end
