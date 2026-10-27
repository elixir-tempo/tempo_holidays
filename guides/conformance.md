# Conformance

`tempo_holidays` is validated against [date-holidays](https://github.com/commenthol/date-holidays) itself. The upstream project ships a fixture corpus — the dates it computes for every territory across a range of years — and the conformance test checks that `Tempo.Holidays.holidays/2` gives the same Gregorian dates.

## Running it

The corpus is large, so the test is opt-in:

```bash
mix test --include conformance
```

It downloads and caches the pinned date-holidays tarball. Then, for each territory and year of the fixtures, it asks `Tempo.Holidays.holidays/2` for the territory's holidays with `dates: :both` (a substituted holiday on its own date and on its substitute, as date-holidays lists them) and converts them over the year. For each rule of the fixture, the days our occurrences of that rule start on must hold every date the fixture gives the rule, and lie among the dates the fixture gives the year. A holiday is counted in the year it starts in, as date-holidays counts it, so a period date-holidays splits at the year end, and which we hold as one period, matches its January half by the period begun in December. Results are grouped into five buckets.

## The buckets

* **matched** — our dates agree with date-holidays. Over 99% of rules.

* **unsupported** — a rule of the fixture our data does not hold. This must stay at zero; it does.

* **known unsupported** — a rule `Tempo.DateRule` does not read yet: the Bengali (revised) calendar, for which Calendrical has no implementation. These are dropped, not wrong.

* **mismatched** — a rule we read but compute the wrong dates for. This is the number that must stay at zero; it does.

* **divergent** — an *accepted* reference difference, not a defect, excluded from `mismatched`. See below.

## Why divergences are kept

Three kinds of difference are counted as divergent:

* **Islamic dates** — date-holidays derives them from a fixed 1969–2077 lookup table with a day that begins at 18:00; `tempo_holidays` derives them from Calendrical's Umm al-Qura calendar. The two agree in the large majority of cases and differ by a day in a handful, a disagreement between two determinations of the same calendar. Chasing the table would mean vendoring it and abandoning the authoritative source.

* **A rule a region removes** — date-holidays' data removes some holidays of a state from its regions (Timaru and Buller in New Zealand), but the fixtures for those regions list the state's holidays all the same. We follow the data.

* **A fixture for a subdivision the data does not define** — the fixtures for Mauritius' districts were generated from an older release of the data, which the current one no longer holds.

The figures for each bucket are printed when the test runs.
