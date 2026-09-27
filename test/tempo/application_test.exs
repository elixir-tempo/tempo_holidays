defmodule Tempo.Holidays.ApplicationTest do
  use ExUnit.Case, async: true

  alias Tempo.Holidays.Application

  test "a time zone database is required" do
    assert {:error, {:time_zone_database_required, message}} =
             Application.check_time_zone_database(Calendar.UTCOnlyTimeZoneDatabase)

    assert message =~ "Tz.TimeZoneDatabase"
    assert Application.check_time_zone_database(Tz.TimeZoneDatabase) == :ok
  end
end
