defmodule Tempo.Holidays.MixProject do
  use Mix.Project

  @version "0.2.0"
  @source_url "https://github.com/elixir-tempo/tempo_holidays"

  def project do
    [
      app: :tempo_holidays,
      version: @version,
      name: "Tempo.Holidays",
      source_url: @source_url,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      # Excluded from coverage:
      #  * `Mix.Tasks.Compile.Holidays`, `Mix.Tasks.Tempo.Holidays.Update`,
      #    `Mix.Tasks.Tempo.Holidays.Gettext` and `Tempo.Holidays.Build` —
      #    the compiler that writes priv/holidays from the pinned
      #    date-holidays bundle, its task to fetch a new one, and the task
      #    that writes the catalog's template from it. They run when the data
      #    is built, not in the test suite, which reads what they wrote.
      #  * `Tempo.Holidays.Conformance` and `Tempo.Holidays.Fixtures` —
      #    test-support modules under test/support.
      test_coverage: [
        ignore_modules: [
          Mix.Tasks.Compile.Holidays,
          Mix.Tasks.Tempo.Holidays.Update,
          Mix.Tasks.Tempo.Holidays.Gettext,
          Tempo.Holidays.Build,
          Tempo.Holidays.Conformance,
          Tempo.Holidays.Fixtures
        ]
      ],
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
    [mod: {Tempo.Holidays.Application, []}, extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp description do
    "Public holidays for every territory as Tempo recurrences, for any window: " <>
      "the date-holidays dataset read by Tempo.DateRule, with subdivisions, " <>
      "substitute days, other calendars and holidays of your own."
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      # Apache-2.0 covers the code. The compiled holiday data derives from
      # commenthol/date-holidays and is redistributed under CC-BY-SA-3.0, so
      # both licences are declared, and LICENSE.md, in the tarball, gives both.
      licenses: ["Apache-2.0", "CC-BY-SA-3.0"],
      links: links(),
      files: [
        "lib",
        "priv/holidays",
        "priv/gettext",
        "mix.exs",
        "README*",
        "CHANGELOG*",
        "LICENSE*"
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
        "livebook/everyday-holidays.livemd",
        "CHANGELOG.md"
      ],
      groups_for_modules: [
        Holidays: [
          Tempo.Holidays.Locale,
          Tempo.Holidays.Names,
          Tempo.Holidays.Gettext
        ],
        "School terms": [Tempo.Holidays.SchoolTerms.NSW],
        "date-holidays": [Tempo.Holidays.DateHolidays],
        Internals: [
          Tempo.Holidays.Build,
          Tempo.Holidays.Data,
          Tempo.Holidays.Holiday
        ]
      ]
    ]
  end

  defp deps do
    [
      # Tempo 2.3, whose Tempo.DateRule reads the dataset's rules and whose
      # Tempo.day_start/1 places a day of a sunset calendar. It requires
      # Calendrical 2.4, whose day_bounds/1 gives that day's sunsets, and
      # Astro 2.10, whose sunsets they are.
      {:ex_tempo, "~> 2.3"},
      {:calendrical, "~> 2.4"},
      {:astro, "~> 2.10"},
      # Tz, which Tempo brings and asks where nothing else is configured: an
      # equinox or solstice in a named IANA zone (Chile's solstice `in
      # America/Santiago`) resolves through it. Named here as the tests name
      # `Tz.TimeZoneDatabase`.
      {:tz, "~> 0.28"},
      # LanguageTag resolution (territory + language in one tag), locale-aware
      # date/time formatting, and MF2 for any templated holiday notes.
      {:localize, "~> 1.4"},
      # Holiday names the data lacks in a language come from a Gettext
      # catalog of MF2 messages, read through Localize's interpolator.
      {:gettext, "~> 1.0"},
      {:ex_doc, "~> 0.38", only: [:dev, :test, :release], optional: true, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
