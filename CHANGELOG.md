# Changelog

## [v0.1.0] — unreleased

* `Tempo.Holidays.recurrences/2` and `materialise/3` return a territory's holidays — every `:type`, for every territory in the dataset — as Tempo recurrences, projected onto any year and date-sorted.

* Requests accept a CLDR territory code, a BCP 47 locale (string, atom, or `Localize.LanguageTag`), or a holiday list. A locale is validated through `Localize` and its territory, state (division) and region (subdivision) derived — `en-US-u-sd-usca` selects California — each overridable via `:territory`/`:division`/`:subdivision`. State and region holidays are compiled and shipped alongside the national set (`Tempo.Holidays.Locale`).

* Territory inheritance (date-holidays' `_days`): a territory that inherits another's holidays — Jersey/Guernsey/Isle of Man from Great Britain, the French overseas territories from France, and 22 in all — now carries the full inherited set plus its own, an inheriting territory's own entries overriding by rule and a `false` removing an inherited one.

* Rule compiler covering date-holidays' grammar: fixed dates and `P<n>D` spans, weekday-in-month, relative and nested weekdays (Election Day, Black Friday), month-anchor weekdays, Islamic/Hebrew/Persian calendar dates, `julian MM-DD` fixed dates (Orthodox/Coptic/Ethiopian Christmas, converted to Gregorian), Chinese and Korean lunisolar dates and Chinese solar terms (Qingming), equinox/solstice dates (Japan's Equinox Days, timezone-aware), Easter/orthodox-relative, and specific dates. Islamic dates use Umm al-Qura and are returned in-calendar — a lunar date can fall twice in one Gregorian year, so `materialise/2` returns a list.

* Rule modifiers: observed-date substitution with per-clause modes — a bare `if` moves the holiday (shift), an `and if` keeps it and adds the observed day, and a `substitutes` prefix yields the observed day alone — where the first clause a date triggers fires and the rest leave it alone, matching date-holidays' persistent modifier. Plus `since`/`prior to`, even/odd, leap, `every N years`, and `on`/`not on <weekday>` filters. An observed date crossing the Gregorian year boundary is attributed to the year it falls in, and a `disable`+`enable` pair is a move (the enable applies only when the disable matches a computed date).

* Occurrence-level metadata gates from date-holidays: `active` windows (half-open `[from, to)`), `disable`d dates and `enable`d dates — a `disable`+`enable` pair moves an occurrence, as with the UK 2022 Spring bank holiday to the Platinum Jubilee Thursday.

* Grammar coverage refinements: Easter/orthodox `P<n>D` spans (`easter -6 P5D`), calendar durations with a time suffix (`1 Shawwal P3DT0H0M`), a weekday after the Nth weekday after a date (`monday after 3rd sunday after 09-01`), the `and` that chains a `since` condition to a bare `if` (a move, not an added observance), date-precise `since`/`prior to YYYY-MM-DD` windows, and an Nth-weekday-in-month that overflows into the next month when the month is short (`5th monday in October`).

* An opt-in conformance test (`mix test --include conformance`) checks every compiled rule's dates against the full date-holidays fixture corpus (9,695 files); over 99% match, with the remainder tracked as the calendars and edge cases still to land.

* Materialisation merges abutting occurrences of the same holiday into one period, so a period split across two entries (to dodge a YAML year boundary) reads as the single span it describes.

* The compiled data is generated at build time by the `:holidays` Mix compiler from a pinned date-holidays bundle (`3.37.0`), written to `priv/holidays/<CC>.etf` and shipped in the package — a reproducible build with no data vendored in git, and no JSON needed to load the result on any OTP. `mix tempo.holidays.update` forces a refresh.
