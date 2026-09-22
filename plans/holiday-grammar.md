# Holidays as a Tempo grammar

**Status:** draft, 2026-09-22

The long-term objective behind `tempo_holidays` is not a lookup table of dates. It is to express a holiday as a **Tempo interval-set value**, defined in Tempo's own grammar, so that a holiday composes with any other Tempo value through set algebra. The motivating query is `my_free_time ∩ holidays_in_my_region`, and its relatives (`workday − holidays`, "bookable slots at least an hour long in the mutual free time"). Today a holiday is an opaque [date-holidays](https://github.com/commenthol/date-holidays) rule string that we compile into a private `%Rule{}` and materialise onto a year. The aim is to lift the *definition* into Tempo grammar, extended as compatibly as possible, leaning on ISO 8601-2 and IXDTF.

This document categorises every rule family we compile, says for each whether it is declarable in Tempo today or needs a grammar / algebra extension, gives the grounded syntax, and proposes a phased path. The Tempo capabilities below are verified against the source at `~/Development/tempo`.

## What already holds — more than expected

Four foundations are already in place:

* **Recurrences are first-class.** `%Tempo.Interval{}` carries a `recurrence` (`:infinity`, a count, or until) and a `repeat_rule` holding a `{:selection, …}`. A year-free "floating" holiday *is* a recurrence: `~o"R/../P1Y/FL11M4K4IN"` is "the 4th Thursday of November, every year" (US Thanksgiving); `~o"R/../P1Y/FL12M25DN"` is a recurring 25 December. Tempo also ships an **RRULE** parser (`Tempo.RRule.parse/2`, full `BYDAY`/`BYMONTH`/`BYSETPOS`/`WKST`/`INTERVAL`/`COUNT`/`UNTIL`), a **Cron** parser, and **iCal** round-trip (`Tempo.ICal`), all compiling to the same selection AST — and `Tempo.to_rrule/1` / `to_iso8601/1` encode back. This resolves what looked like the first blocker: the year-free recurring-selection form already exists.

* **Materialisation yields interval sets.** `Tempo.to_interval/2` with `bound:` expands a recurrence onto a span; `Tempo.select/2` returns a `%Tempo.IntervalSet{}`. `Tempo.Holidays.materialise/3` already returns half-open `[from, to)` intervals and coalesces a holiday's occurrences.

* **The set algebra is rich and complete for the query.** `Tempo.union/intersection/difference/symmetric_difference/complement`, the set predicates `disjoint?/overlaps?/subset?/contains?/equal?`, and on `IntervalSet` itself `to_list/filter/map/duration` — and crucially **`IntervalSet.slots/3`**, which chops a set into fixed-duration bookable slots. The motivating query is `Tempo.difference(work, busy) |> … |> IntervalSet.slots(~o"PT1H")` today, once holidays are a set.

* **The observance and calendar machinery exists imperatively.** `Tempo.next_working_day/2`, `previous_working_day/2`, `nearest_working_day/2`, `add_working_days/3`, `workday?/2`, `weekend?/2` (territory-driven via `Tempo.Territory`), and `Tempo.shift/3` with a `skipping:` option, are exactly the primitives observed-date substitution needs. Calendars wired include gregorian, julian, hebrew, persian, indian, buddhist, roc, chinese, korean/dangi, an islamic family, coptic/ethiopic, and — notably — **ecclesiastical** and **nrf**.

So the gap is narrower than "build a grammar": it is (1) a declarative *surface* for a few operators, (2) wiring existing internal helpers (Easter, working-day) into that surface, and (3) packaging holidays as sets so the algebra applies.

## Categorisation by rule family

### A — declarable in Tempo today

A holiday here *is* a recurrence sigil; the selection markers are `L…N` (wrapper), `nI` (nth instance of a weekday), `nK` (day-of-week, 1=Mon…7=Sun), `nM`/`nD`/`nO`/`nW` (month/day/ordinal-day/week), `nV` (BYSETPOS — a Tempo extension), inside a `/F…` repeat frame.

