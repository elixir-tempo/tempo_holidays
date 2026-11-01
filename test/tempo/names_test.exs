defmodule Tempo.Holidays.NamesTest do
  # A holiday's name is the one a locale reads: the dataset's in the locale's
  # language, the catalog's, English, the territory's own, any. One test sets
  # the application's configured holidays, which every request sees.
  use ExUnit.Case, async: false

  alias Tempo.Holidays
  alias Tempo.Holidays.{Data, Gettext, Holiday, Names}

  defp names(holidays) do
    holidays
    |> Tempo.RecurrenceSet.members()
    |> Enum.map(&Tempo.metadata(&1).name)
  end

  defp names(target, options) do
    {:ok, holidays} = Holidays.holidays(target, options)
    names(holidays)
  end

  describe "the dataset's name in the locale's language" do
    test "a locale's language and territory, then its language" do
      austrian = names([], locale: "de-AT")

      assert "Neujahr" in austrian
      # Named only `de-at`, as Austria names it.
      assert "Staatsfeiertag" in austrian
    end

    test "under CLDR's code where the dataset writes another" do
      assert "元日" in names([], locale: "ja-JP")
      assert Enum.any?(names([], locale: "cs-CZ"), &String.starts_with?(&1, "Nový rok"))
    end

    test "the language of a territory named apart from it" do
      assert "Neujahr" in names([], territory: :AT, locale: "de")
    end

    test "the process's locale where none is given" do
      # The locale is the test process's own, and ends with it.
      Localize.put_locale("de")

      assert "Neujahr" in names(:AT, [])
    end
  end

  describe "where the dataset has no name in the locale's language" do
    test "the catalog's translation comes first" do
      us = names([], territory: :US, locale: "eo")

      assert "Tago de la Liberigo" in us
      refute "Juneteenth" in us
    end

    test "then English" do
      assert "Labour Day" in names([], territory: :US, locale: "eo")
    end

    test "then the territory's own language: Glarus' Näfelser Fahrt, in German" do
      assert "Näfelser Fahrt" in names([], locale: "en-CH", subdivision: "GL")
      assert "Bataille de Näfels" in names([], locale: "fr-CH", subdivision: "GL")
    end
  end

  describe "a removal configured by name" do
    test "removes a holiday by its name in any language" do
      Application.put_env(:tempo_holidays, :holidays, AT: [remove: ["Neujahr"]])
      on_exit(fn -> Application.delete_env(:tempo_holidays, :holidays) end)

      refute "New Year's Day" in names([], locale: "en-AT")
      refute "Neujahr" in names([], locale: "de-AT")
    end
  end

  describe "the catalog's message" do
    test "is the English name, or the territory's own" do
      english = %Holiday{
        name: "x",
        rule: "01-01",
        names: %{"en" => "New Year", "de" => "Neujahr"}
      }

      german = %Holiday{
        name: "x",
        rule: "01-01",
        names: %{"de" => "Neujahr", "fr" => "Nouvel An"}
      }

      assert Names.msgid(english, ["de"]) == "New Year"
      assert Names.msgid(german, ["fr", "de"]) == "Nouvel An"
    end

    test "escapes what MF2 gives a meaning, so the name reads as text" do
      braced = %Holiday{name: "x", rule: "01-01", names: %{"en" => "A {b} c\\d"}}

      assert Names.msgid(braced, []) == "A \\{b\\} c\\\\d"
    end

    test "a holiday the dataset names in no language is its rule" do
      unnamed = %Holiday{name: "01-01", rule: "01-01"}

      assert Names.msgid(unnamed, []) == "01-01"
    end
  end

  describe "the last of the order" do
    test "a holiday named in none of the locale's, English or the territory's is in any it has" do
      french = %Holiday{
        name: "rule",
        rule: "01-01",
        names: %{"fr" => "Nouvel An", "it" => "Capodanno"}
      }

      {:ok, japanese} = Localize.validate_locale("ja")

      assert Names.name(french, japanese, []) == "Nouvel An"
    end

    test "a locale with no territory is looked for by its language" do
      german = %Holiday{name: "rule", rule: "01-01", names: %{"de" => "Neujahr"}}
      {:ok, locale} = Localize.validate_locale("de")

      assert Names.name(german, %{locale | territory: nil}, []) == "Neujahr"
    end
  end

  describe "the package's own catalog" do
    test "has no translations, so a name is the dataset's" do
      assert Gettext.lgettext("de", Names.domain(), nil, "Juneteenth", %{}) ==
               {:default, "Juneteenth"}
    end
  end

  describe "a territory's languages and every holiday it names" do
    test "by a code as a string or an atom" do
      assert Data.languages(:CH) == {:ok, ["de-ch", "de", "fr", "it"]}

      {:ok, country} = Data.for_territory("CH")
      {:ok, every} = Data.every_holiday(:CH)

      # The cantons' own holidays beside the country's.
      assert length(every) > length(country)
      assert Enum.any?(every, &(&1.names["de"] == "Näfelser Fahrt"))
    end

    test "a code that is no territory's, of whatever shape, is unknown" do
      for code <- ["ZZ", "../holidays/AU", 42, "ch-gl"] do
        assert {:error, {:unknown_territory, ^code}} = Data.languages(code)
        assert {:error, {:unknown_territory, ^code}} = Data.every_holiday(code)
      end
    end
  end

  test "a locale that is no locale is an error" do
    assert Holidays.holidays(territory: :US, locale: "not a locale") ==
             {:error, {:invalid_locale, "not a locale"}}
  end
end
