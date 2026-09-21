# Vietnamese lunisolar calendar

**Status:** planning, 2026-09-22

date-holidays expresses Vietnamese holidays (Tết Nguyên Đán and the rest, ~10
distinct rules for `VN`) with a `vietnamese <month>-<leap>-<day>` rule in the
same traditional lunar-month shape as `chinese …` and `korean …`. tempo_holidays
supports the Chinese and Korean lunisolar tiers by delegating to
`Calendrical.Chinese` / `Calendrical.Korean`, but **there is no
`Calendrical.Vietnamese`**, so the Vietnamese rules currently compile to
`{:error, :unsupported}` and are dropped.

## Why this is an upstream (Calendrical) task, not a Tempo helper

The Vietnamese lunar calendar is the Chinese lunisolar system computed at the
**UTC+7 meridian** (Indochina Time) rather than China's UTC+8. Because the new
moon and solar term that fix a month boundary can fall on different civil days
either side of that one-hour meridian difference, Tết occasionally lands a day
off Chinese New Year (e.g. 1985, 2007). So it is a real, distinct calendar, not
an alias of Chinese.

Per the project rule *"never work around a library deficiency with a helper —
call it out first"*, projecting Vietnamese dates inside tempo_holidays (reaching
into `Calendrical.Lunisolar.gregorian_date_for_lunar/5` with a hand-built
Vietnam location) would duplicate calendar logic that belongs in Calendrical and
would drift from it. The calendar belongs upstream.

## The machinery already exists in Calendrical

`Calendrical.Chinese` and `Calendrical.Korean` are thin modules over a shared
lunisolar builder; the low-level `Calendrical.Lunisolar.gregorian_date_for_lunar/5`
already takes an epoch and a `location_fun`. `Calendrical.Chinese.location/1`
returns `{lat, long, elevation, offset}` with `offset = 8/24`;
`Calendrical.Korean.location/1` uses a different meridian. A `Calendrical.Vietnamese`
would be the same builder with a Hanoi location (`long ≈ 105.85`, `offset = 7/24`)
and the Chinese epoch — a small module mirroring `Calendrical.Korean`.

## Decision needed

* **Preferred:** add `Calendrical.Vietnamese` (Calendar behaviour, CLDR type —
  Vietnam has no distinct BCP 47 `u-ca`, so likely reuse `chinese` or expose a
  private tag) upstream, then add a `"vietnamese"` entry to the tempo_holidays
  lunisolar compiler map — one line, exactly like Korean. The checkouts are
  unlocked for Calendrical fixes.
* **Fallback (not recommended):** approximate Vietnamese with `Calendrical.Chinese`
  in tempo_holidays, accepting a wrong day in the handful of years where the
  meridian shifts the boundary, and add a TODO to remove it once the upstream
  calendar lands.

## Tasks

* [ ] Confirm with Calendrical's maintainer (the user) whether to add
  `Calendrical.Vietnamese` now or defer.
* [ ] If yes: add the module (mirror `Calendrical.Korean`, Hanoi location, UTC+7),
  with `gregorian_date_for_lunar/3` and `dates_in_gregorian_year/3`, plus tests
  against known Tết dates (2007-02-17 differs from Chinese New Year 2007-02-18).
* [ ] Add `"vietnamese" => Calendrical.Vietnamese` to the tempo_holidays
  lunisolar compiler map and re-run the VN conformance slice.
