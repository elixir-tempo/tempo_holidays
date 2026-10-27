defmodule Tempo.Holidays.ConfiguredHolidaysTest do
  # Holidays of your own from `config :tempo_holidays, holidays:`. The
  # application environment is global, so these tests run on their own, after
  # the asynchronous ones.
  use ExUnit.Case, async: false

  import Tempo.Sigils

  alias Tempo.Holidays
  alias Tempo.IntervalSet

  @company_day {"1st friday in December", name: "Company Day"}

  setup do
    on_exit(fn -> Application.delete_env(:tempo_holidays, :holidays) end)
  end

  defp configure(holidays) do
    Application.put_env(:tempo_holidays, :holidays, holidays)
  end

  # The days in 2026 a target's holidays of a name start on.
  defp days_named(target, name, options \\ []) do
    {:ok, holidays} = Holidays.holidays(target, options)
    {:ok, occurrences} = Tempo.to_interval(holidays, within: ~o"2026")

    for occurrence <- IntervalSet.members(occurrences),
        Tempo.metadata(occurrence).name == name,
        do: Tempo.Interval.from(occurrence)
  end

  test "a territory's holidays apply to it and its subdivisions" do
    configure(AU: [add: [@company_day]])

    assert days_named(:AU, "Company Day") == [~o"2026Y12M4D"]
    assert days_named(:AU, "Company Day", subdivision: "NSW") == [~o"2026Y12M4D"]
    assert days_named(:NZ, "Company Day") == []
  end

  test "a subdivision's holidays apply to it alone" do
    configure("AU-NSW": [add: [@company_day]])

    assert days_named(:AU, "Company Day", subdivision: "NSW") == [~o"2026Y12M4D"]
    assert days_named(:AU, "Company Day", subdivision: "VIC") == []
    assert days_named(:AU, "Company Day") == []
  end

  test "a subdivision's holidays come after its territory's" do
    configure(
      "AU-NSW": [add: [{"12-11", id: "company-day", name: "Company Day"}]],
      AU: [add: [{"12-04", id: "company-day", name: "Company Day"}]]
    )

    assert days_named(:AU, "Company Day", subdivision: "NSW") == [~o"2026Y12M11D"]
    assert days_named(:AU, "Company Day", subdivision: "VIC") == [~o"2026Y12M4D"]
  end

  test "a request's own holidays come after the configured ones" do
    configure(AU: [add: [@company_day]], BR: [remove: ["Election Day"]])

    assert days_named(:AU, "Company Day", remove: ["Company Day"]) == []
    assert days_named(:BR, "Election Day") == []
  end

  test "a configuration that is not well formed is an error" do
    configure(AU: [append: [@company_day]])
    assert Holidays.holidays(:AU) == {:error, {:invalid_config, {:AU, [append: [@company_day]]}}}

    configure(%{AU: [add: [@company_day]]})
    assert Holidays.holidays(:AU) == {:error, {:invalid_config, %{AU: [add: [@company_day]]}}}

    configure(AU: [add: "12-24"])
    assert Holidays.holidays(:AU) == {:error, {:invalid_add, "12-24"}}
  end
end
