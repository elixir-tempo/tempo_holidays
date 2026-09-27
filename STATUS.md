# Status

**Status:** active, 2026-09-27

Under development, not yet released. Public holidays as Tempo recurrences, compiled from [date-holidays](https://github.com/commenthol/date-holidays) rules, projectable onto any year. Functional work is tracked in `TODO.md` and designed in `plans/`.

The recurrences need Tempo's unreleased 1.7.0 work, and the Islamic tier needs Calendrical's `dates_in_gregorian_year/3`, unreleased as of calendrical 1.3.0, so Tempo (`extensions`), Calendrical and Localize (`main`) are co-development GitHub deps until the releases carrying them ship.

**Next release:** 0.1.0
**Blocked on:** ex_tempo ~> 1.7
**Blocked on:** calendrical ~> 1.4, expected 2026-10
**Blocked on:** localize ~> 1.4
