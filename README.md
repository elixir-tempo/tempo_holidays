# Tempo.Holidays

**TODO: Add description**

## Supported Elixir and OTP versions

tempo_holidays supports **Elixir 1.17** and later on **OTP 27** and later; OTP 26 is not supported, because Tempo requires OTP 27.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `tempo_holidays` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tempo_holidays, "~> 0.1.0"}
  ]
end
```

tempo_holidays reads a zone through the time zone database Tempo asks, [`Tempo.time_zone_database/0`](https://hexdocs.pm/ex_tempo/Tempo.html#time_zone_database/0). Tempo comes with Tz and asks it where nothing else is configured, so no configuration is needed. An application that names a database for Tempo with `config :ex_tempo, :time_zone_database` must name one that knows named zones: tempo_holidays refuses to start with `Calendar.UTCOnlyTimeZoneDatabase`.

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/tempo_holidays>.

