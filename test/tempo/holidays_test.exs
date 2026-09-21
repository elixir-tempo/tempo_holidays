defmodule Tempo.HolidaysTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Holidays
  alias Tempo.Holidays.{Compiler, Holiday, Rule}

  # All the dates a named holiday occupies that year. A substituted holiday
  # keeps its actual date *and* adds the observed one, so a name maps to one
  # or more dates.
  defp dates_of(holidays, name) do
    for {holiday, interval} <- holidays, holiday.name == name, do: Tempo.Interval.from(interval)
  end

  doctest Tempo.Holidays
  doctest Tempo.Holidays.Data
  doctest Tempo.Holidays.Compiler
  doctest Tempo.Holidays.Rule

  describe "recurrences/1" do
    test "returns the AU holidays as recurrences" do
      # Whichever source answers — the vendored ETF (all types) or the seed
      # fallback — the national public holidays are present as %Holiday{}
      # recurrences.
      assert {:ok, holidays} = Holidays.recurrences(:AU)
      assert Enum.all?(holidays, &match?(%Holiday{rule: %Rule{}}, &1))
      names = Enum.map(holidays, & &1.name)
      assert "New Year's Day" in names
      assert "Christmas Day" in names
    end

    test "an unknown territory is an error, not a crash" do
      assert {:error, {:unknown_territory, "ZZ"}} = Holidays.recurrences(:ZZ)
    end

    test "a territory code string is accepted, case-insensitively" do
      assert {:ok, holidays} = Holidays.recurrences("au")
      assert Enum.any?(holidays, &(&1.name == "New Year's Day"))
    end

    test "a value that is neither atom nor string is an invalid locale, not a crash" do
      assert {:error, {:invalid_locale, 123}} = Holidays.recurrences(123)
    end
  end

  describe "materialise/2" do
    test "projects every AU holiday onto 2026" do
      assert {:ok, holidays} = Holidays.materialise(:AU, ~o"2026")

      assert ~o"2026Y1M1D" in dates_of(holidays, "New Year's Day")
      assert ~o"2026Y1M26D" in dates_of(holidays, "Australia Day")
      assert ~o"2026Y4M3D" in dates_of(holidays, "Good Friday")
      assert ~o"2026Y4M25D" in dates_of(holidays, "Anzac Day")
      assert ~o"2026Y12M25D" in dates_of(holidays, "Christmas Day")
      # Boxing Day 2026 is Saturday the 26th; the observed Monday the 28th is added.
      assert ~o"2026Y12M28D" in dates_of(holidays, "Boxing Day")
    end

    test "returns the holidays earliest first" do
      {:ok, holidays} = Holidays.materialise(:AU, ~o"2026")
      names = Enum.map(holidays, fn {holiday, _interval} -> holiday.name end)

      assert hd(names) == "New Year's Day"
      assert "Boxing Day" in names
    end

    test "the recurrence re-projects onto a different year" do
      # Easter moves year to year: in 2027 Easter Sunday is 28 March, so Good
      # Friday is the 26th and Easter Monday the 29th.
      {:ok, holidays} = Holidays.materialise(:AU, ~o"2027")

      assert ~o"2027Y3M26D" in dates_of(holidays, "Good Friday")
      assert ~o"2027Y3M29D" in dates_of(holidays, "Easter Monday")
    end

    test "an unknown territory is an error, not a crash" do
      assert {:error, {:unknown_territory, "ZZ"}} = Holidays.materialise(:ZZ, ~o"2026")
    end
  end

  describe "coalescing back-to-back entries" do
    test "two same-name abutting entries merge into one period" do
      # date-holidays splits a period it cannot express across a year
      # boundary into two entries under one name. Materialised, the two
      # abutting days are coalesced into the single span they describe.
      {:ok, part_1} = Compiler.compile("12-25")
      {:ok, part_2} = Compiler.compile("12-26")

      holidays = [
        %Holiday{name: "Festival", type: :school, rule: part_1},
        %Holiday{name: "Festival", type: :school, rule: part_2}
      ]

      assert {:ok, [{holiday, interval}]} = Holidays.materialise(holidays, ~o"2026")
      assert holiday.name == "Festival"
      assert Tempo.Interval.from(interval) == ~o"2026Y12M25D"
      assert Tempo.Interval.to(interval) == ~o"2026Y12M27D"
    end

    test "adjacent holidays with different names stay separate" do
      # Christmas and Boxing Day are different holidays, so name-aware
      # coalescing leaves them as separate entries rather than merging.
      {:ok, holidays} = Holidays.materialise(:AU, ~o"2026")
      names = Enum.map(holidays, fn {holiday, _interval} -> holiday.name end)

      assert "Christmas Day" in names
      assert "Boxing Day" in names
    end
  end

  describe "observed-date substitution" do
    test "a holiday on a Sunday is observed the following Monday" do
      # Australia Day 2025 falls on Sunday the 26th, so Monday the 27th is
      # observed alongside it.
      {:ok, holidays} = Holidays.materialise(:AU, ~o"2025")
      assert ~o"2025Y1M27D" in dates_of(holidays, "Australia Day")
    end

    test "a holiday on a Saturday is observed the following Monday" do
      # New Year's Day 2028 falls on Saturday the 1st; Monday the 3rd observed.
      {:ok, holidays} = Holidays.materialise(:AU, ~o"2028")
      assert ~o"2028Y1M3D" in dates_of(holidays, "New Year's Day")
    end

    test "a weekday holiday is not shifted" do
      # 26 January 2026 is a Monday — no substitution, one date only.
      {:ok, holidays} = Holidays.materialise(:AU, ~o"2026")
      assert dates_of(holidays, "Australia Day") == [~o"2026Y1M26D"]
    end

    test "a holiday carrying no substitution rule keeps its own date" do
      {:ok, anzac} = Compiler.compile("04-25")
      assert anzac.substitute == nil
    end
  end

  describe "US federal holidays" do
    test "projects the 2026 federal holidays" do
      # date-holidays carries all types, so the US set includes observances
      # (Valentine's Day, Tax Day, …) alongside the federal public holidays
      # asserted here. It spells Labor "Labour"; Juneteenth is honoured through
      # its `since 2021` filter.
      assert {:ok, holidays} = Holidays.materialise(:US, ~o"2026")

      assert ~o"2026Y1M1D" in dates_of(holidays, "New Year's Day")
      assert ~o"2026Y6M19D" in dates_of(holidays, "Juneteenth")
      assert ~o"2026Y1M19D" in dates_of(holidays, "Martin Luther King Jr. Day")
      assert ~o"2026Y2M16D" in dates_of(holidays, "Washington's Birthday")
      assert ~o"2026Y5M25D" in dates_of(holidays, "Memorial Day")
      # 4 July 2026 is a Saturday, so Friday the 3rd is observed alongside it.
      assert ~o"2026Y7M3D" in dates_of(holidays, "Independence Day")
      assert ~o"2026Y9M7D" in dates_of(holidays, "Labour Day")
      assert ~o"2026Y10M12D" in dates_of(holidays, "Columbus Day")
      assert ~o"2026Y11M11D" in dates_of(holidays, "Veterans Day")
      assert ~o"2026Y11M26D" in dates_of(holidays, "Thanksgiving Day")
      assert ~o"2026Y12M25D" in dates_of(holidays, "Christmas Day")
    end

    test "Memorial Day is the last Monday in May" do
      {:ok, holidays} = Holidays.materialise(:US, ~o"2026")
      assert dates_of(holidays, "Memorial Day") == [~o"2026Y5M25D"]
    end

    test "a Saturday holiday is observed the prior Friday" do
      # Independence Day 2026 is Saturday 4 July; the US observes Friday the
      # 3rd alongside it — the opposite direction to the AU weekend rule.
      {:ok, holidays} = Holidays.materialise(:US, ~o"2026")
      assert ~o"2026Y7M3D" in dates_of(holidays, "Independence Day")
    end

    test "a Sunday holiday is observed the next Monday" do
      # New Year's Day 2023 is Sunday 1 January; the observed Monday the 2nd
      # abuts it, so the two coalesce into a single Jan 1–2 span.
      {:ok, holidays} = Holidays.materialise(:US, ~o"2023")
      assert [interval] = for({holiday, iv} <- holidays, holiday.name == "New Year's Day", do: iv)
      assert Tempo.Interval.from(interval) == ~o"2023Y1M1D"
      assert Tempo.Interval.to(interval) == ~o"2023Y1M3D"
    end
  end

  describe "relative-weekday holidays" do
    test "the weekday before a date — US Memorial Day (monday before 06-01)" do
      {:ok, rule} = Compiler.compile("monday before 06-01")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2026")
      assert Tempo.Interval.from(interval) == ~o"2026Y5M25D"

      # Re-projects: the last Monday of May 2027 is the 31st.
      assert {:ok, [interval_2027]} = Rule.materialise(rule, ~o"2027")
      assert Tempo.Interval.from(interval_2027) == ~o"2027Y5M31D"
    end

    test "the weekday after a date (friday after 11-11)" do
      {:ok, rule} = Compiler.compile("friday after 11-11")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2026")
      assert Tempo.Interval.from(interval) == ~o"2026Y11M13D"
    end
  end

  describe "Islamic (Hijri) holidays" do
    test "materialise in the Islamic calendar, not Gregorian" do
      # Islamic New Year — 1 Muharram. Projected onto the Gregorian year
      # 2025, which holds 1 Muharram of the Hijri year 1447.
      {:ok, rule} = Compiler.compile("1 Muharram")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(interval) == ~o"1447Y1M1D[u-ca=islamic-umalqura]"
    end

    test "a P<n>D span covers that many days, crossing months in-calendar" do
      # Eid al-Fitr — "30 Ramadan P4D" runs from 30 Ramadan into Shawwal.
      # 30 Ramadan 1447 falls in the Gregorian year 2026.
      {:ok, rule} = Compiler.compile("30 Ramadan P4D")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2026")
      assert Tempo.Interval.from(interval) == ~o"1447Y9M30D[u-ca=islamic-umalqura]"
      assert Tempo.Interval.to(interval) == ~o"1447Y10M4D[u-ca=islamic-umalqura]"
    end

    test "a lunar date can fall twice in one Gregorian year" do
      # 30 Ramadan (Eid al-Fitr's eve) fell in both Hijri 1420 and 1421
      # within the Gregorian year 2000 — the recurrence yields both.
      {:ok, rule} = Compiler.compile("30 Ramadan P4D")

      assert {:ok, [first, second]} = Rule.materialise(rule, ~o"2000")
      assert Tempo.Interval.from(first) == ~o"1420Y9M30D[u-ca=islamic-umalqura]"
      assert Tempo.Interval.to(first) == ~o"1420Y10M4D[u-ca=islamic-umalqura]"
      assert Tempo.Interval.from(second) == ~o"1421Y9M30D[u-ca=islamic-umalqura]"
      assert Tempo.Interval.to(second) == ~o"1421Y10M4D[u-ca=islamic-umalqura]"
    end
  end

  describe "locale and state resolution" do
    test "a locale with a subdivision loads the state's holidays" do
      {:ok, national} = Holidays.recurrences(:US)
      {:ok, california} = Holidays.recurrences("en-US-u-sd-usca")

      refute "Presidents' Day" in Enum.map(national, & &1.name)
      assert "Presidents' Day" in Enum.map(california, & &1.name)
    end

    test "the division option selects a state — NSW carries King's Birthday" do
      {:ok, nsw} = Holidays.materialise(:AU, ~o"2026", division: "NSW")
      assert Enum.any?(nsw, fn {holiday, _interval} -> holiday.name == "King's Birthday" end)
    end

    test "an unknown state falls back to the country" do
      {:ok, holidays} = Holidays.recurrences(:US, division: "ZZ")
      assert Enum.any?(holidays, &(&1.name == "New Year's Day"))
    end
  end
end
