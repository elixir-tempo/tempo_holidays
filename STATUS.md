# Status

**Status:** active, 2026-09-29

**Next release:** 0.1.0
**Blocked on:** ex_tempo ~> 2.0, expected 2026-10
**Blocked on:** calendrical ~> 1.4, expected 2026-10
**Blocked on:** localize ~> 1.4, expected 2026-10

Under development, not yet released. Public holidays as Tempo recurrences, compiled from [date-holidays](https://github.com/commenthol/date-holidays) rules, for any window. Functional work is tracked in `TODO.md` and designed in `plans/`.

The recurrences need Tempo's unreleased 2.0.0 work, and the Islamic tier needs Calendrical's `dates_in_gregorian_year/3`, unreleased as of calendrical 1.3.0, so Tempo, Calendrical and Localize are co-development GitHub deps on `main` until the releases carrying them ship. Those follow CLDR 49 in mid-October 2026: Localize 1.4 and Calendrical 1.4 carry it, and Tempo 2.0.0 waits on both.
