# Tempo.Holidays

**TODO: Add description**

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

tempo_holidays requires a time zone database, as Tempo does for its zone work, and refuses to start without one. Tz is a dependency, so configure it:

```elixir
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/tempo_holidays>.

