# TODO

Work on `tempo_holidays`. Design notes live in `plans/` once a topic needs
more than a line here. Conformance against the full date-holidays fixture
corpus (`mix test --include conformance`) drives the tiers: every rule that
compiles computes correct dates (zero mismatched), with a small set of accepted
`known_unsupported` gaps (the Bengali calendar and two rare shapes, below) and
the Islamic civil-date `divergent` differences.

## Open

* [ ] **Holidays as a Tempo grammar** — the core objective: express a holiday as a Tempo interval-set value so it composes with other Tempo values (`free_time ∩ holidays`). Categorisation by rule family and a phased path in [plans/holiday-grammar.md](plans/holiday-grammar.md).

* [ ] **Close the remaining declarative gaps** — `Rule.recurrence/1` emits a standalone recurrence for 1219/1478 rules; 80 stay `:needs_window` (lunisolar, islamic day-rollover/multi-day, tz equinox, solar term, easter multi-day) and 194 gates are dropped. Options per family, plus the compiler↔cookbook consistency reconciliation, in [plans/declarative-recurrence-gaps.md](plans/declarative-recurrence-gaps.md). First task there is a live crash: the solar-term `cal=nil` build bug.

* [ ] **Guides** — a User guide (getting holidays, locales, the interval model, calendars, the `:day_start` projection) and a Conformance guide (the date-holidays corpus, the buckets, accepted divergences), wired into `mix.exs` extras.

* [ ] **Day-start projection → Tempo-native** — `Tempo.Holidays.DayStart.project/3` (a calendar day → a Gregorian sunset/evening-bounded datetime interval) belongs natively in Tempo eventually, per the user; it is written self-contained to lift with little change. Also: territory-local anchoring (derive a territory's zone/location from the locale) as a follow-up to the current canonical/explicit anchors.

* [ ] **Localized names (MF2)** — holiday names in the requested locale's language, beyond the current English/`_name` resolution.

## Blocked

* [ ] **Bengali (`bengali-revised`) calendar dates** — no Bengali calendar in Calendrical (closest is `Calendrical.Indian`, the Saka calendar). Blocked on a Bengali calendar upstream; 8 Bangladesh rules, accepted `known_unsupported` in conformance meanwhile.

## Deferred

* [ ] **`Thursday before easter -46`** — a weekday relative to a computed Easter *offset* (not to Easter itself); one rule, no compiler tier for it. Accepted `known_unsupported`. Would revive if a second such rule appears.

* [ ] **`friday before 1st monday before 06-01 since 2009 and prior to 2016`** — a doubly-nested weekday relative (a weekday before an *nth-weekday-before-a-date*) with a year window; one expired US rule. Accepted `known_unsupported`.

## Done

* [x] **Taiwan Chinese New Year makeup days** — the substitution target is now weekday-bounded, so date-holidays' malformed chained TW rule (`…then next Saturdayif Wednesday…`, a missing space) parses instead of derailing; the 7-way lieu-day chain compiles and computes the correct observed dates. 2026-09-23.

* [x] **Day-start projection (`:day_start`)** — `materialise/3` projects a sunset-starting-calendar holiday (Islamic, Hebrew) onto the Gregorian timeline as a datetime interval that begins the evening before: `:evening` (18:00 proxy) or `:sunset` (true, via Astro), at the calendar's canonical reference (Mecca/Jerusalem) or an explicit zone-id / `{lng, lat}` location (`tz_world`-resolved, optional dep). `:midnight` (default) keeps the in-calendar day. New `Tempo.Holidays.DayStart`. 2026-09-22.

* [x] **Islamic day-count rollover** — the `:islamic` tier anchors on `first_day_of_month + (day-1)`, so a day beyond the month's length (`30 Ramadan` in a 29-day Ramadan → Eid, `30 Safar` → 1 Rabi) rolls into the next month and is labelled with its true in-calendar date instead of being dropped. With date-holidays' own `disable`/`enable` table corrections (which we apply), only **2** genuine off-by-one cases remain, accepted `divergent` — Calendrical authoritative. 2026-09-22.

* [x] **Vietnamese lunisolar** — `vietnamese <month>-<leap>-<day>` via `Calendrical.Vietnamese` (UTC+7 meridian, `[u-ca=chinese]` type). A lunisolar date is attributed to the Gregorian year it falls in (fixes Ông Táo, the 12th month), and a `<n> day[s] before/after <base> [P<n>D]` prefix carries Tết's eve. VN: 405/405 conform. 2026-09-22. [plans/vietnamese-calendar.md](plans/vietnamese-calendar.md)

* [x] **Inter-holiday / bridge-day rules** — the two `date-holidays-parser` `PostRule` forms, resolved in a country-level second pass: a *bridge* (`09-22 if 09-21 and 09-23 is public holiday`, Japan's Citizens' Holiday — kept only when the flanking dates are holidays of the type) and an `if is <type>? holiday then <count>? <dir> <weekday|day> omit …` move (CH-GL, NF, NZ-OTA — the `dateDir` offset mirrored in JS weekday indices). `Rule.conditional?/1` + `resolve_conditional/4`; `Holidays.materialise/2` and the conformance harness both tally the year's `{gregorian_days, type}` set (self excluded) and resolve against it. CH/JP/NF/NZ: 0 mismatches (11,570/11,570). 2026-09-22.

* [x] **Territory inheritance (`_days`)** — a territory inheriting another's holidays (JE/GG/IM ← GB, the French overseas ← FR, 22 in all) now carries the full inherited set plus its own, own entries overriding by rule and `false` removing an inherited one (`Build.resolve_days/2`, mirroring `Data._assign`). Also fixed the conformance harness's 3-part territory split (`BR-SP-SP`) and the Nth-weekday-in-month overflow (`5th monday in October` → 1 Nov) and date-precise `since`/`prior to YYYY-MM-DD` gating (Norfolk). 2026-09-22.

* [x] **Per-clause substitution + enable-as-move** — studied `date-holidays-parser`'s `Rule.dateIfThen` and `PostRule.disable`: each `if`/`and if`/`substitutes` clause carries its own mode with a *persistent* modifier (a leading `and` makes it and every later clause additive), and the first clause a date triggers fires and locks it. Fixed the mixed shift/add rules (Tonga) and the `substitutes … and if …` case (Japan). `disable`+`enable` is now a move — the enable is added only when a disable matches a computed date (fixes St Vincent's Carnival, whose disable date didn't match). 2026-09-22.

* [x] **Grammar coverage refinements** — Easter/orthodox `P<n>D` spans (`easter -6 P5D`); calendar durations with a time suffix (`1 Shawwal P3DT0H0M`); a weekday after the Nth weekday after a date (`monday after 3rd sunday after 09-01`, new `:nested_after_date` kind, ~30 entries); and the `and` chaining a `since` condition to a bare `if` (a move, not an added observance — Zambia). 2026-09-22.

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
