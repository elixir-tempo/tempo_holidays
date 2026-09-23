defmodule Tempo.Holidays.ConformanceTest do
  # Drives the compiler + materialiser to full agreement with date-holidays.
  # Each compiled rule's computed Gregorian dates must sit inside the fixture's
  # date-set for that country-year (see `Tempo.Holidays.Conformance`). The gate
  # is zero unsupported and zero mismatched rules across the whole corpus.
  #
  # Two buckets hold *accepted* non-defects, excluded from the gate:
  #
  #   * `divergent` — the Islamic civil dates, where date-holidays uses a fixed
  #     table with a 6pm/timezone day-start and Calendrical uses the
  #     midnight-anchored Umm al-Qura. Excluded from `mismatched`.
  #
  #   * `known_unsupported` — rules we knowingly do not compile yet: the Bengali
  #     (revised) calendar, which needs a Calendrical calendar first, and two
  #     rare/expired compound shapes. Deferred follow-ups; excluded from
  #     `unsupported`. See `Conformance.accepted_unsupported?/1`.
  use ExUnit.Case, async: false

  alias Tempo.Holidays.{Conformance, Fixtures}

  @moduletag :conformance
  # The full corpus is ~168k rule-checks and runs for tens of minutes; this is
  # an opt-in exhaustive test, so let it run to completion.
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
