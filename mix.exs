defmodule Tempo.Holidays.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/elixir-tempo/tempo_holidays"

  def project do
    [
      app: :tempo_holidays,
      version: @version,
      name: "Tempo.Holidays",
      source_url: @source_url,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      # The `:holidays` compiler generates priv/holidays/<CC>.etf from the
      # pinned date-holidays bundle (see Tempo.Holidays.Build). It runs after
      # the Elixir compiler and is a no-op once the data is present.
      compilers: Mix.compilers() ++ [:holidays],
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: [
        # `:mix` for the update task's `Mix.*` calls; `:inets` for the httpc
        # path reached through Localize's HTTP client.
        plt_add_apps: [:mix, :inets],
        flags: [:error_handling, :unknown, :underspecs, :extra_return, :missing_return]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp description do
    "Public holidays as Tempo intervals — date-holidays rules compiled to " <>
      "ISO 8601 / Tempo recurrences, with Calendrical and Astro for the " <>
      "computed tail. Territory- and calendar-aware."
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      # Apache-2.0 covers the code. The compiled holiday data derives from
      # commenthol/date-holidays and is redistributed under CC-BY-SA-3.0, so
      # both licences are declared and ship in the tarball (see NOTICE).
      licenses: ["Apache-2.0", "CC-BY-SA-3.0"],
      links: links(),
      files: [
        "lib",
        "priv/holidays",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*",
        "NOTICE*"
      ]
    ]
  end

  defp links do
    %{
      "GitHub" => @source_url,
      "Readme" => "#{@source_url}/blob/v#{@version}/README.md",
      "Changelog" => "#{@source_url}/blob/v#{@version}/CHANGELOG.md"
    }
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      formatters: ["html", "markdown"],
      extras: [
        "README.md",
        "guides/user-guide.md",
        "guides/conformance.md",
        "CHANGELOG.md"
      ],
      groups_for_modules: [
        Holidays: [
          Tempo.Holidays.Data,
          Tempo.Holidays.DayStart,
          Tempo.Holidays.Holiday,
          Tempo.Holidays.Locale,
          Tempo.Holidays.Rule
        ],
        "date-holidays": [Tempo.Holidays.Compiler, Tempo.Holidays.DateHolidays],
        Internals: [Tempo.Holidays.Build]
      ]
    ]
  end

  defp deps do
    [
      # Path dep during co-development; becomes {:ex_tempo, "~> 1.6"} before publish.
      {:ex_tempo, path: "../tempo"},
      # Path dep: the Islamic tier needs Calendrical's dates_in_gregorian_year,
      # unreleased as of 1.3.0. `override` because ex_tempo/localize pull the
      # hex calendrical as a child. Becomes {:calendrical, "~> 1.4"} before publish.
      {:calendrical, path: "../../localize/calendrical", override: true},
      # The local Astro checkout during co-development (its crescent-visibility
      # fixes are unreleased). Revert to a hex requirement once they ship.
      {:astro, path: "../../astro", override: true},
      # Equinox/solstice holidays computed for a named IANA timezone (Chile's
      # solstice `in America/Santiago`) need a time-zone database; numeric
      # offsets and GMT do not. Tz is the one Astro and Calendrical already use.
      {:tz, "~> 0.28"},
      # Optional: resolves a `{lng, lat}` location to an IANA zone for the
      # `day_start: :evening` projection. A zone id needs no resolver, and
      # `:sunset` returns a UTC instant, so tz_world is only pulled in when a
      # caller projects an evening day-start from a location. 2.5 is the floor:
      # its SpatialIndex lookups are about 1,500 times faster.
      {:tz_world, "~> 2.5", optional: true},
      # LanguageTag resolution (territory + language in one tag), locale-aware
      # date/time formatting, and MF2 for any templated holiday notes.
      {:localize, "~> 1.3"},
      {:ex_doc, "~> 0.38", only: [:dev, :test, :release], optional: true, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ] ++ maybe_json_polyfill()
  end

  # `mix tempo.holidays.update` parses the downloaded bundle with `:json`.
  # On OTP 26 that module does not exist, so json_polyfill (the EEP 68
  # backport) supplies it — for THIS project's own dev/test/CI only, since
  # `only:` deps never enter the hex package requirements. On OTP 27+ `:json`
  # is built in and the polyfill's own build fails, so the conditional keeps
  # it out there. An OTP 26 consumer who wants to run the task adds
  # `{:json_polyfill, "~> 0.2 or ~> 1.0"}` to their own deps (see README).
  defp maybe_json_polyfill do
    if Code.ensure_loaded?(:json) do
      []
    else
      [{:json_polyfill, "~> 0.2 or ~> 1.0", only: [:dev, :test]}]
    end
  end
end
