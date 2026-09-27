defmodule Tempo.Holidays.Application do
  @moduledoc false

  # tempo_holidays requires a time zone database, as Tempo does for its zone
  # work: an equinox or solstice in a named zone takes its date through it. The
  # application refuses to start without one, rather than let such a holiday
  # silently fall out of the year.

  use Application

  @impl true
  def start(_type, _args) do
    with :ok <- check_time_zone_database(Tempo.TimeZoneDatabase.database()) do
      Supervisor.start_link([], strategy: :one_for_one, name: Tempo.Holidays.Supervisor)
    end
  end

  @doc false
  def check_time_zone_database(Calendar.UTCOnlyTimeZoneDatabase) do
    {:error,
     {:time_zone_database_required,
      "tempo_holidays needs a time zone database. Configure one, for example " <>
        "`config :elixir, :time_zone_database, Tz.TimeZoneDatabase` (Tz is a " <>
        "tempo_holidays dependency)."}}
  end

  def check_time_zone_database(_database), do: :ok
end
