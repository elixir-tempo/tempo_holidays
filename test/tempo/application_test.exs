defmodule Tempo.Holidays.ApplicationTest do
  use ExUnit.Case, async: true

  alias Tempo.Holidays.Application

  test "the database checked is the one Tempo asks, which knows named zones" do
    assert Application.check_time_zone_database(Tempo.time_zone_database()) == :ok
  end

  test "a database that knows only UTC is refused" do
    assert {:error, {:time_zone_database_required, message}} =
             Application.check_time_zone_database(Calendar.UTCOnlyTimeZoneDatabase)

    assert message =~ "Tz.TimeZoneDatabase"
    assert Application.check_time_zone_database(Tz.TimeZoneDatabase) == :ok
  end
end
