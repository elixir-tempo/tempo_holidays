defmodule Tempo.Holidays.BuildTest do
  use ExUnit.Case, async: true

  alias Tempo.Holidays.Build

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
end
