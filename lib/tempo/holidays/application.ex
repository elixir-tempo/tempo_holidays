defmodule Tempo.Holidays.Application do
  @moduledoc false

  # tempo_holidays reads a zone as Tempo does, through the time zone
  # database Tempo asks (`Tempo.time_zone_database/0`): an equinox or
  # solstice in a named zone takes its date through it. Tempo asks `tz`
  # where nothing else is configured, so the application refuses to start
  # only with a database that knows only UTC, named for Tempo, rather than
  # let such a holiday silently fall out of the year.

  use Application

  @impl true
  def start(_type, _args) do
    with :ok <- check_time_zone_database(Tempo.time_zone_database()) do
      Supervisor.start_link([], strategy: :one_for_one, name: Tempo.Holidays.Supervisor)
    end
  end

  @doc false
  def check_time_zone_database(Calendar.UTCOnlyTimeZoneDatabase) do
    {:error,
     {:time_zone_database_required,
      "tempo_holidays needs a time zone database that knows named zones, and " <>
        "Tempo is configured with one that knows only UTC. Remove " <>
        "`config :ex_tempo, :time_zone_database` so that Tempo asks tz, or name " <>
        "another, for example `config :ex_tempo, :time_zone_database, Tz.TimeZoneDatabase`."}}
  end

  def check_time_zone_database(_database), do: :ok
end