| Rule family | Example | Tempo value |
|---|---|---|
| Fixed date (+ `PnD` span) | `12-25`, `30 Ramadan P4D` | `~o"R/../P1Y/FL12M25DN"`; the span is the interval width |
| Weekday-in-month | `4th Thursday in November`, `last Monday in May` | `~o"R/../P1Y/FL11M4I4KN"`, `~o"R/../P1Y/FL5M-1I1KN"` |
| Last-weekday-of-month via setpos | `last weekday of month` | `~o"R/../P1M/FL{1..5}K-1VN"` |
| Calendar date | `1 Muharram`, `14 AdarII` | `~o"1447Y1M1D[u-ca=islamic-umalqura]"` (as a recurrence over years) |
| Month start | `February` = `02-01` | fixed date |

Nothing new is required beyond settling the canonical recurring form (`R/../P1Y/FL…N`) as the holiday value.

### B — small, additive selection operators

Declarative, no algebra change. `every N years` already maps to a recurrence **interval** (`~o"R/../P2Y/…"`), and BYSETPOS (`nV`) already exists. The genuine additions:

| Rule family | Example | What's needed |
|---|---|---|
| Nearest/relative weekday | `Monday before 06-01`, `Friday after 11-11` | a `before`/`after <weekday>` selection operator on a date anchor (imperative `next_working_day`-style logic exists; it needs a *declarative selection* form) |
| Day offset | `1 day before <base> P5D` | an offset applied to a selection (`Tempo.shift` exists; needs a grammar form) |
| Year parity / leap filter | `in even years`, `in leap years` | a year predicate on the recurrence (no existing filter; `every N years` covers only the interval case) |
| Weekday gate | `on friday`, `not on sunday` | a keep/drop predicate on the occurrence's weekday (expressible as `IntervalSet.filter/2` today; a declarative form is the addition) |

### C — computed recurrences (wire existing helpers)

Not pure grammar: the date is algorithmic. Two of the three have internal support to build on.

| Rule family | Example | State |
|---|---|---|
| Easter / orthodox | `easter -2`, `orthodox 49` | `Tempo.Event.Easter.gregorian_easter/2` **exists** but is `@moduledoc false`, unwired to any sigil, and `orthodox_easter/1` is an empty stub; the ecclesiastical calendar is wired. Needs a public named-recurrence surface + orthodox completion. |
| Equinox / solstice | `march equinox in +09:00` | `Astro.equinox/2`,`Astro.solstice/2` are used **only** as season-code boundaries; there is **no** way to select the equinox as a first-class value. A genuine new "computed selection" kind. |
| Solar term | `chinese 5-01 solarterm` | resolved via `Calendrical.Lunisolar`; same "computed selection" kind. |

The extension is one mechanism — a *computed selection* whose resolution calls a function (Calendrical/Astro) — used by all three. IXDTF `[event=march-equinox]` is a candidate string carrier.

### D — transformation (a shift over a recurrence)

Observed-date substitution is a *map* over the base recurrence: "if the date lands on a trigger weekday, move / add / replace it." The imperative primitives already exist (`next_working_day/2`, `shift/3` with `skipping:`); what is missing is a **declarative shift operator** so a substituted holiday is a Tempo value, not a function call.

| Rule family | Example | What's needed |
|---|---|---|
| Observed-date substitution | `01-01 and if saturday,sunday then next monday` | a `substitute`/`shift` clause `{trigger, direction, target, mode}` applied as `IntervalSet.map/2` |
| `substitutes` | `substitutes 12-26 …` | the same map with a replace mode |

### E — interval-set and cross-holiday (the core objective)

These families **are already set algebra**, and every operation they need exists.

| Rule family | Set meaning | Tempo op that serves it |
|---|---|---|
| `active` window | `recurrence ∩ [from, to)` | `Tempo.intersection/2` |
| `disable` | `recurrence \ {dates}` | `Tempo.difference/2` |
| `enable` | `… ∪ {dates}` | `Tempo.union/2` |
| Bridge day | keep base iff `on ⊆ holiday_set` | `Tempo.subset?/2` |
| `if is holiday then …` | shift base iff `base ∈ holiday_set` | `Tempo.contains?/2` + the D shift |

The `active`/`disable`/`enable` trio needs **no new algebra** — a gated holiday is `intersection`/`difference`/`union` of the base recurrence with literal windows and date sets. The bridge / if-holiday families need one new thing: the year's holiday set as a **value** the rule can be conditioned on — and an `IntervalSet` *is* that value, with `subset?`/`contains?` already the predicates. This is the point at which holidays become compositional with each other, which is the same compositionality the motivating query wants between holidays and free time.

## Leaning on IXDTF

