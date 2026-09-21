# Changelog

## [v0.1.0] — unreleased

* `Tempo.Holidays.recurrences/1` and `materialise/2` return a territory's holidays — every `:type`, for every territory in the dataset — as Tempo recurrences, projected onto any year and date-sorted. `for_territory/1` takes a CLDR code as an atom or string.

* Rule compiler for date-holidays strings: fixed dates, weekday-in-month (`"2nd Monday in June"`, `"last Monday in May"`), relative weekday (`"monday before 06-01"`), Islamic/Hijri (`"9 Dhu al-Hijjah P4D"`, projected onto a Gregorian year via Calendrical and returned in the Islamic calendar — a lunar date can fall twice in one year, so `materialise/2` returns a list), Easter/orthodox-relative, and an observed-date substitution suffix (`"… if saturday then previous friday if sunday then next monday"`).

* Materialisation merges abutting occurrences of the same holiday into one period, so a period split across two entries (to dodge a YAML year boundary) reads as the single span it describes.

* The compiled data is generated at build time by the `:holidays` Mix compiler from a pinned date-holidays bundle (`3.37.0`), written to `priv/holidays/<CC>.etf` and shipped in the package — a reproducible build with no data vendored in git, and no JSON needed to load the result on any OTP. `mix tempo.holidays.update` forces a refresh.
