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

  # The single interval a one-holiday list materialises to that year, under a
  # `day_start` projection.
  defp single_interval(holidays, year, day_start) do
    {:ok, [{_holiday, interval}]} = Holidays.materialise(holidays, year, day_start: day_start)
    interval
  end

  defp holiday_list(rule_string, name) do
    {:ok, rule} = Compiler.compile(rule_string)
    [%Holiday{name: name, type: :public, rule: rule}]
  end

  # The Gregorian ISO dates a rule materialises to that year — useful for a
  # calendar (Vietnamese) whose in-calendar value carries a shared CLDR tag.
  defp gregorian_dates(rule_string, year) do
    {:ok, rule} = Compiler.compile(rule_string)
    {:ok, intervals} = Rule.materialise(rule, year)

    Enum.map(intervals, fn interval ->
      {:ok, date} = Tempo.to_date(Tempo.Interval.from(interval))
      {:ok, iso} = Date.convert(date, Calendar.ISO)
      Date.to_iso8601(iso)
    end)
  end

  doctest Tempo.Holidays
  doctest Tempo.Holidays.Data
  doctest Tempo.Holidays.Compiler
  doctest Tempo.Holidays.Rule
  doctest Tempo.Holidays.DayStart

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

  describe "occurrence-level metadata gates (active / disable / enable)" do
    test "a disable+enable pair moves a real holiday — GB Spring bank holiday, 2022 Jubilee" do
      # In 2022 the Spring bank holiday was moved off the last-Monday-of-May
      # (30 May) to Thursday 2 June for the Platinum Jubilee, expressed in the
      # data as disable 2022-05-30 + enable 2022-06-02.
      {:ok, holidays} = Holidays.materialise(:GB, ~o"2022")

      assert ~o"2022Y6M2D" in dates_of(holidays, "Spring bank holiday")
      refute ~o"2022Y5M30D" in dates_of(holidays, "Spring bank holiday")

      # A year the move does not touch keeps the computed last Monday of May.
      {:ok, holidays_2021} = Holidays.materialise(:GB, ~o"2021")
      assert ~o"2021Y5M31D" in dates_of(holidays_2021, "Spring bank holiday")
    end

    test "a disabled occurrence is dropped — GB Early May bank holiday, 2020" do
      # The 2020 Early May bank holiday was disabled (moved to VE Day, 8 May).
      {:ok, holidays_2020} = Holidays.materialise(:GB, ~o"2020")
      refute ~o"2020Y5M4D" in dates_of(holidays_2020, "Early May bank holiday")

      {:ok, holidays_2021} = Holidays.materialise(:GB, ~o"2021")
      assert ~o"2021Y5M3D" in dates_of(holidays_2021, "Early May bank holiday")
    end

    test "an active window gates a rule to its years" do
      {:ok, base} = Compiler.compile("03-20")
      rule = %{base | active: [{~D[2010-01-01], nil}]}

      assert {:ok, []} = Rule.materialise(rule, ~o"2009")
      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2010")
      assert Tempo.Interval.from(interval) == ~o"2010Y3M20D"
    end

    test "a disable+enable pair moves a hand-built occurrence, leaving other years alone" do
      {:ok, base} = Compiler.compile("03-20")
      rule = %{base | disable: [~D[2010-03-20]], enable: [~D[2010-03-22]]}

      assert {:ok, [moved]} = Rule.materialise(rule, ~o"2010")
      assert Tempo.Interval.from(moved) == ~o"2010Y3M22D"

      assert {:ok, [untouched]} = Rule.materialise(rule, ~o"2011")
      assert Tempo.Interval.from(untouched) == ~o"2011Y3M20D"
    end
  end

  describe "Hebrew calendar holidays" do
    test "materialise in the Hebrew calendar, not Gregorian" do
      # Rosh Hashanah — 1 Tishrei. Projected onto Gregorian 2025, which holds
      # 1 Tishrei of the Hebrew year 5786.
      {:ok, rule} = Compiler.compile("1 Tishrei")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(interval) == ~o"5786Y1M1D[u-ca=hebrew]"
    end

    test "Adar II carries Purim in both leap and non-leap years" do
      # date-holidays writes Purim as "14 AdarII"; Calendrical's civil month 7
      # is the Adar before Nisan — Adar in an ordinary year, Adar II in a leap
      # year — so the same number serves both.
      {:ok, rule} = Compiler.compile("14 AdarII")

      # 2025 → Hebrew 5785, an ordinary year.
      assert {:ok, [ordinary]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(ordinary) == ~o"5785Y7M14D[u-ca=hebrew]"

      # 2024 → Hebrew 5784, a leap year; month 7 is Adar II.
      assert {:ok, [leap]} = Rule.materialise(rule, ~o"2024")
      assert Tempo.Interval.from(leap) == ~o"5784Y7M14D[u-ca=hebrew]"
    end
  end

  describe "Julian calendar holidays" do
    test "a Julian fixed date is returned in the Julian calendar" do
      # Orthodox Christmas — julian 12-25 — the Julian date whose Gregorian
      # projection (7 January this century) falls in the requested year.
      {:ok, rule} = Compiler.compile("julian 12-25")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(interval) == ~o"2024Y12M25D[u-ca=julian]"

      assert {:ok, ~o"2025Y1M7D"} =
               Tempo.to_calendar(Tempo.Interval.from(interval), Calendrical.Gregorian)
    end

    test "a P<n>D span covers that many days" do
      {:ok, rule} = Compiler.compile("julian 12-25 P2D")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(interval) == ~o"2024Y12M25D[u-ca=julian]"
      assert Tempo.Interval.to(interval) == ~o"2024Y12M27D[u-ca=julian]"
    end
  end

  describe "lunisolar calendar holidays (Chinese, Korean)" do
    test "Chinese New Year is returned in the Chinese calendar" do
      {:ok, rule} = Compiler.compile("chinese 01-0-01")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(interval) == ~o"4662Y1M1D[u-ca=chinese]"
    end

    test "the traditional month is resolved past an intercalary month" do
      # Mid-Autumn is traditional month 8; the Chinese year 4662 carries a leap
      # month 6, so the ordinal month of the returned date is 9.
      {:ok, rule} = Compiler.compile("chinese 08-0-15")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(interval) == ~o"4662Y9M15D[u-ca=chinese]"
    end

    test "day 0 is the eve — the last day of the previous month" do
      {:ok, rule} = Compiler.compile("chinese 01-0-00")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(interval) == ~o"4661Y12M29D[u-ca=chinese]"
    end

    test "Korean Seollal is returned in the Korean (dangi) calendar with its span" do
      {:ok, rule} = Compiler.compile("korean 01-0-01 P3D")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(interval) == ~o"4358Y1M1D[u-ca=dangi]"
      assert Tempo.Interval.to(interval) == ~o"4358Y1M4D[u-ca=dangi]"
    end
  end

  describe "Chinese solar-term holidays" do
    test "Qingming is the day the sun reaches 15° ecliptic longitude, in China time" do
      {:ok, rule} = Compiler.compile("chinese 5-01 solarterm")

      # Qingming is 4 April in 2025, 5 April in 2023.
      assert {:ok, [y2025]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(y2025) == ~o"2025Y4M4D"

      assert {:ok, [y2023]} = Rule.materialise(rule, ~o"2023")
      assert Tempo.Interval.from(y2023) == ~o"2023Y4M5D"
    end
  end

  describe "equinox and solstice holidays" do
    test "Japan's Vernal Equinox Day is the March equinox in JST" do
      {:ok, rule} = Compiler.compile("march equinox in +09:00")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(interval) == ~o"2025Y3M20D"
    end

    test "Japan's Autumnal Equinox Day is the September equinox in JST" do
      {:ok, rule} = Compiler.compile("september equinox in +09:00")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(interval) == ~o"2025Y9M23D"
    end

    test "a solstice with no timezone is computed in GMT" do
      {:ok, rule} = Compiler.compile("december solstice")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(interval) == ~o"2025Y12M21D"
    end

    test "a numeric-offset timezone HH:MM survives time-stripping" do
      # `strip_time` must not mistake the `:00` of `+09:00` for a clock time.
      {:ok, rule} = Compiler.compile("march equinox in +09:00")

      assert rule.kind == :equinox
      assert rule.timezone == "+09:00"
    end

    test "a named IANA timezone resolves the civil date via the tz database" do
      # Chile's June solstice, observed in Santiago (UTC−4 in June).
      {:ok, rule} = Compiler.compile("june solstice in America/Santiago")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(interval) == ~o"2025Y6M20D"
    end
  end

  describe "grammar extensions" do
    test "an Easter-relative rule carries a P<n>D span" do
      {:ok, rule} = Compiler.compile("easter 47 P4D")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      # Easter 2025 is 20 April; +47 days is 6 June, spanning four days.
      assert Tempo.Interval.from(interval) == ~o"2025Y6M6D"
      assert Tempo.Interval.to(interval) == ~o"2025Y6M10D"
    end

    test "a calendar span tolerates a full duration suffix (P3DT0H0M)" do
      {:ok, with_time} = Compiler.compile("1 Shawwal P3DT0H0M")
      {:ok, plain} = Compiler.compile("1 Shawwal P3D")

      assert with_time.count == 3
      assert with_time.count == plain.count
    end

    test "a weekday after the Nth weekday after a fixed date" do
      # The Thursday after the first Sunday on or after 1 September.
      {:ok, rule} = Compiler.compile("thursday after 1st sunday after 09-01")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(interval) == ~o"2025Y9M11D"
    end

    test "an Nth weekday in month overflows into the next month when the month is short" do
      # October 2027 has only four Mondays, so the "5th monday in October"
      # (an NZ-MBH anniversary) overflows to 1 November.
      {:ok, rule} = Compiler.compile("5th monday in October")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2027")
      assert Tempo.Interval.from(interval) == ~o"2027Y11M1D"

      # A "last" weekday cannot overflow — it simply does not occur past its month.
      {:ok, last} = Compiler.compile("last monday in May")
      assert {:ok, [may]} = Rule.materialise(last, ~o"2026")
      assert Tempo.Interval.from(may) == ~o"2026Y5M25D"
    end

    test "a date-precise `prior to` gates by the occurrence date, not just the year" do
      # Norfolk Island's holiday moved on 2022-09-09; the prior-to window keeps
      # the June occurrence in 2022 (before the cutoff) but not in 2023.
      {:ok, rule} = Compiler.compile("Monday after 2nd saturday in June prior to 2022-09-09")

      assert rule.active == [{nil, ~D[2022-09-09]}]
      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2022")
      assert Tempo.Interval.from(interval) == ~o"2022Y6M13D"
      assert {:ok, []} = Rule.materialise(rule, ~o"2023")
    end

    test "the 'and' chaining a since-condition to a bare if is a shift, not an add" do
      # `since 2022 and if sunday …` chains the year condition to a bare `if`
      # (move), unlike the additive `and if`. 28 April 2024 is a Sunday.
      {:ok, chained} = Compiler.compile("04-28 since 2022 and if sunday then next monday")
      assert chained.substitute == [{[7], :next, 1, :shift}]
      assert {:ok, [interval]} = Rule.materialise(chained, ~o"2024")
      assert Tempo.Interval.from(interval) == ~o"2024Y4M29D"

      # A genuine additive `and if` still keeps the original and adds the observed.
      {:ok, additive} = Compiler.compile("03-02 and if sunday then next monday")
      assert additive.substitute == [{[7], :next, 1, :add}]
    end

    test "clause modes are per-clause: a shift clause then an additive one" do
      # Tonga: the bare `if …` moves the holiday; the later `and if …` adds.
      {:ok, rule} =
        Compiler.compile(
          "06-04 if thursday,friday,saturday,sunday then next monday and if tuesday then previous monday"
        )

      assert rule.substitute == [
               {[4, 5, 6, 7], :next, 1, :shift},
               {[2], :previous, 1, :add}
             ]

      # 4 June 2028 is a Sunday: the shift clause fires and moves it to Monday
      # the 5th, dropping the 4th (not an add).
      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2028")
      assert Tempo.Interval.from(interval) == ~o"2028Y6M5D"
    end
  end

  describe "year-boundary substitution" do
    test "an observed date crossing the year boundary is attributed to its own year" do
      # US New Year: 1 Jan observed the previous Friday when it is a Saturday.
      {:ok, rule} =
        Compiler.compile("01-01 and if saturday then previous friday if sunday then next monday")

      # 1 Jan 2028 is a Saturday; its observed 31 Dec 2027 belongs to 2027.
      {:ok, ivs_2027} = Rule.materialise(rule, ~o"2027")

      assert ivs_2027 |> Enum.map(&Tempo.Interval.from/1) |> MapSet.new() ==
               MapSet.new([~o"2027Y1M1D", ~o"2027Y12M31D"])

      # 2028 keeps only its own 1 January — the 31 Dec 2027 observance is not
      # attributed here.
      {:ok, ivs_2028} = Rule.materialise(rule, ~o"2028")
      assert Enum.map(ivs_2028, &Tempo.Interval.from/1) == [~o"2028Y1M1D"]
    end
  end

  describe "day_start projection (a day is just a day until projected)" do
    test "the default :midnight leaves the in-calendar day untouched" do
      eid = holiday_list("1 Shawwal", "Eid al-Fitr")
      interval = single_interval(eid, ~o"2025", :midnight)

      assert Tempo.Interval.from(interval) == ~o"1446Y10M1D[u-ca=islamic-umalqura]"
      # identical to passing no option at all
      {:ok, [{_holiday, plain}]} = Holidays.materialise(eid, ~o"2025")
      assert plain == interval
    end

    test "a zone-anchored evening begins at 18:00 the evening before" do
      # 1 Shawwal 1446 is 30 March 2025; its evening begins 18:00 the 29th.
      interval =
        single_interval(
          holiday_list("1 Shawwal", "Eid al-Fitr"),
          ~o"2025",
          {:evening, "Asia/Riyadh"}
        )

      # An exact structural comparison — no configured zone database needed to
      # read the named-zone value back.
      {:ok, expected} =
        DateTime.new(~D[2025-03-29], ~T[18:00:00], "Asia/Riyadh", Tz.TimeZoneDatabase)

      assert Tempo.Interval.from(interval) == Tempo.from_elixir(expected)
    end

    test "a canonical sunset projects to a datetime interval, sunset to sunset" do
      interval = single_interval(holiday_list("1 Shawwal", "Eid al-Fitr"), ~o"2025", :sunset)

      assert {:ok, from} = Tempo.to_elixir(Tempo.Interval.from(interval))
      assert {:ok, to} = Tempo.to_elixir(Tempo.Interval.to(interval))
      # sunset the evening before 1 Shawwal, through sunset the evening before 2 Shawwal
      assert DateTime.to_date(from) == ~D[2025-03-29]
      assert DateTime.to_date(to) == ~D[2025-03-30]
      assert from.time_zone == "Etc/UTC"
    end

    test "a location-anchored sunset resolves from coordinates alone (no tz_world)" do
      interval =
        single_interval(
          holiday_list("1 Shawwal", "Eid al-Fitr"),
          ~o"2025",
          {:sunset, {101.6869, 3.139}}
        )

      assert %Tempo.Interval{} = interval
      assert {:ok, from} = Tempo.to_elixir(Tempo.Interval.from(interval))
      assert DateTime.to_date(from) == ~D[2025-03-29]
    end

    test "an evening from a location falls back to the day when tz_world is unavailable" do
      # No tz_world backend runs in the suite, so the location's zone cannot be
      # resolved and the occurrence stays the in-calendar day rather than crashing.
      interval =
        single_interval(
          holiday_list("1 Shawwal", "Eid al-Fitr"),
          ~o"2025",
          {:evening, {101.6869, 3.139}}
        )

      assert Tempo.Interval.from(interval) == ~o"1446Y10M1D[u-ca=islamic-umalqura]"
    end

    test "a Gregorian-calendar holiday is untouched by day_start" do
      # Christmas is a civil-calendar day; sunset projection applies only to the
      # sunset-starting calendars (Islamic, Hebrew).
      interval = single_interval(holiday_list("12-25", "Christmas"), ~o"2025", :sunset)

      assert Tempo.Interval.from(interval) == ~o"2025Y12M25D"
    end
  end

  describe "Islamic day-count rollover (date-holidays encoding)" do
    test "a 30th day in a 29-day month rolls into the next month, labelled truly" do
      # date-holidays encodes Saudi Eid al-Fitr as "30 Ramadan P4D". When Ramadan
      # has 29 days (1436), the 30th day counting from its start is 1 Shawwal —
      # Eid itself — so the occurrence is labelled 1 Shawwal, not a fictional
      # "30 Ramadan", and it is no longer dropped.
      {:ok, rule} = Compiler.compile("30 Ramadan P4D")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2015")
      assert Tempo.Interval.from(interval) == ~o"1436Y10M1D[u-ca=islamic-umalqura]"
      assert gregorian_dates("30 Ramadan P4D", ~o"2015") == ["2015-07-17"]
    end

    test "30 Safar in a 29-day Safar rolls to 1 Rabi al-awwal" do
      # Iran encodes an end-of-Safar observance as "30 Safar"; Safar 1437 has 29
      # days, so it rolls to 1 Rabi al-awwal.
      {:ok, rule} = Compiler.compile("30 Safar")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2015")
      assert Tempo.Interval.from(interval) == ~o"1437Y3M1D[u-ca=islamic-umalqura]"
      assert gregorian_dates("30 Safar", ~o"2015") == ["2015-12-12"]
    end

    test "a valid day is unaffected — 1 Muharram is unchanged" do
      # The rollover path only moves out-of-range days; a valid day resolves
      # exactly as the direct in-calendar mapping did.
      {:ok, rule} = Compiler.compile("1 Muharram")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      assert Tempo.Interval.from(interval) == ~o"1447Y1M1D[u-ca=islamic-umalqura]"
    end
  end

  describe "Vietnamese lunisolar holidays" do
    test "Tết is the first day of the first lunar month" do
      # Vietnamese New Year 2025 is 29 January (a day before Chinese New Year's
      # 29th too, but the meridian can split them in other years).
      assert gregorian_dates("vietnamese 1-0-1", ~o"2025") == ["2025-01-29"]
    end

    test "a 12th-month holiday falls in the Gregorian year it lands in" do
      # Ông Táo (Kitchen Guardians, the 23rd of the 12th lunar month) belongs to
      # the Gregorian year it falls in — 22 January 2025, before Tết — not the
      # 12th month of the lunar year that begins in 2025.
      assert gregorian_dates("vietnamese 12-0-23", ~o"2025") == ["2025-01-22"]

      # Re-projects: a year later it is 10 February 2026.
      assert gregorian_dates("vietnamese 12-0-23", ~o"2026") == ["2026-02-10"]
    end

    test "a day-offset span starts before its anchor (Tết eve)" do
      # "1 day before vietnamese 1-0-1 P5D" is Tết eve, five days from the 28th.
      {:ok, rule} = Compiler.compile("1 day before vietnamese 1-0-1 P5D")

      assert {:ok, [interval]} = Rule.materialise(rule, ~o"2025")
      assert gregorian_dates("1 day before vietnamese 1-0-1 P5D", ~o"2025") == ["2025-01-28"]

      # The span runs five days — 28 January through 2 February (exclusive).
      {:ok, to} = Tempo.to_date(Tempo.Interval.to(interval))
      {:ok, to_iso} = Date.convert(to, Calendar.ISO)
      assert Date.to_iso8601(to_iso) == "2025-02-02"
    end
  end

  describe "inter-holiday conditionals (bridge / if-holiday)" do
    test "a bridge compiles to a :bridge conditional carrying its condition dates" do
      {:ok, rule} = Compiler.compile("09-22 if 09-21 and 09-23 is public holiday")

      assert rule.kind == :fixed
      assert {rule.month, rule.day} == {9, 22}
      assert rule.conditional == %{kind: :bridge, type: :public, on: [{9, 21}, {9, 23}]}
      assert Rule.conditional?(rule)
    end

    test "a bridge is kept only when every condition date is a holiday of the type" do
      {:ok, rule} = Compiler.compile("09-22 if 09-21 and 09-23 is public holiday")
      {:ok, base} = Rule.materialise(rule, ~o"2026")

      # Both flanks present — the day stays.
      assert {:ok, [kept]} =
               Rule.resolve_conditional(rule, base, ~o"2026", fn _days, _type -> true end)

      assert Tempo.Interval.from(kept) == ~o"2026Y9M22D"

      # A missing flank — the day is dropped.
      assert {:ok, []} =
               Rule.resolve_conditional(rule, base, ~o"2026", fn _days, _type -> false end)
    end

    test "Japan's Citizens' Holiday bridges 22 September only when 21 and 23 are holidays" do
      # 2026: Respect-for-the-Aged Day (the 21st, 3rd Monday) and the Autumnal
      # Equinox (the 23rd) flank the 22nd, so the Citizens' Holiday falls between
      # them — date-holidays' bridge.
      {:ok, holidays_2026} = Holidays.materialise(:JP, ~o"2026")
      assert ~o"2026Y9M22D" in dates_of(holidays_2026, "Citizens' Holiday")

      # 2025: Respect-for-the-Aged Day is the 15th, so the 22nd is not flanked
      # and the bridge does not occur.
      {:ok, holidays_2025} = Holidays.materialise(:JP, ~o"2025")
      assert dates_of(holidays_2025, "Citizens' Holiday") == []
    end

    test "an if-holiday move is extracted alongside earlier substitution clauses" do
      {:ok, rule} =
        Compiler.compile(
          "03-23 if Tuesday,Wednesday,Thursday then previous Monday if Friday,Saturday,Sunday then next Monday if is public holiday then next Monday"
        )

      # The two weekday-substitution clauses and the if-holiday move are each
      # extracted independently — the base is the bare fixed date.
      assert {rule.kind, rule.month, rule.day} == {:fixed, 3, 23}

      assert rule.substitute == [
               {[2, 3, 4], :previous, 1, :shift},
               {[5, 6, 7], :next, 1, :shift}
             ]

      assert rule.conditional ==
               %{
                 kind: :if_holiday,
                 type: :public,
                 move: %{count: 1, direction: :next, target: 1, omit: []}
               }
    end

    test "an if-holiday occurrence moves when it coincides and stays when it does not" do
      # A fixed 15 June (a Monday in 2026) with a "next monday" if-holiday move.
      {:ok, rule} = Compiler.compile("06-15 if is public holiday then next monday")
      {:ok, base} = Rule.materialise(rule, ~o"2026")
      assert Tempo.Interval.from(hd(base)) == ~o"2026Y6M15D"

      # Coincides with another public holiday — a Monday moving to "next monday"
      # steps a whole week, to the 22nd.
      assert {:ok, [moved]} =
               Rule.resolve_conditional(rule, base, ~o"2026", fn _days, _type -> true end)

      assert Tempo.Interval.from(moved) == ~o"2026Y6M22D"

      # No coincidence — the date is unchanged.
      assert {:ok, [same]} =
               Rule.resolve_conditional(rule, base, ~o"2026", fn _days, _type -> false end)

      assert Tempo.Interval.from(same) == ~o"2026Y6M15D"
    end

    test "a plain rule carries no conditional" do
      {:ok, plain} = Compiler.compile("12-25")
      refute Rule.conditional?(plain)
      assert plain.conditional == nil
    end
  end

  describe "locale and state resolution" do
    test "a locale with a subdivision loads the state's holidays" do
      {:ok, national} = Holidays.recurrences(:US)
      {:ok, california} = Holidays.recurrences(locale: "en-US-u-sd-usca")

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
