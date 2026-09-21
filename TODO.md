# TODO

Work on `tempo_holidays`. Design notes live in `plans/` once a topic needs
more than a line here. Conformance against the full date-holidays fixture
corpus (`mix test --include conformance`) drives the remaining tiers; it sits
at ~96% matched, and the gaps below are what remains.

## Open

* [ ] **Inter-holiday / bridge-day rules** — `"09-22 if 09-21 and 09-23 is public holiday"`, `<rule> if is holiday then next <weekday>`, and "observe as well as" in-lieu days; needs a country-level second pass over the other holidays. A handful of entries.

* [ ] **Localized names (MF2)** — holiday names in the requested locale's language, beyond the current English/`_name` resolution.

## Blocked

* [ ] **Vietnamese (`vietnamese <month>-<leap>-<day>`) lunisolar dates** — Vietnamese lunar (Tet et al., ~10 rules) is Chinese-lunisolar at the UTC+7 meridian; there is no `Calendrical.Vietnamese`. The machinery exists (`Calendrical.Lunisolar.gregorian_date_for_lunar/5` takes a location), so this is an upstream addition to Calendrical, not a Tempo helper (rule 9). Analysis in [plans/vietnamese-calendar.md](plans/vietnamese-calendar.md).

* [ ] **Bengali (`bengali-revised`) calendar dates** — no Bengali calendar in Calendrical (closest is `Calendrical.Indian`, the Saka calendar). Blocked on a Bengali calendar upstream.

* [ ] **Tabular Umm al-Qura** — our *calculated* Umm al-Qura differs from date-holidays' *table* by a day some years, plus day-overflow like `30 Safar` (a 29-day month). Many are corrected in-data by the `disable`/`enable` gates now handled; the residual is blocked on a tabular Umm al-Qura in Calendrical.

## Done

* [x] **Year-boundary substitution** — `materialise/2` gathers a substituted rule's occurrences across the target year and its two neighbours and keeps those whose observed date lands in the target Gregorian year, matching date-holidays' attribution (New Year on a weekend → observed 31 Dec belongs to the prior year). 2026-09-22.

* [x] **IANA-zone equinox/solstice** — added `{:tz, "~> 0.28"}` as a direct dependency and pass `Tz.TimeZoneDatabase` to `DateTime.shift_zone/3`, so Chile's `june solstice in America/Santiago` resolves; numeric offsets and GMT still need no tz data. 2026-09-22.

* [x] **Equinox / solstice tier** — `<march|september> equinox` / `<june|december> solstice` via `Astro.equinox/2`,`Astro.solstice/2`, with an optional `<n> days before/after` and `in <timezone>`; the civil date is taken in that timezone (Japan's Vernal/Autumnal Equinox Days in `+09:00`), GMT when none. Fixed a latent `strip_time` bug that ate the `HH:MM` of a `+HH:MM` offset. Named IANA zones skip cleanly without a host tz database (the remaining astronomical gap, below). 2026-09-22.

* [x] **Chinese, Korean and solar-term tiers** — lunar `chinese|korean <month>-<leap>-<day>` (with `P<n>D` span and day-0 eve) via `gregorian_date_for_lunar/3`, returned in-calendar (`[u-ca=chinese]` / `[u-ca=dangi]`) with the traditional→ordinal month resolved past intercalary months; and `chinese <term>-<day> solarterm` (Qingming) via `Calendrical.Lunisolar.solar_longitude_on_or_after/3` in China time. Scoped conformance for CN/HK/TW/SG/MY/…: 0 chinese mismatches (was ~1575). 2026-09-22.

* [x] **Hebrew and Julian calendar tiers** — `<day> <Hebrew month>` via `Calendrical.Hebrew.dates_in_gregorian_year/3` (month names → CLDR-civil numbering; `AdarII` → month 7 in both leap and ordinary years), and `julian MM-DD` via `Calendrical.Julian.dates_in_gregorian_year/3` converted to Gregorian (covers Orthodox/Coptic/Ethiopian Christmas). Scoped conformance for IL/RU/RS/UA/EG/ER/ME: 0 calendar mismatches, 1 unsupported. 2026-09-22.

* [x] **Occurrence-level metadata gates** — `active` windows (`[from, to)`), `disable`d and `enable`d dates from date-holidays metadata, applied to the computed dates in `Tempo.Holidays.Rule`; a `disable`+`enable` pair moves an occurrence (UK 2022 Jubilee). The conformance harness enriches each compiled rule with the built data's gates so the metric reflects them. Localize bumped to `~> 1.3`. 2026-09-22.

* [x] **Locale / LanguageTag requests + state/region data** — `recurrences/2`, `materialise/3` accept a territory code, a validated BCP 47 locale (string/atom/`Localize.LanguageTag`), or a holiday list, deriving territory + state (division) + region (subdivision), overridable by option. The build compiles country + state + region holidays (state `days` merged over the country's), and the loader picks the most specific level, falling back to the country. `en-US-u-sd-usca` → California; AU-NSW carries King's Birthday. 2026-09-21.

* [x] **Conformance harness** — `Tempo.Holidays.Fixtures` + `Conformance` run every compiled rule against the full date-holidays fixture corpus (9,695 files) as an opt-in `:conformance` test; ~96% of rules match. 2026-09-21.

* [x] **Grammar tiers** — fixed dates + `P<n>D` spans, weekday-in-month, relative and nested weekdays (Election Day, Black Friday), month-anchor weekdays, specific dates, Persian calendar; plus `on`/`not on <weekday>`, `since`/`prior to`, even/odd, leap and `every N years` filters. 2026-09-21.

* [x] **Substitution modes** — `and if` adds the observed day, bare `if` moves it, `substitutes …` is the observed day alone; comma-spaced multi-weekday triggers. 2026-09-21.

* [x] **Islamic (Hijri) tier → Umm al-Qura** — projected onto a Gregorian year via Calendrical's `dates_in_gregorian_year/3`, returned in `[u-ca=islamic-umalqura]` (matches date-holidays 95% vs civil's 38%); `materialise/2` returns a list, so a date falling twice in a year yields both. 2026-09-21.

* [x] **Real-data pipeline, no seed** — the `:holidays` Mix compiler generates `priv/holidays/<CC>.etf` for every territory from a pinned date-holidays bundle (`3.37.0`), shipped in the package and loaded by `Data.for_territory/1`. 2026-09-21.

* [x] **All holiday types** — every date-holidays `:type` is carried (public through observance). 2026-09-21.

* [x] **Name-aware coalescing** — abutting occurrences of the same holiday merge into one period; different neighbours stay apart. 2026-09-21.
