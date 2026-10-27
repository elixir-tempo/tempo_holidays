# Changelog

## [v0.1.0] — unreleased

First release. Public holidays for every territory in the [date-holidays](https://github.com/commenthol/date-holidays) dataset, as Tempo recurrences for any window.

* Every holiday type, resolved from a CLDR territory code or a BCP 47 locale, with a `:subdivision` found at whichever level the data holds it (an unknown one is an error) and territory inheritance.

* The full date-holidays grammar — fixed and weekday dates, Islamic/Hebrew/Persian/Julian, Chinese/Korean/Vietnamese lunisolar, solar-term and equinox/solstice dates, observed-date substitution, occurrence gates, and inter-holiday bridge days.

* The data is compiled from date-holidays 3.38.0 and ships in the package. `mix tempo.holidays.update --version` builds it from another release into the directory an application names with `config :tempo_holidays, data_dir: {:my_app, "holidays"}`, which the library then reads, and lists any rule it leaves out; `Tempo.Holidays.Data.version/0` says which release is loaded.

* `Tempo.Holidays.holidays/2` — a territory's holidays as a `Tempo.RecurrenceSet`, one member per holiday tagged with its `:id`, `:name` and `:type`, and with the `:calendar` of a rule of another calendar than the Gregorian, selected by type with `:include` and `:exclude`, which `Tempo.to_interval/2` converts to a window's holidays. All 1,828 of the dataset's rules are declarative recurrences, the bridge and `if`-holiday rules as conditional members.

* `:dates` gives a holiday observed on a substitute day on that day (`:substitute`, the default), on its own date (`:gazetted`) or on both (`:both`). A period date-holidays splits over the year end is one member, and a dated period keeps its length.

* `Tempo.Holidays.compile/2` — a holiday from a rule in the date-holidays grammar, tagged as the dataset's holidays are (`:id`, `:name`, `:type` and metadata of your own).

* `Tempo.Holidays.add/3` and `remove/2` — a holiday of your own added to a set of holidays from a rule, or holidays removed by id or name. `config :tempo_holidays, holidays:` does the same for every request with `:add` and `:remove`, keyed by territory or subdivision.

* Each rule is read by Tempo's `Tempo.DateRule` when a territory's holidays are first asked for, and kept for the life of the VM per territory, subdivision and `:dates` reading.

* `Tempo.Holidays.day_start/2` projects the occurrences of a holiday whose day begins at sunset, told by the `:calendar` in its metadata, onto the evening before, at sunset or 18:00, at the calendar's reference place or a location of your own.

* `Tempo.Holidays.SchoolTerms.NSW` — New South Wales public school terms, holidays and development days for both divisions, from the rules the Department's calendars follow, matching every calendar it has published for 2016–2030.

* The livebook `everyday-holidays.livemd` answers everyday holiday questions — the next school holidays, the days until Election Day, a year's holidays and those two countries share — through `holidays/2`.

* Requires a time zone database, as Tempo does for its zone work (`config :elixir, :time_zone_database, Tz.TimeZoneDatabase`); the application refuses to start without one.

* Over 99% conformant with the date-holidays fixture corpus (`mix test --include conformance`).
