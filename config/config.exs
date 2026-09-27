import Config

# tempo_holidays requires a time zone database, as Tempo does for zone work:
# an equinox or solstice in a named zone (Chile's `june solstice in
# America/Santiago`) resolves through it, and `Tempo.Holidays.Application`
# refuses to start without one. Tz is a tempo_holidays dependency.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
