# Changelog

## [v0.1.0] — unreleased

* `Tempo.Holidays.recurrences/1` and `materialise/2` return a territory's public holidays as Tempo recurrences, projected onto any year and date-sorted. Seed slices for `:AU` and `:US`.

* Rule compiler for date-holidays strings: fixed dates, weekday-in-month (`"2nd Monday in June"`, `"last Monday in May"`), relative weekday (`"monday before 06-01"`), Easter/orthodox-relative, and an observed-date substitution suffix (`"… if saturday then previous friday if sunday then next monday"`).

* Materialisation merges abutting occurrences of the same holiday into one period, so a period split across two entries (to dodge a YAML year boundary) reads as the single span it describes.

* `mix tempo.holidays.update` downloads the date-holidays dataset (over TLS via Localize's HTTP client), compiles the supported rules through `Tempo.Holidays.DateHolidays`, resolves `_name` references to localized names from the bundle's shared table, and writes `priv/holidays/<CC>.etf` — no JSON needed to load the result on any OTP.
