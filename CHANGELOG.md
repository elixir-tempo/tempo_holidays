# Changelog

## [v0.1.0] — unreleased

First release. Public holidays for every territory in the [date-holidays](https://github.com/commenthol/date-holidays) dataset, as Tempo recurrences projected onto any window.

* Every holiday type, resolved from a CLDR territory code or a BCP 47 locale, with state/region levels and territory inheritance.

* The full date-holidays grammar — fixed and weekday dates, Islamic/Hebrew/Persian/Julian, Chinese/Korean/Vietnamese lunisolar, solar-term and equinox/solstice dates, observed-date substitution, occurrence gates, and inter-holiday bridge days.

* `Tempo.Holidays.holidays/2` — a territory's holidays as a `Tempo.RecurrenceSet`, one member per holiday tagged with its `:id`, `:name` and `:type`, selected by type with `:include` and `:exclude`; `materialise/3` gives their occurrences over any window as a labelled `Tempo.IntervalSet`. All 1,828 of the dataset's rules are declarative recurrences, the bridge and `if`-holiday rules as conditional members.

* `Tempo.Holidays.Rule.materialise/2` evaluates each rule's recurrence, built once per territory (`Rule.prepare/1`); `Rule.materialise_concrete/2` keeps the kind-by-kind computation.

* `:day_start` projects a sunset-starting-calendar holiday onto the Gregorian timeline as a datetime interval beginning at sunset (or 18:00) the evening before.

* Requires a time zone database, as Tempo does for its zone work (`config :elixir, :time_zone_database, Tz.TimeZoneDatabase`); the application refuses to start without one.

* Over 99% conformant with the date-holidays fixture corpus (`mix test --include conformance`).
