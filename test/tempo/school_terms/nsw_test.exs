defmodule Tempo.Holidays.SchoolTerms.NSWTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Holidays.SchoolTerms.NSW
  alias Tempo.Interval
  alias Tempo.IntervalSet

  doctest NSW

  # The New South Wales Department of Education's published calendars, read
  # 2026-09-29 from education.nsw.gov.au: "Future and past NSW term dates and
  # school holidays" for 2016–2025 and 2027–2030, the 2026 page, and "School
  # development days". Each is the first and last day of a run, as published.

  # {year, Term 1 (Eastern), Term 1 (Western) first day, Term 2, Term 3, Term 4}.
  # Terms include their school development days.
  @terms [
    {2016, {"2016-01-27", "2016-04-08"}, "2016-02-03", {"2016-04-26", "2016-07-01"},
     {"2016-07-18", "2016-09-23"}, {"2016-10-10", "2016-12-20"}},
    {2017, {"2017-01-27", "2017-04-07"}, "2017-02-03", {"2017-04-24", "2017-06-30"},
     {"2017-07-17", "2017-09-22"}, {"2017-10-09", "2017-12-19"}},
    {2018, {"2018-01-29", "2018-04-13"}, "2018-02-05", {"2018-04-30", "2018-07-06"},
     {"2018-07-23", "2018-09-28"}, {"2018-10-15", "2018-12-21"}},
    {2019, {"2019-01-29", "2019-04-12"}, "2019-02-05", {"2019-04-29", "2019-07-05"},
     {"2019-07-22", "2019-09-27"}, {"2019-10-14", "2019-12-20"}},
    {2020, {"2020-01-28", "2020-04-09"}, "2020-02-04", {"2020-04-27", "2020-07-03"},
     {"2020-07-20", "2020-09-25"}, {"2020-10-12", "2020-12-18"}},
    {2021, {"2021-01-27", "2021-04-01"}, "2021-02-03", {"2021-04-19", "2021-06-25"},
     {"2021-07-12", "2021-09-17"}, {"2021-10-05", "2021-12-17"}},
    {2022, {"2022-01-28", "2022-04-08"}, "2022-02-04", {"2022-04-26", "2022-07-01"},
     {"2022-07-18", "2022-09-23"}, {"2022-10-10", "2022-12-20"}},
    {2023, {"2023-01-27", "2023-04-06"}, "2023-02-03", {"2023-04-24", "2023-06-30"},
     {"2023-07-17", "2023-09-22"}, {"2023-10-09", "2023-12-19"}},
    {2024, {"2024-01-30", "2024-04-12"}, "2024-02-06", {"2024-04-29", "2024-07-05"},
     {"2024-07-22", "2024-09-27"}, {"2024-10-14", "2024-12-20"}},
    {2025, {"2025-01-31", "2025-04-11"}, "2025-02-07", {"2025-04-28", "2025-07-04"},
     {"2025-07-21", "2025-09-26"}, {"2025-10-13", "2025-12-19"}},
    {2026, {"2026-01-27", "2026-04-02"}, "2026-02-03", {"2026-04-20", "2026-07-03"},
     {"2026-07-20", "2026-09-25"}, {"2026-10-12", "2026-12-17"}},
    {2027, {"2027-01-28", "2027-04-09"}, "2027-02-04", {"2027-04-27", "2027-07-02"},
     {"2027-07-19", "2027-09-24"}, {"2027-10-11", "2027-12-20"}},
    {2028, {"2028-01-31", "2028-04-07"}, "2028-02-07", {"2028-04-24", "2028-07-07"},
     {"2028-07-24", "2028-09-29"}, {"2028-10-16", "2028-12-21"}},
    {2029, {"2029-01-29", "2029-04-13"}, "2029-02-05", {"2029-04-30", "2029-07-06"},
     {"2029-07-23", "2029-09-28"}, {"2029-10-15", "2029-12-20"}},
    {2030, {"2030-01-31", "2030-04-12"}, "2030-02-07", {"2030-04-29", "2030-07-05"},
     {"2030-07-22", "2030-09-27"}, {"2030-10-14", "2030-12-19"}}
  ]

  # {year, Autumn, Winter, Spring, Summer (Eastern), Summer (Western)}. The
  # Department publishes each break's weekdays, and leaves a public holiday at
  # either end in or out as it pleases, so they are compared as the weekdays
  # that are not public holidays.
  @holidays [
    {2016, {"2016-04-11", "2016-04-22"}, {"2016-07-04", "2016-07-15"},
     {"2016-09-26", "2016-10-07"}, {"2016-12-21", "2017-01-26"}, {"2016-12-21", "2017-02-02"}},
    {2017, {"2017-04-10", "2017-04-21"}, {"2017-07-03", "2017-07-14"},
     {"2017-09-25", "2017-10-06"}, {"2017-12-20", "2018-01-26"}, {"2017-12-20", "2018-02-02"}},
    {2018, {"2018-04-16", "2018-04-27"}, {"2018-07-09", "2018-07-20"},
     {"2018-10-01", "2018-10-12"}, {"2018-12-24", "2019-01-28"}, {"2018-12-24", "2019-02-04"}},
    {2019, {"2019-04-15", "2019-04-26"}, {"2019-07-08", "2019-07-19"},
     {"2019-09-30", "2019-10-11"}, {"2019-12-23", "2020-01-27"}, {"2019-12-23", "2020-02-03"}},
    {2020, {"2020-04-13", "2020-04-24"}, {"2020-07-06", "2020-07-17"},
     {"2020-09-28", "2020-10-09"}, {"2020-12-21", "2021-01-26"}, {"2020-12-21", "2021-02-02"}},
    {2021, {"2021-04-05", "2021-04-16"}, {"2021-06-28", "2021-07-09"},
     {"2021-09-20", "2021-10-01"}, {"2021-12-20", "2022-01-27"}, {"2021-12-20", "2022-02-03"}},
    {2022, {"2022-04-11", "2022-04-22"}, {"2022-07-04", "2022-07-15"},
     {"2022-09-26", "2022-10-07"}, {"2022-12-21", "2023-01-26"}, {"2022-12-21", "2023-02-02"}},
    {2023, {"2023-04-11", "2023-04-21"}, {"2023-07-03", "2023-07-14"},
     {"2023-09-25", "2023-10-06"}, {"2023-12-20", "2024-01-29"}, {"2023-12-20", "2024-02-05"}},
    {2024, {"2024-04-15", "2024-04-26"}, {"2024-07-08", "2024-07-19"},
     {"2024-09-30", "2024-10-11"}, {"2024-12-23", "2025-01-30"}, {"2024-12-23", "2025-02-06"}},
    {2025, {"2025-04-14", "2025-04-24"}, {"2025-07-07", "2025-07-18"},
     {"2025-09-29", "2025-10-10"}, {"2025-12-22", "2026-01-26"}, {"2025-12-22", "2026-02-02"}},
    {2026, {"2026-04-07", "2026-04-17"}, {"2026-07-06", "2026-07-17"},
     {"2026-09-28", "2026-10-09"}, {"2026-12-18", "2027-01-27"}, {"2026-12-18", "2027-02-03"}},
    {2027, {"2027-04-12", "2027-04-23"}, {"2027-07-05", "2027-07-16"},
     {"2027-09-27", "2027-10-08"}, {"2027-12-21", "2028-01-28"}, {"2027-12-21", "2028-02-04"}},
    {2028, {"2028-04-10", "2028-04-21"}, {"2028-07-10", "2028-07-21"},
     {"2028-10-03", "2028-10-13"}, {"2028-12-22", "2029-01-25"}, {"2028-12-22", "2029-02-02"}},
    {2029, {"2029-04-16", "2029-04-27"}, {"2029-07-09", "2029-07-20"},
     {"2029-10-02", "2029-10-12"}, {"2029-12-21", "2030-01-30"}, {"2029-12-21", "2030-02-06"}},
    {2030, {"2030-04-15", "2030-04-26"}, {"2030-07-08", "2030-07-19"},
     {"2030-09-30", "2030-10-11"}, {"2030-12-20", "2031-01-27"}, {"2030-12-20", "2031-02-03"}}
  ]

  # {year, Term 1 (Eastern), Term 1 (Western), Term 2, Term 3, Term 4}: the runs
  # of school development days, each a run of school days.
  @development_days [
    {2023, {"2023-01-27", "2023-01-30"}, {"2023-02-03", "2023-02-06"},
     {"2023-04-24", "2023-04-24"}, {"2023-07-17", "2023-07-17"}, {"2023-12-18", "2023-12-19"}},
    {2024, {"2024-01-30", "2024-01-31"}, {"2024-02-06", "2024-02-07"},
     {"2024-04-29", "2024-04-29"}, {"2024-07-22", "2024-07-22"}, {"2024-12-19", "2024-12-20"}},
    {2025, {"2025-01-31", "2025-02-05"}, {"2025-02-07", "2025-02-12"},
     {"2025-04-28", "2025-04-29"}, {"2025-07-21", "2025-07-21"}, {"2025-10-13", "2025-10-13"}},
    {2026, {"2026-01-27", "2026-01-30"}, {"2026-02-03", "2026-02-06"},
     {"2026-04-20", "2026-04-21"}, {"2026-07-20", "2026-07-20"}, {"2026-10-12", "2026-10-12"}},
    {2027, {"2027-01-28", "2027-02-02"}, {"2027-02-04", "2027-02-09"},
     {"2027-04-27", "2027-04-28"}, {"2027-07-19", "2027-07-19"}, {"2027-10-11", "2027-10-11"}}
  ]

  # date-holidays gives New South Wales an additional public holiday for a
  # Saturday Anzac Day before 2026, Monday 27 April 2020, which the 2020
  # calendar did not have: Term 2 started that Monday. Until the data is
  # corrected, the rules start it on the Tuesday.
  @upstream_errors %{{2020, 2} => {"2020-04-27", "2020-04-28"}}

  # The 2030 calendar ends the summer holidays on Monday 27 January 2031, as
  # though Term 1 of 2031 will start after Australia Day. The rules, for which
  # 2031 is a projection, start it six weeks after Term 4 of 2030, on Thursday
  # 30 January, with 199 school days, so the summer holidays run two school
  # days longer than the 2030 calendar shows until 2031's is published.
  @projected_days %{
    {2030, :eastern} => ["2031Y1M28D/29D", "2031Y1M29D/30D"],
    {2030, :western} => ["2031Y2M4D/5D", "2031Y2M5D/6D"]
  }

  defp school_days do
    {:ok, public_holidays} = Tempo.Holidays.holidays(:AU, subdivision: "NSW", include: :public)
    Tempo.workdays(:AU, except: public_holidays)
  end

  defp day(iso), do: Tempo.from_iso8601!(iso)

  defp run({first, last}), do: Interval.new!(from: day(first), through: day(last))

  # A term, as its first and last days in ISO 8601.
  defp first_and_last(%Interval{} = term) do
    last_day = term |> Interval.to() |> Tempo.shift(~o"-P1D")
    {Tempo.to_iso8601!(Interval.from(term)), Tempo.to_iso8601!(last_day)}
  end

  defp first_and_last({first, last}),
    do: {Tempo.to_iso8601!(day(first)), Tempo.to_iso8601!(day(last))}

  # A published term as the rules give it, a known upstream error aside.
  defp as_generated(year, number, {first, last}) do
    case Map.fetch(@upstream_errors, {year, number}) do
      {:ok, {^first, generated_first}} -> {generated_first, last}
      :error -> {first, last}
    end
  end

  defp school_days_in(span, school_days) do
    {:ok, days} = Tempo.select(span, school_days)
    days(days)
  end

  defp days(set), do: set |> IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!/1)

  defp summer_days(year, division, summer, school_days),
    do: school_days_in(run(summer), school_days) ++ Map.get(@projected_days, {year, division}, [])

  describe "terms/2" do
    test "gives every term the Department has published, 2016–2030" do
      for {year, term_1, western_start, term_2, term_3, term_4} <- @terms do
        {:ok, eastern} = NSW.terms(year)
        {:ok, western} = NSW.terms(year, division: :western)

        published =
          for {run, number} <- Enum.with_index([term_1, term_2, term_3, term_4], 1),
              do: first_and_last(as_generated(year, number, run))

        assert eastern |> IntervalSet.members() |> Enum.map(&first_and_last/1) == published,
               "#{year}"

        assert western |> IntervalSet.first() |> first_and_last() ==
                 first_and_last({western_start, elem(term_1, 1)}),
               "#{year} Western"
      end
    end

    test "tags each term with its number" do
      {:ok, terms} = NSW.terms(~o"2027")

      assert terms |> IntervalSet.members() |> Enum.map(&Tempo.metadata(&1).term) == [1, 2, 3, 4]
    end
  end

  describe "holidays/2" do
    test "are the breaks the Department has published, 2016–2030" do
      school_days = school_days()

      for {year, autumn, winter, spring, summer, western_summer} <- @holidays do
        {:ok, eastern} = NSW.holidays(year)
        {:ok, western} = NSW.holidays(year, division: :western)

        published_breaks =
          Enum.map([autumn, winter, spring], &school_days_in(run(&1), school_days))

        assert Enum.map(IntervalSet.members(eastern), &school_days_in(&1, school_days)) ==
                 published_breaks ++ [summer_days(year, :eastern, summer, school_days)],
               "#{year}"

        assert western |> IntervalSet.members() |> List.last() |> school_days_in(school_days) ==
                 summer_days(year, :western, western_summer, school_days),
               "#{year} Western"
      end
    end

    test "are tagged with their season, and the summer holidays run into the next year" do
      {:ok, holidays} = NSW.holidays(2026)

      assert holidays |> IntervalSet.members() |> Enum.map(&Tempo.metadata(&1).holiday) ==
               [:autumn, :winter, :spring, :summer]

      assert holidays |> IntervalSet.members() |> List.last() |> Tempo.to_iso8601!() ==
               "2026Y12M18D/2027Y1M28D"
    end
  end

  describe "development_days/2" do
    test "are the days the Department has published, 2023–2027" do
      school_days = school_days()

      for {year, term_1, western_term_1, term_2, term_3, term_4} <- @development_days do
        {:ok, eastern} = NSW.development_days(year)
        {:ok, western} = NSW.development_days(year, division: :western)

        assert days(eastern) ==
                 Enum.flat_map(
                   [term_1, term_2, term_3, term_4],
                   &school_days_in(run(&1), school_days)
                 ),
               "#{year}"

        assert days(western) ==
                 Enum.flat_map(
                   [western_term_1, term_2, term_3, term_4],
                   &school_days_in(run(&1), school_days)
                 ),
               "#{year} Western"
      end
    end

    test "are tagged with their term's number" do
      {:ok, days} = NSW.development_days(2024)

      assert days |> IntervalSet.members() |> Enum.map(&Tempo.metadata(&1).term) ==
               [1, 1, 2, 3, 4, 4]
    end
  end

  describe "the rules' thinnest fits" do
    test "the 199-day threshold: 2027 keeps the six-week start with 199, 2029 would have 198" do
      school_days = school_days()
      {:ok, terms_2027} = NSW.terms(2027)
      assert Tempo.count_workdays(terms_2027, school_days) == 199

      # Six weeks after Term 4 of 2028 ended is Thursday 1 February 2029, which
      # would leave the year 198 school days: Term 1 starts after Australia Day.
      {:ok, terms_2029} = NSW.terms(2029)
      [term_1 | later_terms] = IntervalSet.members(terms_2029)
      six_weeks_start = Interval.new!(from: ~o"2029-02-01", to: Interval.to(term_1))

      {:ok, six_weeks_year} = IntervalSet.new([six_weeks_start | later_terms])
      assert Tempo.count_workdays(six_weeks_year, school_days) == 198
      assert Interval.from(term_1) == ~o"2029Y1M29D"
    end

    test "the Term 4 fallback from 2026: 2027's Thursday is the 23rd, so Term 4 ends on the Monday" do
      {:ok, terms} = NSW.terms(2027)

      assert terms |> IntervalSet.members() |> List.last() |> first_and_last() ==
               {"2027Y10M11D", "2027Y12M20D"}
    end
  end

  describe "input that is not a school year or an option" do
    test "is an error, not a raise" do
      for year <- [2015, ~o"2015", nil, "2027", :"", 2027.0, ~o"2027-06", ~o"T09"] do
        assert {:error, {:invalid_year, _year}} = NSW.terms(year)
        assert {:error, {:invalid_year, _year}} = NSW.holidays(year)
        assert {:error, {:invalid_year, _year}} = NSW.development_days(year)
      end

      assert NSW.terms(2027, division: :northern) == {:error, {:invalid_division, :northern}}
      assert {:error, {:invalid_option, _options}} = NSW.terms(2027, divison: :western)
      assert {:error, {:invalid_option, _options}} = NSW.terms(2027, :western)
      assert NSW.development_days(2022) == {:error, {:unpublished_development_days, 2022}}
    end
  end
end
