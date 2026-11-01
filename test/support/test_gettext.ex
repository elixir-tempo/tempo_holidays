defmodule Tempo.Holidays.TestGettext do
  @moduledoc false

  # A Gettext backend with a catalog of its own, as an application that
  # translates holiday names names in `config :tempo_holidays, gettext: …`.
  use Gettext.Backend,
    otp_app: :tempo_holidays,
    priv: "test/support/gettext",
    interpolation: Localize.Gettext.Interpolation
end
