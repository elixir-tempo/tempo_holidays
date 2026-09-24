# Declarative recurrence — remaining gaps

**Status:** in progress, 2026-09-24

Current standing (2026-09-24): lunisolar, the Islamic rollover and multi-day spans, solar-term recurrences, and every gate are done. Of the 1,828 stored rules, **1,804** are declarative recurrences that match `materialise/2` exactly over 2000–2035 and each rule's gate boundary years; **24** stay `:needs_window` — 10 Vietnamese (no `[u-ca=…]` identifier names `Calendrical.Vietnamese`; blocked on Calendrical), 5 non-UTC equinox/solstice, 4 conditional, 3 non-leap-year (no filter spelling yet) and 2 `nested_after_date`. Multi-day spans shipped as an `:occurrence_duration` directive rather than the `FLL…/P<count>DN` window proposed below. The analysis below is as written on 2026-09-23, except where marked.

`Rule.recurrence/1` now emits a standalone, re-materialisable `%Tempo.Interval{}` recurrence for **1219 of 1478** distinct date-holidays rules (up from 1080 before the "Full" pass, which added islamic, easter/orthodox offsets, and relative/nested weekdays). **80** rules still return `:needs_window`, and a further **194 gate-instances** are dropped from otherwise-faithful recurrences. This document explores options to close each, and reconciles the compiler's emitted forms with the Tempo holiday cookbook.

The safety invariant throughout: `Rule.recurrence/1` and its `base_recurrence/1` helpers are the recurrence-emission path only — `materialise/2` (which the conformance corpus tests) is never touched, so any change here leaves conformance untouched. Validate every new form by materialising it against a window and comparing to `Rule.materialise/2`, across both a leap and a common year where the form crosses a month boundary.

## The five `:needs_window` families

### 1. Lunisolar (57) — traditional month numbering

The blocker (recorded decision, 2026-09-23): date-holidays writes `<month>-<leap>-<day>` in *traditional* month numbering, which drifts from a lunisolar calendar's *ordinal* months in a year carrying an intercalary month, and the traditional→ordinal mapping is year-dependent. A bare `FL<m>M<d>DN[u-ca=chinese]` selects the *ordinal* month, so it is wrong in every leap year — even though 71/71 corpus rules happen to be non-leap, a recurrence must be correct for future leap years.

Options:

* **(a) Keep `:needs_window`** (current). `materialise/2` resolves the traditional month through Calendrical's `gregorian_date_for_lunar/3` per year — correct, but not a standalone recurrence.
* **(b) A traditional-month selection in Tempo/Calendrical.** Add a selection spelling for a traditional lunar month (e.g. a `+`-tagged month, `FL8+M15D[u-ca=chinese]`) that Tempo resolves through Calendrical's traditional-month arithmetic. This is the principled fix but spans three repos (grammar in Tempo, arithmetic in Calendrical, emission here) and needs the `+` selection token, which the recorded finding notes does not parse in a selection frame today. Tempo's `plans/lunisolar-traditional-months.md` records the finding in detail.
* **(c) A `Tempo.Event.Resolver` in tempo_holidays.** Register a consumer event per lunisolar holiday (`(chinese-8-0-15)E`) that resolves the date per year by calling the same `materialise_base` lunisolar path. Emits `R/../P1Y/FL(<key>)EN`, re-materialisable and reusing the tested computation. Cost: a key encoding (the `(name)E` grammar accepts only `a-z`/`-`, so the params must encode into that charset) and a registered resolver.

Recommendation: (a) remains correct and is the current state; pursue (b) only if a *syntactic* lunar recurrence is wanted across the stack; (c) is the cheapest way to get a standalone re-materialisable member without a grammar change, and reuses tested code. Decide (b) vs (c) by whether the value is a human-readable ISO string (→ b) or just set-composability (→ c).

### 2. Islamic day-rollover and multi-day spans (12)

Two sub-cases, both currently `:needs_window`: a day *beyond* the month length (Saudi `30 Ramadan`, a sunset-convention rollover the 29/30-day month resolves), and a multi-day span (`count > 1`).

Options:

