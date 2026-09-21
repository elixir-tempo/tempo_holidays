# TODO

Work on `tempo_holidays`. Design notes live in `plans/` once a topic needs
more than a line here.

## Open

* [ ] **`mix tempo.holidays.update` download task** — pull the [date-holidays](https://github.com/commenthol/date-holidays) dataset, compile it through `Tempo.Holidays.Compiler`, and write `priv/holidays/`. Usable by consumers as well as the build.

* [ ] **Additional-day (in-lieu) holidays** — AU Christmas/Boxing keep their date on a weekend *and* add an observed weekday (unlike the New Year / Australia Day shift), needing per-holiday semantics and collision resolution across the added days. Waits on the real dataset, which encodes the per-territory rules.

* [ ] **Compiler tiers beyond the current set** — lunar calendars (Islamic, Hebrew, Chinese, Persian, Bengali via Calendrical), equinox/solstice and solar terms (via Astro / lunisolar calendars), active-range and disable/enable qualifiers, and holiday `:type`.

* [ ] **Cross-year range holidays** — school-holiday periods expressed as `:range` rules; the name-aware coalescing that merges their split entries is already in place.

* [ ] **Localize integration** — localized holiday names (MF2), and accepting a `LanguageTag` (territory + language in one) wherever a territory atom is taken today.

* [ ] **More territories** — AU and US are the seed; extend once the download task lands.

## Done

* [x] **AU and US public-holiday slices** — `Tempo.Holidays.recurrences/1` and `materialise/2` over each territory's national holidays, date-sorted. 2026-09-21.

* [x] **Weekday ordinals and substitution direction** — `"last"`/word ordinals (ISO `-1I`), and `:next`/`:previous` substitution so both the AU (weekend → Monday) and US (Saturday → prior Friday, Sunday → next Monday) observance express cleanly. 2026-09-21.

* [x] **Observed-date substitution** — `"… if weekend then next monday"` compiled to `{trigger, direction, target}` clauses, applied after the base date is placed. 2026-09-21.

* [x] **Name-aware coalescing** — abutting occurrences of the same holiday merge into one period; different neighbours stay apart. 2026-09-21.

* [x] **Rule compiler** — fixed (`MM-DD`), weekday-in-month (ISO `FL…I…KN`), Easter/orthodox-relative, plus the substitution suffix. 2026-09-21.
