defmodule Mix.Tasks.Tempo.Holidays.UpdateTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Tempo.Holidays.Update

  describe "holidays_from_bundle/3" do
    setup do
      bundle = %{
        "version" => "2026-09-20",
        "holidays" => %{
          "US" => %{
            "days" => %{
              "12-25" => %{"name" => %{"en" => "Christmas Day"}},
              "4th thursday in November" => %{"name" => %{"en" => "Thanksgiving Day"}},
              # unsupported grammar (time-of-day) — dropped
              "10-31 18:00" => %{"name" => %{"en" => "Halloween"}}
            }
          }
        }
      }

      %{bundle: bundle}
    end

    test "compiles a territory's supported holidays", %{bundle: bundle} do
      names =
        bundle
        |> Update.holidays_from_bundle("US", "en")
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert names == ["Christmas Day", "Thanksgiving Day"]
    end

    test "a territory the bundle does not carry yields none", %{bundle: bundle} do
      assert Update.holidays_from_bundle(bundle, "ZZ", "en") == []
    end
  end
end
