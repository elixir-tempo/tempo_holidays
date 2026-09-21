# Changelog

## [v0.1.0] — unreleased

* `Tempo.Holidays.recurrences/1` and `materialise/2` return a territory's holidays — every `:type`, for every territory in the dataset — as Tempo recurrences, projected onto any year and date-sorted. `for_territory/1` takes a CLDR code as an atom or string.

* Rule compiler covering date-holidays' grammar: fixed dates and `P<n>D` spans, weekday-in-month, relative and nested weekdays (Election Day, Black Friday), month-anchor weekdays, Islamic/Hebrew/Persian calendar dates, Easter/orthodox-relative, and specific dates. Islamic dates use Umm al-Qura and are returned in-calendar — a lunar date can fall twice in one Gregorian year, so `materialise/2` returns a list.

* Rule modifiers: observed-date substitution in `and if` (add), `if` (shift) and `substitutes` (observed-only) modes; and `since`/`prior to`, even/odd, leap, `every N years`, and `on`/`not on <weekday>` filters that gate whether a holiday occurs.

* An opt-in conformance test (`mix test --include conformance`) checks every compiled rule's dates against the full date-holidays fixture corpus (9,695 files); ~96% match, with the remainder tracked as the calendars and edge cases still to land.

* Materialisation merges abutting occurrences of the same holiday into one period, so a period split across two entries (to dodge a YAML year boundary) reads as the single span it describes.

* The compiled data is generated at build time by the `:holidays` Mix compiler from a pinned date-holidays bundle (`3.37.0`), written to `priv/holidays/<CC>.etf` and shipped in the package — a reproducible build with no data vendored in git, and no JSON needed to load the result on any OTP. `mix tempo.holidays.update` forces a refresh.
