# TODO

Work on `tempo_holidays`. Design notes live in `plans/` once a topic needs
more than a line here.

## Open

* [ ] **`since <year>` and state/region tiers** — the compiler drops both, so the real data is missing US Juneteenth (a `since 2021` holiday) and AU King's Birthday (carried at state level). The most visible coverage gaps. Analysis in [plans/date-holidays-format.md](plans/date-holidays-format.md).

* [ ] **Additional-day (in-lieu) holidays** — some territories keep a holiday's date on a weekend *and* add an observed weekday, needing per-holiday semantics and collision resolution across the added days.

* [ ] **Compiler tiers beyond the current set** — the other lunar calendars (Hebrew, Chinese, Persian, Bengali via Calendrical, like the Islamic tier), equinox/solstice and solar terms (via Astro / lunisolar calendars), and `disable`/`enable` date qualifiers.

* [ ] **Cross-year range holidays** — school-holiday periods expressed as `:range` rules; the name-aware coalescing that merges their split entries is already in place.

* [ ] **Localize integration** — localized holiday names (MF2), and accepting a `LanguageTag` (territory + language in one) wherever a territory code is taken today.

## Done

* [x] **Real-data pipeline, no seed** — the `:holidays` Mix compiler generates `priv/holidays/<CC>.etf` for every territory from a pinned date-holidays bundle (`3.37.0`), shipped in the package and loaded by `Data.for_territory/1`. Replaces the hand-written AU/US seed. 2026-09-21.

* [x] **All holiday types** — every date-holidays `:type` is carried (public through observance), not just public holidays. 2026-09-21.

* [x] **Islamic (Hijri) tier** — holidays projected onto a Gregorian year via Calendrical's `dates_in_gregorian_year/3` and returned in `[u-ca=islamic-civil]`; `materialise/2` returns a list, so a lunar date that falls twice in a Gregorian year (Eid al-Fitr in 2000) yields both occurrences. 2026-09-21.

* [x] **Weekday ordinals and substitution direction** — `"last"`/word ordinals (ISO `-1I`), and `:next`/`:previous` substitution so both the weekend→Monday and Saturday→Friday/Sunday→Monday observances express cleanly. 2026-09-21.

* [x] **Observed-date substitution** — `"… if weekend then next monday"` compiled to `{trigger, direction, target}` clauses, applied after the base date is placed. 2026-09-21.

* [x] **Name-aware coalescing** — abutting occurrences of the same holiday merge into one period; different neighbours stay apart. 2026-09-21.

* [x] **Rule compiler** — fixed (`MM-DD`), weekday-in-month (ISO `FL…I…KN`), relative weekday, Easter/orthodox-relative, plus the substitution suffix. 2026-09-21.
