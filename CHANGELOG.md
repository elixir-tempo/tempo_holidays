# Changelog

## [v0.1.0] — 2026-10-28

First release: public holidays for every territory in the [date-holidays](https://github.com/commenthol/date-holidays) dataset, as Tempo recurrences for any window. The [README](https://hexdocs.pm/tempo_holidays/readme.html) and the [user guide](https://hexdocs.pm/tempo_holidays/user-guide.html) describe it in full.

### Highlights

* **Every territory** — the 207 territories of date-holidays 3.38.0 and their subdivisions, with every holiday type, from a CLDR territory code or a BCP 47 locale.

* **Holidays as recurrences** — `Tempo.Holidays.holidays/2` gives a territory's holidays as a `Tempo.RecurrenceSet`, each rule read in its own calendar by `Tempo.DateRule`, and `Tempo.to_interval/2` gives the days of any window.

* **Observed days** — `:dates` gives a holiday on its substitute day, on its own date or on both; a bridge day, or a holiday moved off another, is decided against the set.

* **Holidays of your own** — `Tempo.Holidays.compile/2` reads a rule into a holiday, `add/3` and `remove/2` change a set, and `config :tempo_holidays, holidays:` changes a territory's for every request.

* **Day starts** — `Tempo.Holidays.day_start/2` begins a holiday whose day begins at sunset on the evening before, at the calendar's reference place or a location of your own.

* **School terms** — `Tempo.Holidays.SchoolTerms.NSW`, New South Wales' public school terms, holidays and development days, matching every calendar published for 2016–2030.

* **Data you can update** — the data ships in the package, and `mix tempo.holidays.update` builds a newer date-holidays release into an application.

* **Conformance** — 169,799 of the 170,818 checks of date-holidays' fixture corpus agree and none disagree; the eight rules of the Bengali calendar are not read yet.
