# Tempo.Holidays

Public holidays for every territory as [Tempo](https://hexdocs.pm/ex_tempo) recurrences, for any window. tempo_holidays reads the [date-holidays](https://github.com/commenthol/date-holidays) dataset, every holiday of every type in 207 territories and their subdivisions, with Tempo's reader of its rule grammar, so a holiday is a rule — "Christmas is the 25th of December", "Eid al-Fitr is the 1st of Shawwal" — that gives the days it falls on in any year, and meets anything else in Tempo through set algebra.

## Features

* **Every territory and subdivision** — a CLDR territory code (`:AU`) or a BCP 47 locale (`"en-US-u-sd-usca"`), with a subdivision found at whichever level the data holds it: a state, or a region within it.

* **Holidays as rules, not lists** — each holiday is a recurrence tagged with its id, name and type; `Tempo.to_interval/2` gives the days in any window, and a set operation meets a diary, a calendar or another territory's holidays.

* **Every calendar the data uses** — Islamic (Umm al-Qura), Hebrew, Persian and Julian dates, Chinese, Korean and Vietnamese lunisolar dates, solar terms, equinoxes and Easter, each holiday read in its own calendar and given as the Gregorian days it falls on.

* **Substitute days, bridges and moves** — a holiday observed on another day is given on that day, its own date or both (`:dates`); a bridge day, or a holiday moved off another, is decided against the rest of the set.

* **Holidays of your own** — `Tempo.Holidays.add/3` and `remove/2` change a set of holidays, and the application's configuration changes a territory's for every request.

* **Business days** — a territory's weekend and its holidays are Tempo values, so its business days are a period less both, counted with `Tempo.count/3`.

* **Day starts** — `Tempo.Holidays.day_start/2` begins an Islamic or Hebrew holiday the evening before, at sunset or at 18:00, at the calendar's reference place or a location of your own.

* **Conformance** — 169,799 of the 170,818 checks of date-holidays' own fixture corpus agree, none disagree, and the rest are accepted reference differences; the eight Bangladeshi rules of the Bengali calendar are not read yet.

* **Data you can update** — the data of date-holidays 3.38.0 ships in the package, and `mix tempo.holidays.update` builds a newer release into an application.

## Supported Elixir and OTP versions

tempo_holidays supports **Elixir 1.17** and later on **OTP 27** and later; OTP 26 is not supported, because Tempo requires OTP 27.

## Installation

Add `tempo_holidays` to the dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tempo_holidays, "~> 0.1"}
  ]
end
```

tempo_holidays reads a zone through the time zone database Tempo asks, [`Tempo.time_zone_database/0`](https://hexdocs.pm/ex_tempo/Tempo.html#time_zone_database/0). Tempo comes with Tz and asks it where nothing else is configured, so no configuration is needed. An application that names a database for Tempo with `config :ex_tempo, :time_zone_database` must name one that knows named zones: tempo_holidays refuses to start with `Calendar.UTCOnlyTimeZoneDatabase`.

## Quick start

A territory's holidays are a set of recurrences; the days they fall on in a year are that year's holidays:

```elixir
iex> import Tempo.Sigils
iex> {:ok, holidays} = Tempo.Holidays.holidays(:AU, include: :public)
iex> {:ok, this_year} = Tempo.to_interval(holidays, within: ~o"2026")
iex> Tempo.IntervalSet.count(this_year)
9
iex> names = Tempo.IntervalSet.map(this_year, &Tempo.metadata(&1).name)
iex> Enum.take(names, 3)
["New Year's Day", "Australia Day", "Good Friday"]
```

> *"Australia's **public holidays** are rules; **this year's** are the nine days they fall on in 2026, the first of them New Year's Day."*

A holiday of your own is a rule in the same grammar, and the business days of a period are its days less the weekend and the holidays:

```elixir
iex> import Tempo.Sigils
iex> {:ok, brazil} = Tempo.Holidays.holidays(:BR, include: [:public, :bank])
iex> {:ok, anbima} = Tempo.Holidays.remove(brazil, "Election Day")
iex> {:ok, weekends} = Tempo.weekends(:BR)
iex> {:ok, business_days} = Tempo.difference(~o"2026-01-02/2026-03-31", [weekends, anbima])
iex> Tempo.count(business_days, :day)
{:ok, 61}
```

> *"Brazil's public and bank holidays **without Election Day** are ANBIMA's calendar, and the **business days** of the first quarter from the 2nd of January are 61."*

## Documentation

* [User guide](https://hexdocs.pm/tempo_holidays/user-guide.html) — territories and subdivisions, substitute days, holiday types, other calendars, holidays of your own, business days, day starts and updating the data.

* [Conformance](https://hexdocs.pm/tempo_holidays/conformance.html) — how the data is held to date-holidays' own fixture corpus, and the differences accepted.

* [Everyday holiday questions](https://hexdocs.pm/tempo_holidays/everyday-holidays.html) — a livebook: the next school holidays, the days until Election Day, a year's holidays and those two countries share.

* [Changelog](https://hexdocs.pm/tempo_holidays/changelog.html) — release history.

Full API documentation is available on [HexDocs](https://hexdocs.pm/tempo_holidays).

## License

The code is licensed under the Apache License 2.0; see [LICENSE.md](https://github.com/elixir-tempo/tempo_holidays/blob/v0.1.0/LICENSE.md). The holiday data derives from [date-holidays](https://github.com/commenthol/date-holidays) and is redistributed under CC-BY-SA-3.0; see [NOTICE](https://github.com/elixir-tempo/tempo_holidays/blob/v0.1.0/NOTICE).
