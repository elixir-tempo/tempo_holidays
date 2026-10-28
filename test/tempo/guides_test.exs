defmodule Tempo.Holidays.GuidesTest do
  # The examples of the README and the guides, run as they are written.
  use ExUnit.Case, async: true

  doctest_file("README.md")
  doctest_file("guides/user-guide.md")
end
