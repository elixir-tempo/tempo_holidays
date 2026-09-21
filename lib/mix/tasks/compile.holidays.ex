defmodule Mix.Tasks.Compile.Holidays do
  @moduledoc false

  use Mix.Task.Compiler

  # Generate the compiled holiday data as part of `mix compile`.
  #
  # Runs after the Elixir compiler (so `Tempo.Holidays.Build` and the rule
  # compiler it uses are available) and is a no-op once the pinned data is on
  # disk — so warm builds, and every consumer build where the etf ships in the
  # package, do no work and touch no network. A cold build downloads the pinned
  # bundle once and writes `priv/holidays/<CC>.etf`.

  @recursive false

  alias Tempo.Holidays.Build

  @impl Mix.Task.Compiler
  def run(_argv) do
    case Build.ensure_built() do
      :noop -> {:noop, []}
      :ok -> {:ok, []}
    end
  end
end