IXDTF is the compatibility lever, and Tempo already parses **arbitrary `[key=value]` tags** into `extended.tags`, with the critical `!` flag failing the parse on an unrecognised critical suffix. Its roles here:

* **Calendar and zone** — already used (`[u-ca=islamic-umalqura]`; the `:day_start` projection emits a zone).

* **Named events** — a computed recurrence (C) can be carried as `[event=march-equinox]`, keeping the string a valid annotated Tempo value.

* **Not for transformations** — substitution and gates (D, E) are operations *over* a value, not annotations *of* one; forcing them into `[key=value]` yields strings only Tempo can read, defeating interop. They belong in the selection grammar and the set algebra.

One known gap to close if we carry annotations in strings: **`Tempo.to_iso8601/1` does not currently re-emit the `:extended` suffixes** (calendar/zone/tags), so an annotated value does not round-trip through its own string form yet.

## Proposed path

Additive throughout — every phase leaves existing Tempo values valid and adds capability.

1. **Package holidays as interval sets (A + E-gates).** Have `Tempo.Holidays` hand back `IntervalSet`s and re-express `active`/`disable`/`enable` as the `∩ / \ / ∪` they already are. With `IntervalSet.slots/3`, this makes `free_time ∩ holidays` and the bookable-slots query work for categories A and the gate part of E — **no grammar change, only packaging and a set-algebra rewrite**. This is the phase that delivers the headline use case.

2. **Additive selection operators (B).** Add relative-weekday, day-offset, and year-parity/leap operators to Tempo's selection grammar (interval and BYSETPOS already exist); migrate the corresponding compiler tiers to emit them.

3. **Computed recurrences (C).** Add one "computed selection" mechanism and wire Easter (complete `orthodox`), equinox/solstice, and solar term into it.

4. **Substitution as a shift transform (D).** Add a declarative shift/substitute operator over the working-day primitives.

5. **Cross-holiday predicates (E-conditional).** Condition a rule on a supplied holiday `IntervalSet` via `subset?`/`contains?`, replacing the private two-pass with grammar-level set predicates.

At the end, a holiday is a Tempo recurrence from grammar (A–D) closed under the set algebra (E); `tempo_holidays` compiles date-holidays strings *into* that grammar, and the private `%Rule{}` becomes an implementation detail or disappears. (Tempo's own `guides/holidays.md` documents an iCal-ingest-into-`IntervalSet` path today; this makes the *computed* holidays first-class alongside it.)

## Open questions

* Which of B is **ISO 8601-2 conformant** versus a Tempo extension (as `nV`/`nQ` already are). "Nearest weekday" and parity filters likely exceed ISO 8601-2; where carried in a string they must be flagged so a plain-ISO consumer is not misled.

* Whether **computed selections** (C) live in the sigil grammar or only as constructor functions with an IXDTF string form — bounded by the `to_iso8601` re-emit gap above.

* Whether the **holiday set** in E is caller-supplied (an `IntervalSet` argument, which the current two-pass argues for and which keeps the grammar pure) or resolved from a registry.

## Definition of done for every addition

* Each new selection operator and computed selection is covered by **`Tempo.explain/1`** (`Tempo.Explain`) — it must render the new form as prose, not fall through.

* Each extends ISO 8601 by **only the symbols we use**, documented clearly in the Tempo conformance guide as a Tempo extension (as `nV`/`nQ` already are).

* **End goal:** once the operators land, re-state every holiday rule we compile in the new extended-ISO-8601 floating-recurrence form where possible, so `tempo_holidays` compiles into Tempo grammar rather than a private `%Rule{}`.

## Tasks

* [ ] Phase 1: `Tempo.Holidays` returns `IntervalSet`s; re-express `active`/`disable`/`enable` as set algebra; demonstrate `free_time ∩ holidays` and `IntervalSet.slots/3`.

* [ ] Phase 2: additive selection operators (relative weekday, offset, parity/leap) in Tempo; migrate the compiler tiers.

* [ ] Phase 3: one computed-selection mechanism; wire Easter (finish `orthodox`), equinox/solstice, solar term.

* [ ] Phase 4: substitution as a declarative shift transform over the working-day primitives.

* [ ] Phase 5: cross-holiday predicates over a supplied holiday `IntervalSet`.

* [ ] Close the `Tempo.to_iso8601/1` IXDTF re-emit gap if annotations are carried in string form (Tempo-side).
