defmodule Tempo.Holidays.BuildTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Holidays.{Build, Data, Rule}

  describe "holidays_from_bundle/3" do
    setup do
      bundle = %{
        "version" => "2026-09-20",
        "holidays" => %{
          "US" => %{
            "days" => %{
              "12-25" => %{"name" => %{"en" => "Christmas Day"}},
              "4th thursday in November" => %{"name" => %{"en" => "Thanksgiving Day"}},
              # unsupported grammar (Bengali calendar, no Calendrical support) — dropped
              "bengali-revised 1-1" => %{"name" => %{"en" => "Bengali New Year"}},
              # date-holidays disables an inherited holiday with `false` — dropped
              "1st monday in May" => false
            }
          }
        }
      }

      %{bundle: bundle}
    end

    test "compiles a territory's supported holidays, skipping unsupported and disabled", %{
      bundle: bundle
    } do
      names =
        bundle
        |> Build.holidays_from_bundle("US", "en")
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert names == ["Christmas Day", "Thanksgiving Day"]
    end

    test "a territory the bundle does not carry yields none", %{bundle: bundle} do
      assert Build.holidays_from_bundle(bundle, "ZZ", "en") == []
    end

    test "a territory inherits another's holidays via `_days`, overriding by rule", %{
      bundle: bundle
    } do
      # `IX` inherits `US`, adds its own `07-04`, and removes the inherited
      # Thanksgiving with `false` — as Jersey inherits Great Britain.
      bundle =
        put_in(bundle, ["holidays", "IX"], %{
          "_days" => ["US"],
          "days" => %{
            "07-04" => %{"name" => %{"en" => "Founders' Day"}},
            "4th thursday in November" => false
          }
        })

      names =
        bundle
        |> Build.holidays_from_bundle("IX", "en")
        |> Enum.map(& &1.name)
        |> Enum.sort()

      # Inherited Christmas kept, Thanksgiving removed, own Founders' Day added.
      assert names == ["Christmas Day", "Founders' Day"]
    end
  end

  # The subdivisions of the built data, as date-holidays-parser's `getRules`
  # reads them: each level inherits what its `_days` names before its own
  # days, a country's top-level `regions` are its subdivisions, and one with
  # no days of its own has the level above's holidays.
  describe "subdivisions" do
    test "a state inherits the days its `_days` names" do
      # Saint Barthélemy is a state of France whose days are the territory BL's.
      {:ok, france} = Data.for_territory(:FR)
      {:ok, saint_barthelemy} = Data.for_territory(:FR, "BL")

      refute Enum.any?(france, &(&1.rule == "08-24"))
      assert Enum.any?(saint_barthelemy, &(&1.rule == "08-24" and &1.name == "Saint Barth"))
    end

    test "a region inherits the days its `_days` names" do
      # El Hierro, a region of the Canary Islands, has the days of IC's region EH.
      {:ok, el_hierro} = Data.for_territory(:ES, "CN-EH")
      assert Enum.any?(el_hierro, &(&1.rule == "09-24"))
    end

    test "a country's top-level regions are its subdivisions" do
      assert Data.subdivision(:AD, "07") == {:ok, "07"}
    end

    test "a region with no days of its own has its state's holidays" do
      assert Data.for_territory(:US, "LA-NO") ==
               Data.for_territory(:US, "LA")
    end
  end

  # Regression: a stale build once stored `calendar: nil` for solar-term rules,
  # so `Rule.materialise/2` crashed calling `nil.location/1`. The build must set
  # the meridian, and materialise must not crash if it is ever missing.
  describe "solar-term calendar" do
    test "a built solar-term rule reads to its solar term" do
      bundle = %{
        "holidays" => %{
          "CX" => %{"days" => %{"chinese 5-01 solarterm" => %{"name" => %{"en" => "Qingming"}}}}
        }
      }

      [holiday] = Build.holidays_from_bundle(bundle, "CX", "en")
      assert holiday.rule == "chinese 5-01 solarterm"
      assert Tempo.to_iso8601!(Tempo.DateRule.parse!(holiday.rule)) == "R/../P1Y/FL(qingming)eN"
    end

    test "materialise defaults to the Chinese meridian when the calendar is absent" do
      rule = %Rule{kind: :solar_term, calendar: nil, count: 5, day: 1}
      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2026")

      # Qingming 2026 is 5 April at the Chinese meridian. A rule that names its
      # calendar says so on its occurrence, and the day is the same day.
      assert {:ok, [named]} = Rule.materialise(%{rule | calendar: Calendrical.Chinese}, ~o"2026")
      assert Tempo.metadata(named) == %{calendar: Calendrical.Chinese}
      assert Tempo.to_elixir(named) == Tempo.to_elixir(interval)
    end
  end
end
