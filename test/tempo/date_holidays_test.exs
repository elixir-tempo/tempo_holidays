defmodule Tempo.Holidays.DateHolidaysTest do
  use ExUnit.Case, async: true

  alias Tempo.Holidays.DateHolidays

  doctest DateHolidays

  describe "compile_days/2" do
    test "keeps the rules Tempo.DateRule reads and drops the rest" do
      # A slice of a date-holidays `days` map: rules of its grammar, one it
      # writes no other way (`last monday in May` is `monday before 06-01`),
      # a calendar Calendrical does not have, and no rule at all.
      days = %{
        "12-25" => %{"_name" => "12-25"},
        "4th thursday in November" => %{"name" => %{"en" => "Thanksgiving Day"}},
        "monday before 06-01" => %{"name" => %{"en" => "Memorial Day"}},
        "last monday in May" => %{"name" => %{"en" => "Memorial Day, written otherwise"}},
        "bengali-revised 1-1" => %{"name" => %{"en" => "Bengali New Year"}},
        "1st day of Ramadan" => %{"name" => %{"en" => "Ramadan"}}
      }

      names = days |> DateHolidays.compile_days() |> Enum.map(& &1.name) |> Enum.sort()

      assert names == ["12-25", "Memorial Day", "Thanksgiving Day"]
    end

    test "keeps the rule and the type, and marks a substitute entry" do
      days = %{
        "07-04 and if saturday then previous friday if sunday then next monday" => %{
          "substitute" => true,
          "name" => %{"en" => "Independence Day"}
        },
        "substitutes 07-04 if sunday then next monday" => %{"name" => %{"en" => "Observed"}},
        "easter" => %{"_name" => "easter", "type" => "observance"}
      }

      holidays = Map.new(DateHolidays.compile_days(days), &{&1.name, &1})

      assert holidays["Independence Day"].rule ==
               "07-04 and if saturday then previous friday if sunday then next monday"

      refute holidays["Independence Day"].substitute
      assert holidays["Observed"].substitute
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

      spanish = Map.new(DateHolidays.compile_days(days, language: "es"), &{&1.rule, &1.name})

      assert spanish["3rd monday in January"] == "Natalicio de Martin Luther King, Jr."
      # With no names table given, a `_name` reference stands in for its name.
      assert spanish["05-01"] == "05-01"

      # A language the entry lacks falls back to English.
      german = Map.new(DateHolidays.compile_days(days, language: "de"), &{&1.rule, &1.name})
      assert german["3rd monday in January"] == "Martin Luther King Jr. Day"
    end

    test "keeps the disable, enable and active metadata beside the rule" do
      days = %{
        "1st monday before 06-01" => %{
          "name" => %{"en" => "Spring bank holiday"},
          "disable" => ["2022-05-30"],
          "enable" => ["2022-06-02"]
        },
        "10-19" => %{
          "name" => %{"en" => "Mother Teresa Day"},
          "active" => [%{"from" => 2004}]
        }
      }

      holidays = Map.new(DateHolidays.compile_days(days), &{&1.name, &1})

      spring = holidays["Spring bank holiday"]
      assert spring.disable == [~D[2022-05-30]]
      assert spring.enable == [~D[2022-06-02]]

      # An integer `from` year means that year's 1 January, and the window is
      # open-ended above.
      assert holidays["Mother Teresa Day"].active == [{~D[2004-01-01], nil}]
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
