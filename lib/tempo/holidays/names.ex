defmodule Tempo.Holidays.Names do
  @moduledoc """
  A holiday's name in a locale's language.

  The dataset names a holiday in the languages its contributors wrote,
  seventy-seven of them across the territories, and `Tempo.Holidays.holidays/2`
  gives each holiday the name a locale reads. `name/3` looks for it in this
  order, taking the first it finds:

  1. The dataset's name in the locale's language and territory (`"de-at"`
     for `de-AT`), then in its language (`"de"`).

  2. A translation in the Gettext catalog (`Tempo.Holidays.Gettext`, or the
     backend `config :tempo_holidays, gettext: …` names), in the locale's
     language and territory (`"de_AT"`), then its language.

  3. The dataset's English name.

  4. The dataset's name in the territory's own languages, in the order it
     lists them: Swiss holidays in Swiss German, German, French, Italian.

  5. Any name the dataset gives, and last the holiday's rule.

  `msgid/2` is the message a holiday's name has in the catalog: its English
  name, or for a holiday with none, its name in the territory's own language,
  written in MF2.

  """

  alias Localize.LanguageTag
  alias Tempo.Holidays.Holiday

  @domain "holidays"

  @doc """
  The name of a holiday in a locale's language.

  ### Arguments

  * `holiday` is a `t:Tempo.Holidays.Holiday.t/0`.

  * `locale` is a `t:Localize.LanguageTag.t/0`.

  * `territory_languages` are the territory's own languages, as
    `Tempo.Holidays.Data.languages/1` gives them.

  ### Returns

  * The name, a string.

  ### Examples

      iex> {:ok, [new_year | _]} = Tempo.Holidays.Data.for_territory("AT")
      iex> {:ok, german} = Localize.validate_locale("de-AT")
      iex> Tempo.Holidays.Names.name(new_year, german, ["de-at"])
      "Neujahr"

      iex> {:ok, holidays} = Tempo.Holidays.Data.for_territory("CH", "GL")
      iex> fahrt = Enum.find(holidays, &(&1.names["de"] == "Näfelser Fahrt"))
      iex> {:ok, english} = Localize.validate_locale("en")
      iex> Tempo.Holidays.Names.name(fahrt, english, ["de-ch", "de", "fr", "it"])
      "Näfelser Fahrt"

  """
  @spec name(Holiday.t(), LanguageTag.t(), [String.t()]) :: String.t()
  def name(%Holiday{names: names} = holiday, %LanguageTag{} = locale, territory_languages) do
    in_language(names, locale) ||
      catalogued(holiday, locale, territory_languages) ||
      default(holiday, territory_languages)
  end

  @doc """
  The message a holiday's name has in the Gettext catalog: its English name,
  or for a holiday the dataset names in no English, its name in the
  territory's own languages, then any it has, then its rule; in MF2, with
  the characters MF2 gives a meaning (`{`, `}` and `\\`) escaped.

  ### Arguments

  * `holiday` is a `t:Tempo.Holidays.Holiday.t/0`.

  * `territory_languages` are the territory's own languages.

  ### Returns

  * The message id, a string.

  ### Examples

      iex> {:ok, [new_year | _]} = Tempo.Holidays.Data.for_territory("AT")
      iex> Tempo.Holidays.Names.msgid(new_year, ["de-at"])
      "New Year's Day"

  """
  @spec msgid(Holiday.t(), [String.t()]) :: String.t()
  def msgid(%Holiday{} = holiday, territory_languages) do
    holiday
    |> default(territory_languages)
    |> escaped()
  end

  @doc """
  The Gettext domain holiday names are translated in.

  ### Returns

  * `"holidays"`.

  ### Examples

      iex> Tempo.Holidays.Names.domain()
      "holidays"

  """
  @spec domain() :: String.t()
  def domain do
    @domain
  end

  # The name with no locale to read it in: English, the territory's own
  # languages, any, the rule.
  defp default(%Holiday{names: names} = holiday, territory_languages) do
    Map.get(names, "en") ||
      Enum.find_value(territory_languages, &Map.get(names, &1)) ||
      any_name(names) ||
      holiday.name
  end

  defp in_language(names, locale) do
    locale
    |> codes("-")
    |> Enum.find_value(&Map.get(names, &1))
  end

  # A translation of the holiday's name in the catalog, in the locale's
  # language and territory, then its language. A backend's `lgettext/5`
  # takes the locale, so none is put in the process.
  defp catalogued(holiday, locale, territory_languages) do
    backend = Application.get_env(:tempo_holidays, :gettext, Tempo.Holidays.Gettext)
    message = msgid(holiday, territory_languages)

    locale
    |> codes("_")
    |> Enum.find_value(&translated(backend, &1, message))
  end

  defp translated(backend, gettext_locale, message) do
    case backend.lgettext(gettext_locale, @domain, nil, message, %{}) do
      {:ok, translation} -> translation
      _untranslated -> nil
    end
  end

  # A locale's language with its territory, then its language alone, as
  # the dataset (`"de-at"`) or Gettext (`"de_AT"`) writes them.
  defp codes(%LanguageTag{language: language, territory: nil}, _separator) do
    [Atom.to_string(language)]
  end

  defp codes(%LanguageTag{language: language, territory: territory}, "-") do
    language = Atom.to_string(language)
    [language <> "-" <> String.downcase(Atom.to_string(territory)), language]
  end

  defp codes(%LanguageTag{language: language, territory: territory}, "_") do
    language = Atom.to_string(language)
    [language <> "_" <> Atom.to_string(territory), language]
  end

  defp any_name(names) when map_size(names) == 0 do
    nil
  end

  defp any_name(names) do
    names
    |> Enum.min_by(fn {code, _name} -> code end)
    |> elem(1)
  end

  defp escaped(text) do
    String.replace(text, ["\\", "{", "}"], &("\\" <> &1))
  end
end
