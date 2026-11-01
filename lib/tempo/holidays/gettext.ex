defmodule Tempo.Holidays.Gettext do
  @moduledoc """
  The Gettext backend holiday names are translated by, where the dataset
  gives a holiday no name in a locale's language.

  Its catalog is the `"holidays"` domain under `priv/gettext`: a message
  for each holiday name, its `msgid` the name in English (or, for a holiday
  the dataset names in no English, in the territory's own language), written
  in MF2 as every message of the Localize stack is. `mix
  tempo.holidays.gettext` writes the template, `holidays.pot`, from the
  compiled data; a translation is a `holidays.po` under the locale's
  directory, `priv/gettext/<locale>/LC_MESSAGES`.

  An application with its own translations names its own backend, one that
  uses `Localize.Gettext.Interpolation` as this one does, and holds a
  `"holidays"` domain:

      config :tempo_holidays, gettext: MyApp.Gettext

  See `Tempo.Holidays.Names` for the order a name is looked for in.

  """

  use Gettext.Backend,
    otp_app: :tempo_holidays,
    interpolation: Localize.Gettext.Interpolation
end
