# Changelog

## [v0.1.0] — unreleased

First release. Public holidays for every territory in the [date-holidays](https://github.com/commenthol/date-holidays) dataset, as Tempo recurrences projected onto any year.

* Every holiday type, resolved from a CLDR territory code, a BCP 47 locale, or a holiday list, with state/region levels and territory inheritance.

* The full date-holidays grammar — fixed and weekday dates, Islamic/Hebrew/Persian/Julian, Chinese/Korean/Vietnamese lunisolar, solar-term and equinox/solstice dates, observed-date substitution, occurrence gates, and inter-holiday bridge days.

* `:day_start` projects a sunset-starting-calendar holiday onto the Gregorian timeline as a datetime interval beginning at sunset (or 18:00) the evening before.

* Over 99% conformant with the date-holidays fixture corpus (`mix test --include conformance`).
