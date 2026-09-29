defmodule Tempo.Holidays.SchoolTerms.NSW do
  @moduledoc """
  New South Wales public school terms, school holidays and school
  development days, from the rules the Department of Education's calendars
  follow.

  The Department publishes each year's calendar a few years ahead, and
  publishes it as dates, not rules. These rules reproduce every calendar it
  has published, 2016 to 2030, in both divisions, and project the years after:

  * **Term 1 ends before Easter or in the week of 7–13 April** — on the day
    before Good Friday when Good Friday falls 31 March–13 April, so Easter
    opens the autumn holidays, and otherwise on the Friday that falls 7–13
    April.

  * **The autumn, winter and spring holidays are two weeks** — each runs from
    the Monday after a term's last day, and the next term starts on the Monday
    two weeks later, or on the next school day when that Monday is a public
    holiday.

  * **Term 3 is ten weeks** — Monday of its first week to Friday of its tenth.

  * **Term 2 runs to Term 3** — up to 2025 Term 2 is ten weeks. From 2026 Term 3
    starts on the Monday on or after 18 July, so Term 2 is ten weeks or eleven.

  * **Term 4 ends in the week before Christmas** — up to 2025 on the Friday that
    falls 17–23 December, or on that week's Tuesday when the Friday is the 22nd
    or 23rd; from 2026 on the Thursday that falls 17–23 December, or on that
    week's Monday when the Thursday is the 22nd or 23rd.

  * **Term 1 starts after Australia Day** — up to 2021 on the school day after
    Australia Day; from 2022 six weeks after the previous Term 4 ended, on the
    same weekday, unless the year would then have fewer than 199 school days,
    when it starts on the school day after Australia Day.

  * **The Western division starts a week later** — its Term 1 starts seven days
    after the Eastern division's.

  A school day is a weekday that is not one of New South Wales' public holidays,
  as `Tempo.Holidays.holidays/2` gives them, and school development days are
  school days. `terms/2`, `holidays/2` and `development_days/2` return interval
  sets, so they compose with the rest of Tempo.

  ## Example

      {:ok, terms} = NSW.terms(~o"2027")
      {:ok, holidays} = NSW.holidays(~o"2027")
      {:ok, next_holidays} = Tempo.members_overlapping(holidays, ~o"2027-07")

  > *"The NSW school **terms** of 2027, the **holidays** between them, and the
  > holidays that fall in July."*

  """

  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet

  @typedoc """
  A school division: `:eastern`, most of the state, or `:western`, the schools
  in the far west, whose Term 1 starts a week later.
  """
  @type division :: :eastern | :western

  @typedoc "A school year: a year from 2016, as an integer or a Tempo value naming it."
  @type year :: pos_integer() | Tempo.t()

  # The first year the rules were checked against a published calendar.
  @first_year 2016

  # The rules' dates, as ISO 8601-2 selections that `Tempo.on/2` places on a
  # year.
  @australia_day ~o"1M26D"
  @good_friday ~o"LLL(easter)eN/P-3DN5K1IN"
  @march_31_to_april_13 ~o"3M31D/4M14D"
  @friday_7_to_13_april ~o"LLL4M7DN/P7DN5K1IN"
  @monday_on_or_after_18_july ~o"LLL7M18DN/P7DN1K1IN"
  @friday_17_to_23_december ~o"LLL12M17DN/P7DN5K1IN"
  @thursday_17_to_23_december ~o"LLL12M17DN/P7DN4K1IN"
  @december_22_or_23 ~o"12M22D/12M24D"

  @monday ~o"1K"
  @tuesday ~o"2K"

  @holidays [:autumn, :winter, :spring, :summer]

  @doc """
  Returns a year's four school terms.

  Each term runs from its first day to its last, school development days
  included, and is tagged with its number: `%{term: 1}` to `%{term: 4}`.

  ### Arguments

  * `year` is a year from 2016, the first the rules were checked against: an
    integer or a `t:Tempo.t/0` naming the year, `~o"2027"`.

  ### Options

  * `:division` is `:eastern`, the default, or `:western` for the schools in the
    far west, whose Term 1 starts a week later.

  ### Returns

  * `{:ok, terms}`, a `t:Tempo.IntervalSet.t/0` of the four terms.

  * `{:error, reason}` — `{:invalid_year, year}`, `{:invalid_division, division}`
    or `{:invalid_option, options}`.

  ### Examples

      iex> {:ok, terms} = Tempo.Holidays.SchoolTerms.NSW.terms(~o"2027")
      iex> terms |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!/1)
      ["2027Y1M28D/4M10D", "2027Y4M27D/7M3D", "2027Y7M19D/9M25D", "2027Y10M11D/12M21D"]

      iex> {:ok, terms} = Tempo.Holidays.SchoolTerms.NSW.terms(2027, division: :western)
      iex> terms |> Tempo.IntervalSet.first() |> Tempo.to_iso8601!()
      "2027Y2M4D/4M10D"

  """
  @spec terms(year(), keyword()) :: {:ok, IntervalSet.t()} | {:error, {atom(), term()}}
  def terms(year, options \\ []) do
    with {:ok, year} <- school_year(year),
         {:ok, division} <- division(options),
         {:ok, school_days} <- school_days() do
      year_terms(year, division, school_days)
    end
  end

  @doc """
  Returns a year's four school holidays.

  The holidays are the days between the terms: the autumn, winter and spring
  holidays after Terms 1, 2 and 3, and the summer holidays after Term 4, which
  run into the next year until its Term 1 starts. Each holiday takes in the
  weekends either side, and is tagged `%{holiday: :autumn}`, `:winter`,
  `:spring` or `:summer`.

  ### Arguments

  * `year` is a year from 2016, as for `terms/2`.

  ### Options

  * `:division` is `:eastern` or `:western`, as for `terms/2`: the Western
    division's summer holidays run a week longer.

  ### Returns

  * `{:ok, holidays}`, a `t:Tempo.IntervalSet.t/0` of the four holidays.

  * `{:error, reason}` as for `terms/2`.

  ### Examples

      iex> {:ok, holidays} = Tempo.Holidays.SchoolTerms.NSW.holidays(~o"2027")
      iex> holidays |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!/1)
      ["2027Y4M10D/27D", "2027Y7M3D/19D", "2027Y9M25D/10M11D", "2027Y12M21D/2028Y1M31D"]

  """
  @spec holidays(year(), keyword()) :: {:ok, IntervalSet.t()} | {:error, {atom(), term()}}
  def holidays(year, options \\ []) do
    with {:ok, year} <- school_year(year),
         {:ok, division} <- division(options),
         {:ok, school_days} <- school_days(),
         {:ok, terms} <- year_terms(year, division, school_days),
         {:ok, next_terms} <- year_terms(year + 1, division, school_days),
         {:ok, school_year} <- Interval.new(from: first_day(terms), to: first_day(next_terms)),
         {:ok, between_terms} <- Tempo.difference(school_year, terms) do
      between_terms
      |> IntervalSet.members()
      |> Enum.zip_with(@holidays, &Tempo.put_metadata(&1, %{holiday: &2}))
      |> IntervalSet.new()
    end
  end

  @doc """
  Returns a year's school development days.

  Staff attend on a school development day and students do not. The Department
  has published them since 2023: the first two school days of Term 1, the first
  of Terms 2 and 3, and the last two of Term 4 in 2023 and 2024; from 2025 the
  first four school days of Term 1, the first two of Term 2, and the first of
  Terms 3 and 4. Each day is tagged with its term's number.

  ### Arguments

  * `year` is a year from 2023, as an integer or a `t:Tempo.t/0` naming it.

  ### Options

  * `:division` is `:eastern` or `:western`, as for `terms/2`: the Western
    division's Term 1 development days are the first days of its own Term 1.

  ### Returns

  * `{:ok, development_days}`, a `t:Tempo.IntervalSet.t/0` of the days.

  * `{:error, reason}` as for `terms/2`, or `{:unpublished_development_days,
    year}` for a year before 2023.

  ### Examples

      iex> {:ok, days} = Tempo.Holidays.SchoolTerms.NSW.development_days(~o"2027")
      iex> days |> Tempo.IntervalSet.members() |> Enum.map(&Tempo.to_iso8601!/1)
      ["2027Y1M28D/29D", "2027Y1M29D/30D", "2027Y2M1D/2D", "2027Y2M2D/3D",
       "2027Y4M27D/28D", "2027Y4M28D/29D", "2027Y7M19D/20D", "2027Y10M11D/12D"]

  """
  @spec development_days(year(), keyword()) ::
          {:ok, IntervalSet.t()} | {:error, {atom(), term()}}
  def development_days(year, options \\ []) do
    with {:ok, year} <- school_year(year),
         {:ok, division} <- division(options),
         {:ok, pattern} <- development_day_pattern(year),
         {:ok, school_days} <- school_days(),
         {:ok, terms} <- year_terms(year, division, school_days),
         {:ok, days_of_school} <- Tempo.select(terms, school_days) do
      days_of_school
      |> IntervalSet.members()
      |> Enum.chunk_by(&Tempo.metadata(&1).term)
      |> Enum.zip_with(pattern, &at_the/2)
      |> Enum.concat()
      |> IntervalSet.new()
    end
  end

  # School development days, published from 2023: in each term, how many of its
  # first or last school days.
  defp development_day_pattern(year) when year in 2023..2024,
    do: {:ok, [first: 2, first: 1, first: 1, last: 2]}

  defp development_day_pattern(year) when year >= 2025,
    do: {:ok, [first: 4, first: 2, first: 1, first: 1]}

  defp development_day_pattern(year), do: {:error, {:unpublished_development_days, year}}

  defp at_the(term_days, {:first, count}), do: Enum.take(term_days, count)
  defp at_the(term_days, {:last, count}), do: Enum.take(term_days, -count)

  # A year's terms, from its rules. They run in the order that leaves each
  # one's inputs known: Easter places Term 1's end, the holidays and Term 3
  # follow, December places Term 4's end, and Term 1's start comes last,
  # because the six-week rule counts the whole year's school days.
  defp year_terms(year, division, school_days) do
    with %Tempo{} = term_1_end <- term_1_end(year),
         %Tempo{} = term_2_start <- after_the_holidays(term_1_end, school_days),
         {:ok, {term_2_end, term_3_start}} <- terms_2_and_3(year, term_2_start, school_days),
         %Tempo{} = term_3_end <- ten_weeks_on(term_3_start),
         %Tempo{} = term_4_start <- after_the_holidays(term_3_end, school_days),
         %Tempo{} = term_4_end <- term_4_end(year),
         {:ok, term_2} <- term(2, term_2_start, term_2_end),
         {:ok, term_3} <- term(3, term_3_start, term_3_end),
         {:ok, term_4} <- term(4, term_4_start, term_4_end),
         %Tempo{} = term_1_start <-
           term_1_start(year, term_1_end, [term_2, term_3, term_4], school_days),
         {:ok, term_1} <- term(1, in_division(term_1_start, division), term_1_end) do
      IntervalSet.new([term_1, term_2, term_3, term_4])
    else
      {:error, _reason} = error -> error
      not_a_day -> {:error, {:not_a_day, not_a_day}}
    end
  end

  # Term 1 ends before Easter or in the week of 7–13 April: on the day before
  # Good Friday when Good Friday falls 31 March–13 April, so Easter opens the
  # autumn holidays, and otherwise on the Friday that falls 7–13 April.
  defp term_1_end(year) do
    with %Tempo{} = good_friday <- day_in(year, @good_friday),
         {:ok, fortnight} <- placed(@march_31_to_april_13, year) do
      if Tempo.within?(good_friday, fortnight),
        do: Tempo.shift(good_friday, ~o"-P1D"),
        else: day_in(year, @friday_7_to_13_april)
    end
  end

  # The autumn, winter and spring holidays are two weeks: each runs from the
  # Monday after a term's last day, and the next term starts on the Monday two
  # weeks later, or on the next school day when that Monday is a public holiday.
  defp after_the_holidays(last_day, school_days) do
    holidays_start = Tempo.shift(Tempo.trunc(last_day, :week), ~o"P1W")
    two_weeks_later = Tempo.shift(holidays_start, ~o"P2W")

    if Tempo.workday?(two_weeks_later, school_days),
      do: two_weeks_later,
      else: Tempo.next_workday(two_weeks_later, school_days)
  end

  # Term 2 runs to Term 3. Up to 2025 Term 2 is ten weeks, and Term 3 starts
  # after the winter holidays that follow it.
  defp terms_2_and_3(year, term_2_start, school_days) when year <= 2025 do
    with %Tempo{} = term_2_end <- ten_weeks_on(term_2_start),
         %Tempo{} = term_3_start <- after_the_holidays(term_2_end, school_days),
         do: {:ok, {term_2_end, term_3_start}}
  end

  # From 2026 Term 3 starts on the Monday on or after 18 July, and Term 2 ends
  # on the school day before the winter holidays, the two weeks before it.
  defp terms_2_and_3(year, _term_2_start, school_days) do
    with %Tempo{} = term_3_start <- day_in(year, @monday_on_or_after_18_july),
         winter_holidays_start = Tempo.shift(term_3_start, ~o"-P2W"),
         %Tempo{} = term_2_end <- Tempo.previous_workday(winter_holidays_start, school_days),
         do: {:ok, {term_2_end, term_3_start}}
  end

  # A ten-week term runs from the Monday of its first week to the Friday of its
  # tenth: its last day is the last weekday before the Monday ten weeks on.
  defp ten_weeks_on(first_day) do
    first_day
    |> Tempo.trunc(:week)
    |> Tempo.shift(~o"P10W")
    |> Tempo.previous_workday(:AU)
  end

  # Term 4 ends in the week before Christmas. Up to 2025 it ends on the Friday
  # that falls 17–23 December, or on that week's Tuesday when the Friday is the
  # 22nd or 23rd.
  defp term_4_end(year) when year <= 2025,
    do: last_day_before_christmas(year, @friday_17_to_23_december, @tuesday)

  # From 2026 it ends on the Thursday that falls 17–23 December, or on that
  # week's Monday when the Thursday is the 22nd or 23rd.
  defp term_4_end(year),
    do: last_day_before_christmas(year, @thursday_17_to_23_december, @monday)

  defp last_day_before_christmas(year, last_day, earlier_day) do
    with %Tempo{} = day <- day_in(year, last_day),
         {:ok, too_close} <- placed(@december_22_or_23, year) do
      if Tempo.within?(day, too_close), do: that_weeks(earlier_day, day), else: day
    end
  end

  # Term 1 starts after Australia Day. Up to 2021 it starts on the school day
  # after Australia Day.
  defp term_1_start(year, _term_1_end, _later_terms, school_days) when year <= 2021,
    do: school_day_after(@australia_day, year, school_days)

  # From 2022 it starts six weeks after the previous Term 4 ended, on the same
  # weekday, unless the year would then have fewer than 199 school days, when it
  # starts on the school day after Australia Day.
  defp term_1_start(year, term_1_end, later_terms, school_days) do
    with %Tempo{} = last_term_4_end <- term_4_end(year - 1),
         six_weeks_later = Tempo.shift(last_term_4_end, ~o"P6W"),
         {:ok, term_1} <- term(1, six_weeks_later, term_1_end),
         {:ok, terms} <- IntervalSet.new([term_1 | later_terms]),
         {:ok, days_of_school} <- Tempo.select(terms, school_days) do
      if Tempo.at_least?(days_of_school, ~o"P199D"),
        do: six_weeks_later,
        else: school_day_after(@australia_day, year, school_days)
    end
  end

  # The Western division starts a week later: its Term 1 starts seven days
  # after the Eastern division's.
  defp in_division(term_1_start, :eastern), do: term_1_start
  defp in_division(term_1_start, :western), do: Tempo.shift(term_1_start, ~o"P1W")

  defp term(number, first_day, last_day),
    do: Interval.new(from: first_day, through: last_day, metadata: %{term: number})

  # A school day is a weekday that is not a New South Wales public holiday.
  defp school_days do
    with {:ok, public_holidays} <-
           Tempo.Holidays.holidays(:AU, subdivision: "NSW", include: :public),
         do: {:ok, Tempo.workdays(:AU, except: public_holidays)}
  end

  defp school_day_after(rule, year, school_days) do
    with %Tempo{} = day <- day_in(year, rule), do: Tempo.next_workday(day, school_days)
  end

  # The given weekday of the week a day falls in: that week's Tuesday.
  defp that_weeks(weekday, day) do
    with {:ok, week} <- Interval.new(from: Tempo.trunc(day, :week), duration: ~o"P1W"),
         {:ok, days} <- Tempo.select(week, weekday),
         do: first_day(days)
  end

  # The day a rule names in a year: the Friday that falls 7–13 April 2027 is
  # 9 April.
  defp day_in(year, rule) do
    with {:ok, rule_in_year} <- placed(rule, year), do: Interval.from(rule_in_year)
  end

  defp placed(rule, year) do
    with {:ok, year} <- Tempo.new(year: year), do: Tempo.on(rule, year)
  end

  defp first_day(set), do: set |> IntervalSet.first() |> Interval.from()

  defp school_year(year) when is_integer(year) and year >= @first_year, do: {:ok, year}

  defp school_year(%Tempo{} = value) do
    case Tempo.resolution(value) do
      {:year, 1} -> value |> Tempo.year() |> school_year()
      _not_a_year -> {:error, {:invalid_year, value}}
    end
  end

  defp school_year(year), do: {:error, {:invalid_year, year}}

  defp division(options) do
    with true <- Keyword.keyword?(options),
         {:ok, [division: division]} <- Keyword.validate(options, division: :eastern) do
      if division in [:eastern, :western],
        do: {:ok, division},
        else: {:error, {:invalid_division, division}}
    else
      _invalid -> {:error, {:invalid_option, options}}
    end
  end
end
