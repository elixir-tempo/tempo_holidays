# date-holidays data format

**Status:** reference, 2026-09-21

The source dataset is [commenthol/date-holidays](https://github.com/commenthol/date-holidays),
CC-BY-SA-3.0. Its format is defined by
[`docs/specification.md`](https://github.com/commenthol/date-holidays/blob/master/docs/specification.md)
(spec v2.2.0) — the authority for the rule grammar, not the sample files.

## Structure

Per-country YAML under `data/countries/<CC>.yaml`, plus a shared
`data/names.yaml`. A compiled bundle `data/holidays.json` is generated from
them.

```yaml
holidays:
  <CC>:                 # IANA country code
    names: {en: …}
    dayoff: sunday      # default weekend day
    langs: [en, …]
    zones: [America/New_York, …]
    days:
      <rule string>:    # the grammar below — the map KEY
        name: {en: …, es: …}   # or `_name: <ref>` into names.yaml
        type: public|bank|school|optional|observance   # default public
        substitute: true       # appends "(substitute day)" to the name
        disable: ['YYYY-MM-DD'] # and `enable:` to move
        note: …
    states:  { <state>: { names, days, regions } }
    regions: { <region>: { names, days } }
```

## Grammar tiers (spec §"Grammar for day rules")

**Handled by `Tempo.Holidays.Compiler` today** — the common cases:

* Fixed date `MM-DD`.
* Weekday-in-month `<ordinal> <weekday> in <Month>` (`first`…`fifth`, `last`).
* Relative weekday `<weekday> before|after <MM-DD>` (US Memorial `monday before 06-01`).
* Islamic (Hijri) `<day> <month> [P<n>D]`, returned in the `[u-ca=islamic-civil]` calendar.
* Easter / orthodox relative.
* Observed-date substitution `if <weekdays> then (next|previous) <weekday>`, incl. the `and if …` connector and chained clauses.

**Not yet handled** (skipped as `{:error, {:unsupported, rule}}`):

* Other calendars: Hebrew, Chinese (lunar & solar), Bengali, Persian — via Calendrical, each returned in its own calendar like the Islamic tier. (Islamic/Hijri is done.)
* Equinox / solstice / solar terms — via Astro.
* `<weekday> before|after <Month>` (start-of-month anchor) and the nested form `<weekday> after <Nth weekday in Month>` (Black Friday, Election Day) — only the `<MM-DD>` anchor is handled so far.
* Fixed-date-at-start-of-month; time-of-day (`10-31 18:00`) and non-24h durations.
* Additional-day / "observe **as well as** a substitute" (AU Christmas/Boxing).
* "Change weekday if date already falls on a holiday" (the cascade / collision).
* Year filters: `since <year>` (why US Juneteenth is absent — it is a 2021-onward holiday), in/odd/even years, active periods; `disable`/`enable`; `substitutes …` prefix; bridge days; state/region disabling.

## Build pipeline

* **Source** (decided): the compiled `holidays.json` bundle from an **exactly pinned** date-holidays version via jsDelivr (`date-holidays@3.37.0`). An exact pin — not the `@3` range — makes the build reproducible, so the source need not be vendored in git. It keeps rule strings as `days` keys, so it parses with stdlib `:json` (json_polyfill supplies it on OTP 26) and fetches with `:httpc` via Localize's hardened HTTP client — **no new dependency**. The per-country YAML path (needing `yaml_elixir`) is rejected on that basis.
* **Generate at build time**: the `:holidays` Mix compiler (`Tempo.Holidays.Build`) runs after the Elixir compiler and, when the pinned data is not already on disk, downloads the bundle and compiles every territory's `days` to `%Holiday{}`, writing `priv/holidays/<CC>.etf`. It is a no-op once built, so warm builds and every consumer build (the etf ships in the package) touch no network.
* **No seed**: the compiled bundle is the only source; there is no hand-written fallback data.

## Tasks

* [x] Source decided: jsDelivr `date-holidays@3.37.0` `holidays.json` bundle (exact pin), stdlib `:json` + `:httpc`, no new dep, no vendored source.

* [x] `Tempo.Holidays.DateHolidays.compile_days/2` — maps a country's `days` entries to `%Holiday{}`, resolving name (inline `name.<lang>` → `_name` → rule) and type, dropping unsupported rules and `false` (disabled) entries.

* [x] Build at compile time: the `:holidays` Mix compiler (`Tempo.Holidays.Build`) downloads the pinned bundle and writes `priv/holidays/<CC>.etf` for every territory; `mix tempo.holidays.update` forces a refresh. ETF means loading needs no JSON on any OTP.

* [x] `Data.for_territory/1` loads `priv/holidays/<CC>.etf` (CLDR code as atom or string); `territories/0` lists them. No seed fallback.

* [ ] States/regions: the build compiles only the country-level `days`; sub-territory `days` (`US-AL`, …) are still to come — and would restore AU King's Birthday.

* [x] Resolve `_name` references against the bundle's top-level `names` table — days keyed only by `_name` get real, localized names (~50 languages) instead of the reference string.

* [x] Islamic (Hijri) tier — compiled, and projected onto a Gregorian year via `Calendrical.dates_in_gregorian_year/3`, returned in `[u-ca=islamic-civil]`. A lunar date can fall twice in one Gregorian year, so `materialise/2` returns a list of occurrences.

* [ ] Grow the remaining compiler tiers (see "Not yet handled"), most-common first — the nested / Month-anchor relative weekdays (Black Friday, Election Day) and the other lunar calendars (Hebrew, Chinese, Persian, Bengali) lead.

### Calendar-native output

Lunar / non-Gregorian holidays are returned **in their own calendar** — an
Islamic holiday materialises to an `[u-ca=islamic-civil]` Tempo value, not a
Gregorian conversion. Tempo is calendar-aware, so there is no need to convert
output to Gregorian; the caller converts if they want to.

`materialise/2` still takes a **Gregorian** year — that is the year a caller
asks a country's holidays for. Calendrical's
`calendar.dates_in_gregorian_year(g_year, month, day)` bridges the two: it
returns the calendar-native date(s) of a given month-and-day that fall in that
Gregorian year — zero, one, or (because a lunar year is ~11 days shorter) two.
So `materialise/2` returns a **list** of occurrences, and the "an Islamic date
falls 0, 1 or 2 times in a Gregorian year" case is expressed directly rather
than sidestepped: Eid al-Fitr genuinely appears twice in the year 2000.
