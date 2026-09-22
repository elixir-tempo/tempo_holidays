defmodule Tempo.Holidays.LocaleTest do
  use ExUnit.Case, async: true

  alias Tempo.Holidays.Locale

  doctest Locale

  test "a LanguageTag struct resolves to its territory and subdivision" do
    {:ok, tag} = Localize.validate_locale("en-US-u-sd-usca")
    assert {:ok, %{territory: "US", division: "CA", subdivision: nil}} = Locale.resolve(tag)
  end

  test "a :locale region override (u-rg) wins over the language's territory" do
    assert {:ok, %{territory: "GB"}} = Locale.resolve(nil, locale: "en-US-u-rg-gbzzzz")
  end

  test "a positional territory is a territory, never a language (:SA is Saudi Arabia)" do
    assert {:ok, %{territory: "SA"}} = Locale.resolve(:SA)
    assert {:ok, %{territory: "AU"}} = Locale.resolve("au")
  end

  test "the :territory option is validated" do
    assert {:ok, %{territory: "SA"}} = Locale.resolve(nil, territory: :SA)
    assert {:error, {:unknown_territory, "en-US"}} = Locale.resolve(nil, territory: "en-US")
  end

  test "options override the derived levels" do
    assert {:ok, %{territory: "US", division: "NY"}} =
             Locale.resolve(nil, locale: "en-US-u-sd-usca", division: "NY")

    assert {:ok, %{territory: "GB", subdivision: "LA"}} =
             Locale.resolve(nil, locale: "en-GB", subdivision: "LA")
  end

  test "an invalid, non-territory input is an invalid locale" do
    assert {:error, {:invalid_locale, 123}} = Locale.resolve(123)
    assert {:error, {:invalid_locale, %{}}} = Locale.resolve(%{})
  end
end
