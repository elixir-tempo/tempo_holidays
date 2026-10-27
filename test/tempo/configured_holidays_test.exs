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

  # The days in 2026 a target's holidays, or a set of holidays, of a name
  # start on.
  defp days_named(target, name, options \\ [])

  defp days_named(%Tempo{} = holidays, name, _options) do
    {:ok, occurrences} = Tempo.to_interval(holidays, within: ~o"2026")

    for occurrence <- IntervalSet.members(occurrences),
        Tempo.metadata(occurrence).name == name,
        do: Tempo.Interval.from(occurrence)
  end

  defp days_named(target, name, options) do
    {:ok, holidays} = Holidays.holidays(target, options)
    days_named(holidays, name)
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

  test "a configured holiday is the territory's, selected by type as the dataset's are" do
    configure(AU: [add: [{"1st friday in December", name: "Company Day", type: :optional}]])

    assert days_named(:AU, "Company Day") == [~o"2026Y12M4D"]
    assert days_named(:AU, "Company Day", include: :public) == []
  end

  test "a configuration removes holidays by id or name, one or a list" do
    configure(AU: [remove: "04-25"], BR: [remove: ["Election Day"]])

    assert days_named(:AU, "Anzac Day") == []
    assert days_named(:BR, "Election Day") == []
  end

  test "add/3 and remove/2 change the holidays the configuration gives" do
    configure(AU: [add: [{"12-04", id: "company-day", name: "Company Day"}]])
    {:ok, holidays} = Holidays.holidays(:AU)

    {:ok, moved} = Holidays.add(holidays, "12-11", id: "company-day", name: "Company Day")
    {:ok, removed} = Holidays.remove(holidays, "Company Day")

    assert days_named(moved, "Company Day") == [~o"2026Y12M11D"]
    assert days_named(removed, "Company Day") == []
  end

  test "a configuration that is not well formed is an error" do
    configure(AU: [append: [@company_day]])
    assert Holidays.holidays(:AU) == {:error, {:invalid_config, {:AU, [append: [@company_day]]}}}

    configure(%{AU: [add: [@company_day]]})

    assert Holidays.holidays(:AU) ==
             {:error, {:invalid_config, %{AU: [add: [@company_day]]}}}

    configure(AU: [add: 42])
    assert Holidays.holidays(:AU) == {:error, {:invalid_config, {:AU, [add: 42]}}}

    # Types are a request's to select, with `:include` and `:exclude`.
    configure(AU: [remove: :observance])
    assert Holidays.holidays(:AU) == {:error, {:invalid_config, {:AU, [remove: :observance]}}}

    configure(AU: [include: [@company_day]])
    assert Holidays.holidays(:AU) == {:error, {:invalid_config, {:AU, [include: [@company_day]]}}}
  end
end