* **Multi-day span** → a span recurrence. Tempo already expresses a fixed span as `FLL<m>M<d>DN/P<count>DN` (the cookbook's "Christmas break", `~o"R/../P1Y/FLL12M25DN/P4DN"`). So a multi-day islamic holiday should be `R/../P1Y/FLL<m>M<d>DN[u-ca=islamic-*]/P<count>DN`. Cheap and clean — verify it materialises to the same span as `materialise/2`.
* **Day-rollover (day ≥ 30)** → either keep `:needs_window` (concrete `offset_calendar_holiday/5` handles the 1st-of-month-plus-offset), or emit a §12.10 window off the always-valid 1st: `FLLL<m>M1DN[u-ca=islamic-*]/P<day>D…` picking the last day. Needs a check that Tempo's window arithmetic crosses the islamic month boundary the same way `Tempo.shift/2` does.

Recommendation: do the multi-day span form first (likely closes several of the 12); leave the true day-rollover `:needs_window` unless the window form validates exactly.

### 3. Timezone equinox / solstice (5)

`(march-equinox)E` resolves through `Astro.equinox/2` in **UTC**; these holidays want a specific zone (Japan `+09:00`, Chile `America/Santiago`). When the astronomical instant is near UTC midnight the civil date differs by a day in the target zone, so `(event)E` is not reliably correct — it merely happens to match for 2026.

Options:

* **(a) Verify the blast radius first.** Materialise each of the 5 with its real timezone via `materialise/2` for every year 2000–2100 and compare to `(event)E`. If the specific zones never shift a day across that range, relax the `timezone` guard for exactly those zones. Cheap; may close all 5 with no new machinery.
* **(b) A timezone-aware event recurrence in Tempo.** Let `Tempo.Event.date/3` (and the `(name)E` recurrence) carry a zone — `FL(march-equinox)EN[Asia/Tokyo]` — resolving the astronomical instant in that zone. The general fix, but a Tempo + Astro change.

Recommendation: (a) first — it is a measurement, not a change, and likely settles whether (b) is even needed.

### 4. Solar term (4) — the `cal=nil` data-build bug (also a live crash)

The built `priv/holidays/<CC>.etf` stores `calendar: nil` for `:solar_term` rules, even though `Compiler.compile/1` sets `Calendrical.Chinese`. `materialise/2` then calls `nil.location/1` and **crashes** — a latent bug on the live `recurrences/2` / `recurrence_set/2` path, masked only because the conformance harness re-compiles fixture *strings* (which do carry the calendar) rather than reading the stored rule.

Options / steps:

* **Fix the build first (it is a real bug, not just a recurrence gap).** Trace `Tempo.Holidays.Build` → `DateHolidays.compile_days/2` and find where the solar-term calendar is lost between `Compiler.compile/1` and the serialized rule. Likely the JSON→rule path in the build differs from `Compiler.compile/1`, or the calendar is stripped before `:erlang.term_to_binary/1`. Add a regression test that loads a built solar-term rule and asserts `rule.calendar == Calendrical.Chinese`.
* **Then the recurrence.** Re-add `Calendrical.Lunisolar.solar_term_name/1` (index→name, previously prototyped and reverted; the user approved adding it to Calendrical) and emit `R/../P1Y/FL(<term-name>)EN` for the Chinese meridian, `day == 1`. The recurrence itself does not read `rule.calendar` (Tempo.Event defaults to the Chinese meridian), so it works regardless of the build bug — but the build must be fixed anyway so `materialise/2` (the validation oracle and the live path) stops crashing.

Recommendation: fix the build bug regardless of the recurrence work — it is a live crash. The recurrence is a small follow-on once `materialise/2` works as the validation oracle.

### 5. Easter / orthodox multi-day spans (2)

`count > 1` on a moveable feast. Same shape as islamic multi-day: extend the §12.10 offset window with a `P<count>DN` span, or keep `:needs_window`. Low volume; do it alongside islamic multi-day.

## Gates (resolved 2026-09-24)

The census of the stored rules (not just the fixture strings, which never carry the `active`/`disable`/`enable` metadata) found 1,161 gated rules, ~760 of them emitting a lossy or wrong recurrence. The decision: a recurrence is exact or `:needs_window`, never lossy. Each gate now has a form:

* **Year range, open or closed** → the domain, `{2017Y..}`, `{..2022Y}`, `{2020Y..2024Y}` (Tempo now closes an open range against the bound).
* **`active` window** → a year range: a once-a-year holiday is inside a date window exactly in the years its date is, decided at the window's first and last year by materialising the base.
* **Every N years** → a `P<N>Y` cadence over a domain starting at the `since` year (Tempo now steps the domain by the cadence).
* **Weekday gate** → a weekday limit, `FL5M4D{2..6}KN`.
* **Substitution** → a `Tempo.RecurrenceSet`: the date limited to the weekdays that keep it, plus one §12.10 window per clause off the date limited to the weekdays it fires on — `P8DN<t>K-1I` for "next", `-P7DN<t>K1I` for "previous". A window crossing the year lands in the right year (fixed in Tempo). Easter feasts resolve statically, their weekday being fixed.
* **`disable`/`enable` move** → the producing member excludes the year and each enabled date — and any occurrence the member keeps that year — is a one-year member.

Four Tempo defects surfaced and were fixed on the way: `(name)e` with a weekday limit raised, a domain ignored a multi-year cadence, open domain ranges would not materialise, and a window crossing the bound's year was lost or leaked. Also found: `materialise/2` relabelled a Vietnamese date as Chinese (fixed), and there is no way to name the Vietnamese calendar in a recurrence (upstream).

### As written on 2026-09-23 (superseded)

These are `{:ok, rec}` recurrences that silently drop a gate the domain cannot carry: `active` date-windows (77), open-ended `since`/`until` (61 + 18), `enable` (20), `weekday_gate` (10), `every_years` (3), `non_leap` (3), `conditional` (2). Two are Tempo-domain gaps worth their own exploration:

* **Open-ended ranges** (`{2021Y..}`) — Tempo errors on these today; supporting an open upper/lower bound resolved against the materialisation window would fold every `since`/`until` into the domain (79 rules).
* **`active` date-windows** — the domain is year-granular; a date-precise `[from, to)` window in the domain would carry these (77 rules).

`enable` (a union of a *different* date), `weekday_gate` (a filter), `every_years` (a `P<N>Y` cadence) and `conditional` (bridge/if-holiday) are genuinely not domain-expressible and stay set-algebra / concrete — see the cookbook's "Enable, weekday gates, and bridges" section. Open question worth deciding: should a rule whose gate the recurrence cannot carry return `:needs_window` (faithful, concrete) instead of a lossy `{:ok, rec}`? Today `domain_blocking_gate?/1` chooses the lossy base; revisit whether that is right for `recurrence_set`.

## Compiler ↔ cookbook consistency

Cross-reference of the form `base_recurrence/1` emits against the form Tempo's `guides/holiday-cookbook.md` documents:

| Family | Compiler emits | Cookbook documents | Consistent |
|---|---|---|---|
| Fixed | `R/../P1Y/FL2M14DN` | same shape | ✅ |
| Nth weekday | `R/../P1Y/FL9M1K1IN` | same shape | ✅ |
| Easter / orthodox base | `R/../P1Y/FL(easter)EN` | same | ✅ |
| Equinox / solstice | `R/../P1Y/FL(march-equinox)EN` | same | ✅ |
| Year gates | `{fromY..(to-1)Y}` + `^` / `e` / `o` / `l` | same format | ✅ |
| **Relative weekday** | `FLLL6M1DN/P-7DN1K1IN` (§12.10 window off the date) | `FL5M{25..31}D1K1IN` (day-range) | ❌ different form |
| **Nested weekday** | `FLLL11M4K4IN/P7DN5K-1IN` (§12.10 off the inner nth-weekday) | `FL11M{23..29}D5K1IN` (day-range) | ❌ different form |
| **Calendar (islamic/hebrew/persian/julian)** | `FL<m>M<d>DN[u-ca=…]` (selection) | `R/<yr>Y<m>M<d>D/P1Y[u-ca=…]` (anchored) | ❌ selection vs anchored |
| **Easter offsets** | `FLLL(easter)EN/P-<abs+1>DN<wd>K±1IN` (computed) | `FLLL(easter)EN/-P49DN3K1IN` (hand-picked window) | ⚠️ same family, different window |

Reconciliation options (the cookbook is the doc, the compiler is the implementation; either can move):

* **Relative / nested weekday.** The compiler's §12.10-window-off-the-anchor is *more* robust than the cookbook's day-range: taking the window off the real date lets Tempo resolve the month boundary and leap years, whereas a fixed `{25..31}D` range is leap-fragile the moment it straddles February. Recommend updating the cookbook to the §12.10 form the compiler emits (keeping a day-range example only for the fully-in-month illustration), so the doc shows the robust, actually-emitted form.
* **Calendar holidays.** The compiler emits the **selection** form (`FL<m>M<d>DN[u-ca=…]`) — confirmed canonical by the user, and it correctly yields 0/1/2 occurrences as a lunar year drifts against the Gregorian one. The cookbook shows the **anchored** form (`R/<yr>…/P1Y[u-ca=…]`), kept for its "recurs on the calendar's own year" pedagogy, but that form silently drops occurrences before its anchor year. Recommend the cookbook lead with the selection form (matching the compiler) and mention the anchored form only as the calendar-year intuition, or drop it.
* **Easter offsets.** Both forms materialise identically; the compiler computes the minimal window (`-P<abs+1>D`, first/last weekday) while the cookbook hand-picked slightly larger windows. Cosmetic — align the cookbook's window arithmetic to the compiler's formula (or note the formula) so a reader who compares them is not confused.

## Tasks

* [ ] **Verify tz equinox/solstice** across 2000–2100; relax the guard for zones that never shift, else scope a tz-aware `(event)e` in Tempo.
* [ ] **A non-leap-year filter** — a spelling beside `e`/`o`/`l`; closes 3 rules.
* [ ] **Name the Vietnamese calendar** — Calendrical registering `vietnamese` in `additional_calendars/0`; closes 10 rules with no change here.
* [ ] **Reconcile the cookbook** with the emitted forms — relative/nested weekday (§12.10), calendar (selection-first), easter windows (formula), and now lunisolar `m` and multi-day spans.

### Done

* [x] **Gates** — exact or `:needs_window`, never lossy; every gate has a form (above). 1,804 of 1,828 rules exact. 2026-09-24.
* [x] **Lunisolar** — (b) the traditional-month `m` selection, with the offset folded into the day and the eve as a backward window; 58/58. 2026-09-24.
* [x] **Multi-day span recurrences** — `count > 1` as an `:occurrence_duration` directive over any base (not `FLL…/P<count>DN`, whose nested form parses in >300 s). 2026-09-24.
* [x] **Solar-term recurrence** — `Calendrical.Lunisolar.solar_term_name/1`, emitting `(term)eN`. 2026-09-24.
* [x] **Fix the solar-term `cal=nil` build bug** — rebuilt data carries `Calendrical.Chinese`, and `materialise_base` defaults a nil meridian. 2026-09-24.
