defmodule Tempo.Holidays.Fixtures do
  @moduledoc false

  # Test-only. Downloads and caches the pinned date-holidays repo tarball and
  # exposes its `test/fixtures` as parsed conformance cases: for each
  # `<territory>-<year>.json`, the expected holidays (rule, date, name, type,
  # substitute) that date-holidays itself computes. The tarball is the same
  # exact pin as the compiled data (`Tempo.Holidays.Build.pinned_version/0`),
  # so conformance stays reproducible. The 2.6 MB tarball is cached under
  # `_build`, so only the first run touches the network.

  alias Localize.Utils.Http
  alias Tempo.Holidays.Build

  @source "https://codeload.github.com/commenthol/date-holidays/tar.gz/refs/tags/v#{Build.pinned_version()}"

  @type holiday :: %{
          rule: term(),
          date: String.t(),
          name: String.t(),
          type: String.t(),
          substitute: boolean()
        }

  @type fixture :: %{
          territory: String.t(),
          code: String.t(),
          year: pos_integer(),
          holidays: [holiday()]
        }

  @doc "All fixtures, parsed. Downloads and caches the tarball on first use."
  @spec all() :: [fixture()]
  def all do
    tarball()
    |> extract()
    |> Enum.flat_map(&parse/1)
  end

  @doc "Fixtures for the given CLDR country codes only — a fast subset for iteration."
  @spec for_codes([String.t()]) :: [fixture()]
  def for_codes(codes) do
    set = MapSet.new(codes)
    Enum.filter(all(), &MapSet.member?(set, &1.code))
  end

  # ── tarball ─────────────────────────────────────────────────────────

  defp tarball do
    case File.read(cache_path()) do
      {:ok, binary} -> binary
      {:error, _absent} -> download()
    end
  end

  defp download do
    _ = Application.ensure_all_started(:ssl)
    _ = Application.ensure_all_started(:inets)

    case Http.get(@source) do
      {:ok, binary} ->
        File.mkdir_p!(Path.dirname(cache_path()))
        File.write!(cache_path(), binary)
        binary

      {:error, reason} ->
        raise "tempo_holidays fixtures: could not download #{@source}: #{inspect(reason)}"
    end
  end

  defp cache_path do
    Path.join([
      Mix.Project.build_path(),
      "date_holidays_fixtures",
      "#{Build.pinned_version()}.tar.gz"
    ])
  end

  # ── extract & parse ─────────────────────────────────────────────────

  defp extract(tarball) do
    {:ok, files} = :erl_tar.extract({:binary, tarball}, [:compressed, :memory])

    for {name, content} <- files,
        path = to_string(name),
        String.ends_with?(path, ".json"),
        String.contains?(path, "/test/fixtures/"),
        do: {Path.basename(path, ".json"), content}
  end

  defp parse({base, content}) do
    case split(base) do
      {territory, year} ->
        [
          %{
            territory: territory,
            code: hd(String.split(territory, "-")),
            year: year,
            holidays: holidays(content)
          }
        ]

      :error ->
        []
    end
  end

  defp holidays(content) do
    for entry <- :json.decode(content) do
      %{
        rule: entry["rule"],
        date: String.slice(entry["date"] || "", 0, 10),
        name: entry["name"],
        type: entry["type"],
        substitute: entry["substitute"] == true
      }
    end
  end

  # "US-2026" -> {"US", 2026}; "US-CA-2026" -> {"US-CA", 2026}
  defp split(base) do
    parts = String.split(base, "-")
    {year_string, territory_parts} = List.pop_at(parts, -1)

    case Integer.parse(year_string || "") do
      {year, ""} when territory_parts != [] -> {Enum.join(territory_parts, "-"), year}
      _not_a_year -> :error
    end
  end
end
