defmodule Mix.Tasks.Tempo.Holidays.Update do
  @shortdoc "Download a date-holidays release and compile it into holiday data"

  @moduledoc """
  Download a [date-holidays](https://github.com/commenthol/date-holidays)
  release and compile it into the holiday data `Tempo.Holidays` reads.

  `Tempo.Holidays` ships data built from the release it pins. A newer release
  carries corrections and new holidays before a new `tempo_holidays` does:
  this task builds the data from any release, into a directory of your
  application that the library then reads instead of its own.

  ## In your application

  Name a directory in your application's `priv` for the data:

      # config/config.exs
      config :tempo_holidays, data_dir: {:my_app, "holidays"}

  then build it from the release you want:

      mix tempo.holidays.update --version 3.38.0

  The data is written to `priv/holidays` of your project, so it goes into a
  release with your application and can be committed with it.
  `Tempo.Holidays.Data.version/0` says which release is loaded. An absolute
  path is also accepted as `data_dir`.

  The data is read only while it is in the format of the `tempo_holidays`
  release that reads it: after an upgrade of `tempo_holidays` that changes
  the format, the package's own data is read until the task is run again.

  ## In `tempo_holidays` itself

  The task writes the package's own `priv/holidays`, which the `:holidays`
  compiler builds on a cold build from the pinned release. Run it after the
  pinned version (`Tempo.Holidays.Build`) is bumped.

  ## Usage

      mix tempo.holidays.update
      mix tempo.holidays.update --version 3.38.0
      mix tempo.holidays.update --language es

  ## Options

  * `--version` — the date-holidays release, three numbers such as `3.38.0`.
    The default is the release `tempo_holidays` pins.

  * `--language` — the ISO 639-1 code for holiday names. The default is `en`.

  """

  use Mix.Task

  alias Tempo.Holidays.Build

  @impl Mix.Task
  def run(argv) do
    {options, _rest, _invalid} =
      OptionParser.parse(argv, strict: [language: :string, version: :string])

    Mix.Task.run("app.config")
    _ = Application.ensure_all_started(:tempo_holidays)

    directory = target_directory(Mix.Project.config()[:app])
    version = Keyword.get(options, :version, Build.pinned_version())

    case Build.build([directory: directory] ++ options) do
      {:ok, count, unsupported} ->
        Mix.shell().info(
          "tempo_holidays: wrote #{count} territories from date-holidays #{version} " <>
            "to #{Path.relative_to_cwd(directory)}"
        )

        left_out(unsupported, version)
    end
  end

  # The rules this release of tempo_holidays does not compile yet: their
  # holidays are not in the data, and the user is told which.
  defp left_out([], _version) do
    :ok
  end

  defp left_out(rules, version) do
    Mix.shell().info(
      "tempo_holidays: #{length(rules)} rules of date-holidays #{version} are not compiled " <>
        "by this release of tempo_holidays, and their holidays are left out:\n" <>
        Enum.map_join(rules, "\n", &("  " <> &1))
    )
  end

  @doc false
  # In `tempo_holidays` itself, the package's own data; in an application, the
  # directory its configuration names.
  @spec target_directory(atom()) :: String.t()
  def target_directory(:tempo_holidays) do
    Build.default_directory()
  end

  def target_directory(app) do
    configured_directory(app, Application.get_env(:tempo_holidays, :data_dir))
  end

  defp configured_directory(app, {app, path}) when is_binary(path) do
    Path.join([Path.dirname(Mix.Project.project_file()), "priv", path])
  end

  defp configured_directory(app, {other, path}) when is_atom(other) and is_binary(path) do
    Mix.raise(
      "tempo_holidays: data_dir names #{inspect(other)}, and this is the #{inspect(app)} " <>
        "project; run the task in #{inspect(other)}'s project"
    )
  end

  defp configured_directory(_app, path) when is_binary(path) do
    Path.expand(path)
  end

  defp configured_directory(app, nil) do
    Mix.raise("""
    tempo_holidays: name a directory for the holiday data first, in config/config.exs:

        config :tempo_holidays, data_dir: {#{inspect(app)}, "holidays"}

    The data is then written to priv/holidays of this project, and read from there.
    """)
  end

  defp configured_directory(app, other) do
    Mix.raise(
      "tempo_holidays: data_dir is {#{inspect(app)}, \"holidays\"} or an absolute path, " <>
        "not #{inspect(other)}"
    )
  end
end
