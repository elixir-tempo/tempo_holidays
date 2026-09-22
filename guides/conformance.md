# Conformance

`tempo_holidays` is validated against [date-holidays](https://github.com/commenthol/date-holidays) itself. The upstream project ships a fixture corpus — the dates it computes for every territory across a range of years — and the conformance test checks that our compiled-and-materialised rules produce the same Gregorian dates.

## Running it

The corpus is large, so the test is opt-in:

```bash
mix test --include conformance
```

It downloads and caches the pinned date-holidays tarball, then, for each fixture rule, checks that our dates sit inside the fixture's date-set for that territory-year. Results are grouped into four buckets.

## The buckets

* **matched** — our dates agree with date-holidays. Over 99% of rules.

* **unsupported** — a rule whose grammar or calendar we do not yet compile (currently the Bengali calendar, for which Calendrical has no implementation). These are dropped, not wrong.

* **mismatched** — a rule we compile but compute the wrong date for. This is the number that must stay at zero; it does.

* **divergent** — an *accepted* reference difference, not a defect, excluded from `mismatched`. These are Islamic dates where date-holidays' embedded Hijri table places a month's first day one day either side of Calendrical's Umm al-Qura. Calendrical is authoritative, so we keep our date and record the difference.

## Why divergences are kept

date-holidays derives Islamic dates from a fixed 1969–2077 lookup table; `tempo_holidays` derives them from Calendrical's Umm al-Qura calendar. The two agree in the large majority of cases and differ by a day in a handful, a genuine disagreement between two determinations of the same calendar. Chasing the table would mean vendoring it and abandoning the authoritative source, so these are reported as `divergent` rather than forced to match.
