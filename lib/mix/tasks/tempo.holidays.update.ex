defmodule Mix.Tasks.Tempo.Holidays.Update do
  @shortdoc "Re-download and recompile the holiday data into priv/holidays/"

  @moduledoc """
  Force a refresh of the compiled holiday data.

  `mix compile` already builds `priv/holidays/<CC>.etf` on a cold build, from a
  pinned [date-holidays](https://github.com/commenthol/date-holidays) bundle
  (see `Tempo.Holidays.Build`). This task re-runs that build *unconditionally* —
  after the pinned version is bumped, or to regenerate the names in another
  language.

  The download is over TLS via Localize's HTTP client and is parsed with
  Erlang's `:json` (json_polyfill supplies it on OTP 26). The data it writes is
  ETF, so *loading* it at runtime never needs JSON on any OTP.

  ## Usage

      mix tempo.holidays.update            # rebuild every territory
      mix tempo.holidays.update --language es

  ## Options

  * `--language` — the ISO 639-1 code for holiday names (default `en`).

  """

  use Mix.Task

  alias Tempo.Holidays.Build

  @impl Mix.Task
  def run(argv) do
    {options, _rest, _invalid} = OptionParser.parse(argv, strict: [language: :string])
    Mix.Task.run("app.start")

    case Build.build(options) do
      {:ok, count} ->
        Mix.shell().info(
          "tempo_holidays: rebuilt #{count} territories from date-holidays #{Build.pinned_version()}"
        )
    end
  end
end
