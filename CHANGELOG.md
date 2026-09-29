# Changelog

## [v0.1.0] — unreleased

First release. Public holidays for every territory in the [date-holidays](https://github.com/commenthol/date-holidays) dataset, as Tempo recurrences for any window.

* Every holiday type, resolved from a CLDR territory code or a BCP 47 locale, with a `:subdivision` found at whichever level the data holds it (an unknown one is an error) and territory inheritance.

* The full date-holidays grammar — fixed and weekday dates, Islamic/Hebrew/Persian/Julian, Chinese/Korean/Vietnamese lunisolar, solar-term and equinox/solstice dates, observed-date substitution, occurrence gates, and inter-holiday bridge days.

* `Tempo.Holidays.holidays/2` — a territory's holidays as a `Tempo.RecurrenceSet`, one member per holiday tagged with its `:id`, `:name` and `:type`, selected by type with `:include` and `:exclude`, which `Tempo.to_interval_set/2` converts to a window's holidays. All 1,828 of the dataset's rules are declarative recurrences, the bridge and `if`-holiday rules as conditional members.

* `:dates` gives a holiday observed on a substitute day on that day (`:substitute`, the default), on its own date (`:gazetted`) or on both (`:both`). A period date-holidays splits over the year end is one member, and a dated period keeps its length.

* `Tempo.Holidays.Rule.materialise/2` evaluates each rule's recurrence, built once per territory (`Rule.prepare/1`); `Rule.materialise_concrete/2` keeps the kind-by-kind computation.

* `Tempo.Holidays.day_start/2` projects the occurrences of a holiday whose day begins at sunset onto the evening before, at sunset or 18:00, at the calendar's reference place or a location of your own.

* Requires a time zone database, as Tempo does for its zone work (`config :elixir, :time_zone_database, Tz.TimeZoneDatabase`); the application refuses to start without one.

* Over 99% conformant with the date-holidays fixture corpus (`mix test --include conformance`).
