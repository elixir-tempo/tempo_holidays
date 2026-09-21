defmodule Tempo.Holidays.ConformanceTest do
  # Drives the compiler + materialiser to full agreement with date-holidays.
  # Each compiled rule's computed Gregorian dates must sit inside the fixture's
  # date-set for that country-year (see `Tempo.Holidays.Conformance`). The
  # target is zero unsupported and zero mismatched rules across the whole
  # corpus; while tiers are still being filled in, the assertions below record
  # the remaining gaps.
  #
  # `divergent` is a third bucket for *accepted* differences that are not
  # defects — currently the Islamic civil dates, where date-holidays uses a
  # fixed table with a 6pm/timezone day-start and Calendrical uses the
  # midnight-anchored Umm al-Qura. Those are excluded from `mismatched`.
  use ExUnit.Case, async: false

  alias Tempo.Holidays.{Conformance, Fixtures}

  @moduletag :conformance
  @moduletag timeout: 600_000

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
