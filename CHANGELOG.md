# Changelog

## [v0.3.0] — 2026-11-01

### Added

* Bangladesh's national days written in the Bengali calendar (Victory Day, Independence Day, Pohela Boishakh and five more) are read, through Tempo 2.4 and Calendrical 2.5's Bangla calendar; every rule of the dataset is now read, and 169,919 of the 170,818 conformance checks agree.

### Changed

* Requires ex_tempo 2.4, Calendrical 2.5 and Localize 1.6.

## [v0.2.0] — 2026-11-01

### Breaking changes

* `Tempo.Holidays.day_start/1` replaces `day_start/2`: a day start is its calendar's, sunset at its own place (Mecca, Jerusalem), through `Tempo.day_start/1`, so `:evening`, `:sunset` and located day starts are gone, with `Tempo.Holidays.DayStart` and the optional `tz_world`.

### Added

* Requires ex_tempo 2.3 and Calendrical 2.4.

* Holiday names in the request's locale (`Tempo.Holidays.Names`): the dataset's in 77 languages, a Gettext catalog of MF2 messages (`Tempo.Holidays.Gettext`), then English, then the territory's own languages.

* `mix tempo.holidays.gettext` writes the catalog's template, `priv/gettext/holidays.pot`; `config :tempo_holidays, gettext: …` names an application's own backend. `Tempo.Holidays.Data.languages/1` gives a territory's own languages.

### Changed

* A holiday's `:name` is in the language of the `:locale` option, else of `Localize.get_locale/0`: an `en-US` process reads US names (`"Labor Day"`) where it read the dataset's generic English.

* A removal configured by name removes a holiday by its name in any language the dataset gives.

### Fixed

* A Hebrew holiday written with a traditional month is placed by its day start, where it was left a whole day without a word.

* A holiday the dataset names in no English reads in the territory's language (Glarus' `"Näfelser Fahrt"`), where its name was its rule; Czech, Japanese, Georgian, Latin and Norwegian names are kept under CLDR's codes.

* A territory code of other than two letters never names a file to read, where `Tempo.Holidays.Data.for_territory/2` read a path built from any string.

## [v0.1.0] — 2026-10-28

First release: public holidays for every territory in the [date-holidays](https://github.com/commenthol/date-holidays) dataset, as Tempo recurrences for any window. The [README](https://hexdocs.pm/tempo_holidays/readme.html) and the [user guide](https://hexdocs.pm/tempo_holidays/user-guide.html) describe it in full.

### Highlights

* **Every territory** — the 207 territories of date-holidays 3.38.0 and their subdivisions, with every holiday type, from a CLDR territory code or a BCP 47 locale.

* **Holidays as recurrences** — `Tempo.Holidays.holidays/2` gives a territory's holidays as a `Tempo.RecurrenceSet`, each rule read in its own calendar by `Tempo.DateRule`, and `Tempo.to_interval/2` gives the days of any window.

* **Observed days** — `:dates` gives a holiday on its substitute day, on its own date or on both; a bridge day, or a holiday moved off another, is decided against the set.

* **Holidays of your own** — `Tempo.Holidays.compile/2` reads a rule into a holiday, `add/3` and `remove/2` change a set, and `config :tempo_holidays, holidays:` changes a territory's for every request.

* **Day starts** — `day_start/2` (since 0.2.0 `day_start/1`) begins a holiday whose day begins at sunset on the evening before, at the calendar's reference place or a location of your own.

* **School terms** — `Tempo.Holidays.SchoolTerms.NSW`, New South Wales' public school terms, holidays and development days, matching every calendar published for 2016–2030.

* **Data you can update** — the data ships in the package, and `mix tempo.holidays.update` builds a newer date-holidays release into an application.

* **Conformance** — 169,799 of the 170,818 checks of date-holidays' fixture corpus agree and none disagree; the eight rules of the Bengali calendar are not read yet.
