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
* Easter / orthodox relative.
* Observed-date substitution `if <weekdays> then (next|previous) <weekday>`, incl. the `and if …` connector and chained clauses.

**Not yet handled** (skipped as `{:error, {:unsupported, rule}}`):

* Lunar/other calendars: Hijra, Hebrew, Chinese (lunar & solar), Bengali, Persian — via Calendrical.
* Equinox / solstice / solar terms — via Astro.
* `<weekday> before|after <date>` (`monday before 06-01` = US Memorial Day).
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

* [ ] `mix tempo.holidays.update`: fetch the bundle over `:httpc` (verified TLS via `:public_key.cacerts_get/0`), parse, run each country's `days` through `compile_days/2`, write `priv/holidays/<CC>.json`; `Data` then loads from there.

* [ ] Resolve `_name` references against `names.yaml`/`names.json` so days keyed only by `_name` get real names.

* [ ] Grow the compiler tiers (see "Not yet handled"), most-common first — `<weekday> before|after <date>` (US Memorial) and lunar calendars lead.
