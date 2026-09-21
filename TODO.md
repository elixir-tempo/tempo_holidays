# TODO

Work on `tempo_holidays`. Design notes live in `plans/` once a topic needs
more than a line here. Conformance against the full date-holidays fixture
corpus (`mix test --include conformance`) drives the remaining tiers; it sits
at ~96% matched, and the gaps below are what remains.

## Open

* [ ] **State/region tiers** — the build compiles only country-level `days`; sub-territory `days` (`US-AL`, AU state holidays like King's Birthday) are still to come. Analysis in [plans/date-holidays-format.md](plans/date-holidays-format.md).

* [ ] **Inter-holiday, disable/enable, and additional-day rules** — `"09-22 if 09-21 and 09-23 is public holiday"`, `disable`/`enable` overrides (GB's 2022 Jubilee move), and "observe as well as" in-lieu days. Edge cases, each a handful of entries.

* [ ] **Localize integration** — localized holiday names (MF2), and accepting a `LanguageTag` (territory + language in one) wherever a territory code is taken today.

## Blocked

* [ ] **Hebrew / Chinese / Bengali / Ethiopian / Coptic / Julian calendar dates** — need Tempo `[u-ca=…]` support and settled month numbering (Hebrew leap-month Adar I/II shifts Nisan onward). Blocked on Calendrical calendar coverage.

* [ ] **Equinox / solstice / solar terms** — the astronomical tier. Blocked on Astro integration.

* [ ] **Tabular Umm al-Qura** — our *calculated* Umm al-Qura differs from date-holidays' *table* by a day some years (~205 fixture entries), plus day-overflow like `30 Safar` (a 29-day month). Blocked on a tabular Umm al-Qura in Calendrical.

## Done

* [x] **Conformance harness** — `Tempo.Holidays.Fixtures` + `Conformance` run every compiled rule against the full date-holidays fixture corpus (9,695 files) as an opt-in `:conformance` test; ~96% of rules match. 2026-09-21.

* [x] **Grammar tiers** — fixed dates + `P<n>D` spans, weekday-in-month, relative and nested weekdays (Election Day, Black Friday), month-anchor weekdays, specific dates, Persian calendar; plus `on`/`not on <weekday>`, `since`/`prior to`, even/odd, leap and `every N years` filters. 2026-09-21.

* [x] **Substitution modes** — `and if` adds the observed day, bare `if` moves it, `substitutes …` is the observed day alone; comma-spaced multi-weekday triggers. 2026-09-21.

* [x] **Islamic (Hijri) tier → Umm al-Qura** — projected onto a Gregorian year via Calendrical's `dates_in_gregorian_year/3`, returned in `[u-ca=islamic-umalqura]` (matches date-holidays 95% vs civil's 38%); `materialise/2` returns a list, so a date falling twice in a year yields both. 2026-09-21.

* [x] **Real-data pipeline, no seed** — the `:holidays` Mix compiler generates `priv/holidays/<CC>.etf` for every territory from a pinned date-holidays bundle (`3.37.0`), shipped in the package and loaded by `Data.for_territory/1`. 2026-09-21.

* [x] **All holiday types** — every date-holidays `:type` is carried (public through observance). 2026-09-21.

* [x] **Name-aware coalescing** — abutting occurrences of the same holiday merge into one period; different neighbours stay apart. 2026-09-21.
