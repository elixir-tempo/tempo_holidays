defmodule Tempo.Holidays.DateHolidaysTest do
  use ExUnit.Case, async: true

  alias Tempo.Holidays.DateHolidays

  doctest DateHolidays

  describe "compile_days/2" do
    test "compiles the supported rules and drops the rest" do
      # A realistic slice of a date-holidays `days` map: some rules the
      # compiler understands, some it does not yet.
      days = %{
        "12-25" => %{"_name" => "12-25"},
        "4th thursday in November" => %{"name" => %{"en" => "Thanksgiving Day"}},
        "last monday in May" => %{"name" => %{"en" => "Memorial Day"}},
        "10-31 18:00" => %{"name" => %{"en" => "Halloween"}},
        "1st day of Ramadan" => %{"name" => %{"en" => "Ramadan"}}
      }

      names = days |> DateHolidays.compile_days() |> Enum.map(& &1.name) |> Enum.sort()

      assert names == ["12-25", "Memorial Day", "Thanksgiving Day"]
    end

    test "carries the substitution and type through from the rule and metadata" do
      days = %{
        "07-04 and if saturday then previous friday if sunday then next monday" => %{
          "substitute" => true,
          "name" => %{"en" => "Independence Day"}
        },
        "easter" => %{"_name" => "easter", "type" => "observance"}
      }

      holidays = Map.new(DateHolidays.compile_days(days), &{&1.name, &1})

      assert holidays["Independence Day"].rule.substitute ==
               [{[6], :previous, 5}, {[7], :next, 1}]

      assert holidays["easter"].type == :observance
    end

    test "picks a localized name, falling back to English then the reference" do
      days = %{
        "3rd monday in January" => %{
          "name" => %{
            "en" => "Martin Luther King Jr. Day",
            "es" => "Natalicio de Martin Luther King, Jr."
          }
        },
        "05-01" => %{"_name" => "05-01"}
      }

      spanish =
        Map.new(DateHolidays.compile_days(days, language: "es"), &{&1.rule.month, &1.name})

      assert spanish[1] == "Natalicio de Martin Luther King, Jr."
      # With no names table given, a `_name` reference stands in for its name.
      assert spanish[5] == "05-01"

      # A language the entry lacks falls back to English.
      german = Map.new(DateHolidays.compile_days(days, language: "de"), &{&1.rule.month, &1.name})
      assert german[1] == "Martin Luther King Jr. Day"
    end

    test "resolves a _name reference against the bundle's names table" do
      days = %{"01-01" => %{"_name" => "01-01"}}
      names = %{"01-01" => %{"name" => %{"en" => "New Year's Day", "fr" => "Nouvel An"}}}

      assert [english] = DateHolidays.compile_days(days, names: names)
      assert english.name == "New Year's Day"

      assert [french] = DateHolidays.compile_days(days, names: names, language: "fr")
      assert french.name == "Nouvel An"

      # A reference absent from the table stands in for its own name.
      absent = DateHolidays.compile_days(%{"01-06" => %{"_name" => "01-06"}}, names: names)
      assert [%{name: "01-06"}] = absent
    end
  end
end
