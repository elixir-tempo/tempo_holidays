# TODO

Work on `tempo_holidays`. Design notes live in `plans/` once a topic needs
more than a line here. Conformance against the full date-holidays fixture
corpus (`mix test --include conformance`) drives the remaining tiers; it sits
at ~96% matched, and the gaps below are what remains.

## Open

* [ ] **Per-occurrence `disable`/`enable`** — a holiday's `disable: ['YYYY-MM-DD']` / `enable:` metadata (GB's 2022 Jubilee move); the `states`/`regions` `false` disables are already handled by the build-time merge. A handful of fixture entries.

* [ ] **Inter-holiday and additional-day rules** — `"09-22 if 09-21 and 09-23 is public holiday"` and "observe as well as" in-lieu days. Edge cases.

* [ ] **Localized names (MF2)** — holiday names in the requested locale's language, beyond the current English/`_name` resolution.

## Blocked

* [ ] **Hebrew / Chinese / Bengali / Ethiopian / Coptic / Julian calendar dates** — need Tempo `[u-ca=…]` support and settled month numbering (Hebrew leap-month Adar I/II shifts Nisan onward). Blocked on Calendrical calendar coverage.

* [ ] **Equinox / solstice / solar terms** — the astronomical tier. Blocked on Astro integration.

* [ ] **Tabular Umm al-Qura** — our *calculated* Umm al-Qura differs from date-holidays' *table* by a day some years (~205 fixture entries), plus day-overflow like `30 Safar` (a 29-day month). Blocked on a tabular Umm al-Qura in Calendrical.

## Done

* [x] **Locale / LanguageTag requests + state/region data** — `recurrences/2`, `materialise/3` accept a territory code, a validated BCP 47 locale (string/atom/`Localize.LanguageTag`), or a holiday list, deriving territory + state (division) + region (subdivision), overridable by option. The build compiles country + state + region holidays (state `days` merged over the country's), and the loader picks the most specific level, falling back to the country. `en-US-u-sd-usca` → California; AU-NSW carries King's Birthday. 2026-09-21.

* [x] **Conformance harness** — `Tempo.Holidays.Fixtures` + `Conformance` run every compiled rule against the full date-holidays fixture corpus (9,695 files) as an opt-in `:conformance` test; ~96% of rules match. 2026-09-21.

* [x] **Grammar tiers** — fixed dates + `P<n>D` spans, weekday-in-month, relative and nested weekdays (Election Day, Black Friday), month-anchor weekdays, specific dates, Persian calendar; plus `on`/`not on <weekday>`, `since`/`prior to`, even/odd, leap and `every N years` filters. 2026-09-21.

* [x] **Substitution modes** — `and if` adds the observed day, bare `if` moves it, `substitutes …` is the observed day alone; comma-spaced multi-weekday triggers. 2026-09-21.

* [x] **Islamic (Hijri) tier → Umm al-Qura** — projected onto a Gregorian year via Calendrical's `dates_in_gregorian_year/3`, returned in `[u-ca=islamic-umalqura]` (matches date-holidays 95% vs civil's 38%); `materialise/2` returns a list, so a date falling twice in a year yields both. 2026-09-21.

* [x] **Real-data pipeline, no seed** — the `:holidays` Mix compiler generates `priv/holidays/<CC>.etf` for every territory from a pinned date-holidays bundle (`3.37.0`), shipped in the package and loaded by `Data.for_territory/1`. 2026-09-21.

* [x] **All holiday types** — every date-holidays `:type` is carried (public through observance). 2026-09-21.

* [x] **Name-aware coalescing** — abutting occurrences of the same holiday merge into one period; different neighbours stay apart. 2026-09-21.
