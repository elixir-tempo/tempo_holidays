defmodule Mix.Tasks.Tempo.Holidays.Gettext do
  @shortdoc "Write the Gettext template of every holiday name"

  @moduledoc """
  Write `priv/gettext/holidays.pot`, the Gettext template of every holiday
  name the compiled data holds, for translators to translate.

  Each message's `msgid` is a holiday's name as `Tempo.Holidays.Names.msgid/2`
  gives it: its English name, or for a holiday the dataset names in no
  English, its name in the territory's own language, in MF2. A comment on
  each message lists the territories that name a holiday so, and the rule of
  one of them, for the translator's context.

  A translation is a `holidays.po` under `priv/gettext/<locale>/LC_MESSAGES`
  (`mix gettext.merge priv/gettext --locale de` starts one from the
  template). `Tempo.Holidays.holidays/2` reads it through
  `Tempo.Holidays.Gettext` where the dataset gives no name in a locale's
  language.

  Run it after the data is rebuilt from a new date-holidays release.

  ## Usage

      mix tempo.holidays.gettext

  """

  use Mix.Task

  alias Tempo.Holidays.{Data, Names}

  @template "priv/gettext/holidays.pot"

  @impl Mix.Task
  def run(_arguments) do
    Mix.Task.run("compile")

    messages =
      Data.territories()
      |> Enum.flat_map(&named_holidays/1)
      |> Enum.group_by(fn {msgid, _territory, _rule} -> msgid end)
      |> Enum.sort_by(fn {msgid, _uses} -> msgid end)
      |> Enum.map(&message/1)

    File.mkdir_p!(Path.dirname(@template))
    File.write!(@template, Expo.PO.compose(%Expo.Messages{headers: [""], messages: messages}))
    Mix.shell().info("tempo_holidays: wrote #{length(messages)} holiday names to #{@template}")
  end

  # Each holiday of a territory that the dataset names, with its message,
  # the territory and its rule.
  defp named_holidays(territory) do
    case {Data.languages(territory), Data.every_holiday(territory)} do
      {{:ok, languages}, {:ok, holidays}} ->
        for holiday <- holidays, map_size(holiday.names) > 0 do
          {Names.msgid(holiday, languages), territory, holiday.rule}
        end

      _unknown_territory ->
        []
    end
  end

  defp message({msgid, uses}) do
    territories =
      uses
      |> Enum.map(fn {_msgid, territory, _rule} -> territory end)
      |> Enum.uniq()
      |> Enum.sort()

    {_msgid, _territory, rule} = hd(uses)

    %Expo.Message.Singular{
      msgid: [msgid],
      msgstr: [""],
      extracted_comments: [" #{Enum.join(territories, ", ")}: #{rule}"]
    }
  end
end
