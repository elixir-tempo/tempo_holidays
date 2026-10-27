defmodule Tempo.Holidays.ConformanceTest do
  # Holds `Tempo.Holidays.holidays/2` to date-holidays' own output: for each
  # territory and year of its fixtures, the days our occurrences of each rule
  # start on must hold the fixture's dates for that rule and lie among the
  # fixture's dates that year (see `Tempo.Holidays.Conformance`). The gate is
  # zero unsupported and zero mismatched rules across the whole corpus.
  #
  # Two buckets hold *accepted* non-defects, excluded from the gate:
  #
  #   * `divergent` — the Islamic civil dates, where date-holidays uses a fixed
  #     table with a 6pm/timezone day-start and Calendrical uses the
  #     midnight-anchored Umm al-Qura; a rule a region's data removes with
  #     `false` which its fixture lists all the same (Timaru, Buller: their
  #     fixtures give the state's holidays, not the region's); and a fixture
  #     for a subdivision the data does not define (Mauritius' districts),
  #     generated from an older release. Excluded from `mismatched`.
  #
  #   * `known_unsupported` — rules `Tempo.DateRule` does not read: the Bengali
  #     (revised) calendar, which needs a Calendrical calendar first. Excluded
  #     from `unsupported`. See `Conformance.accepted_unsupported?/1`.
  use ExUnit.Case, async: false

  alias Tempo.Holidays.{Conformance, Fixtures}

  @moduletag :conformance
  # The full corpus is ~171k rule-checks and runs for minutes; this is an
  # opt-in exhaustive test, so let it run to completion.
  @moduletag timeout: :infinity

  test "our computed dates match date-holidays across the full corpus" do
    stats = Conformance.run(Fixtures.all())
    IO.puts("\n" <> Conformance.summary(stats))

    unsupported = stats.unsupported |> Map.values() |> Enum.sum()
    mismatched = stats.mismatched |> Map.values() |> Enum.sum()

    assert mismatched == 0,
           "#{mismatched} rules compute the wrong dates: #{inspect(stats.mismatched)}"

    assert unsupported == 0,
           "#{unsupported} rules are not yet supported: #{inspect(stats.unsupported)}"
  end
end
