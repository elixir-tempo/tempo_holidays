defmodule Tempo.Holidays.LocaleTest do
  use ExUnit.Case, async: true

  alias Tempo.Holidays.Locale

  doctest Locale

  test "a LanguageTag struct resolves to its territory and subdivision" do
    {:ok, tag} = Localize.validate_locale("en-US-u-sd-usca")
    assert {:ok, %{territory: "US", division: "CA", subdivision: nil}} = Locale.resolve(tag)
  end

  test "a region override (u-rg) wins over the language's territory" do
    assert {:ok, %{territory: "GB"}} = Locale.resolve("en-US-u-rg-gbzzzz")
  end

  test "options override the derived levels" do
    assert {:ok, %{territory: "US", division: "NY"}} =
             Locale.resolve("en-US-u-sd-usca", division: "NY")

    assert {:ok, %{territory: "GB", subdivision: "LA"}} =
             Locale.resolve("en-GB", subdivision: "LA")
  end

  test "an invalid, non-territory input is an invalid locale" do
    assert {:error, {:invalid_locale, 123}} = Locale.resolve(123)
    assert {:error, {:invalid_locale, %{}}} = Locale.resolve(%{})
  end
end
