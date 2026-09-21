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
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: [
        flags: [:error_handling, :unknown, :underspecs, :extra_return, :missing_return]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

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
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp deps do
    [
      # Path dep during co-development; becomes {:ex_tempo, "~> 1.6"} before publish.
      {:ex_tempo, path: "../tempo"},
      {:calendrical, "~> 1.3"},
      {:astro, "~> 2.5"},
      # LanguageTag resolution (territory + language in one tag), locale-aware
      # date/time formatting, and MF2 for any templated holiday notes.
      {:localize, "~> 1.0"},
      {:ex_doc, "~> 0.38", only: [:dev, :test, :release], optional: true, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
