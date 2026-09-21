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
* Easter / orthodox relative.
* Observed-date substitution `if <weekdays> then (next|previous) <weekday>`, incl. the `and if …` connector and chained clauses.

**Not yet handled** (skipped as `{:error, {:unsupported, rule}}`):

* Lunar/other calendars: Hijra, Hebrew, Chinese (lunar & solar), Bengali, Persian — via Calendrical.
* Equinox / solstice / solar terms — via Astro.
* `<weekday> before|after <Month>` (start-of-month anchor) and the nested form `<weekday> after <Nth weekday in Month>` (Black Friday, Election Day) — only the `<MM-DD>` anchor is handled so far.
* Fixed-date-at-start-of-month; time-of-day (`10-31 18:00`) and non-24h durations.
* Additional-day / "observe **as well as** a substitute" (AU Christmas/Boxing).
* "Change weekday if date already falls on a holiday" (the cascade / collision).
* Year filters: `since <year>`, in/odd/even years, active periods; `disable`/`enable`; `substitutes …` prefix; bridge days; state/region disabling.

## `mix tempo.holidays.update` design

* **Source** (decided): the compiled `data/holidays.json` bundle from a **pinned** date-holidays version via jsDelivr (`https://cdn.jsdelivr.net/npm/date-holidays@3/data/holidays.json`). It keeps the rule strings as `days` keys — verified — so it parses with stdlib `:json` (Erlang, per the `~> 1.17` floor) and fetches with stdlib `:httpc`: **no new dependency**, matching the ecosystem's stdlib-JSON stance. The per-country YAML path (needing `yaml_elixir`) is rejected on that basis.
* **Compile**: map each `days` entry `{rule, meta}` to a `%Holiday{name, type, rule}` — name from `meta.name.<lang>` or the `_name` → `names.yaml` lookup, type from `meta.type`. Compile the rule string via `Compiler`; drop unsupported ones (partial support is correct for partial coverage).
* **Write**: `priv/holidays/<CC>.json` in our own compact shape, bundled in the package and loaded by `Data`.

## Tasks

* [x] Source decided: jsDelivr `date-holidays@3` `holidays.json` bundle, stdlib `:json` + `:httpc`, no new dep.

* [x] `Tempo.Holidays.DateHolidays.compile_days/2` — maps a country's `days` entries to `%Holiday{}`, resolving name (inline `name.<lang>` → `_name` → rule) and type, dropping unsupported rules.

* [x] `mix tempo.holidays.update`: fetches the bundle via Localize's hardened HTTP client, parses with `:json`, runs each country's `days` through `compile_days/2`, and writes `priv/holidays/<CC>.etf`. `:json` on OTP 26 comes from json_polyfill (a dev/test dep here; consumers add it to run the task). ETF means loading needs no JSON on any release.

* [ ] `Data.for_territory/1` loads `priv/holidays/<CC>.etf` when present, falling back to the inline seed — so the downloaded data is actually used.

* [ ] States/regions: the task compiles only the country-level `days`; sub-territory `days` (`US-AL`, …) are still to come.

* [x] Resolve `_name` references against the bundle's top-level `names` table — days keyed only by `_name` get real, localized names (~50 languages) instead of the reference string.

* [ ] Grow the compiler tiers (see "Not yet handled"), most-common first — lunar calendars (Islamic first: `30 Ramadan P4D`) and the nested/Month-anchor relative weekdays (Black Friday, Election Day) lead.

### Calendar-native output

Lunar / non-Gregorian holidays are returned **in their own calendar** — an
Islamic holiday materialises to an `[u-ca=islamic]` Tempo value, not a
Gregorian conversion. Tempo is calendar-aware, so there is no need to convert
output to Gregorian; the caller converts if they want to. This also sidesteps
the "an Islamic date falls 0, 1 or 2 times in a Gregorian year" problem — the
rule is projected onto the corresponding year of its own calendar.
