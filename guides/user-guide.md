# User guide

`tempo_holidays` turns the [date-holidays](https://github.com/commenthol/date-holidays) dataset into [Tempo](https://hexdocs.pm/ex_tempo) recurrences: a holiday is a *rule* — "Christmas is the 25th of December", "Eid al-Fitr is the 1st of Shawwal" — that gives the intervals it occupies in any window.

## Getting a territory's holidays

`Tempo.Holidays.holidays/2` returns a territory's holidays as a `Tempo.RecurrenceSet`: one member per holiday, tagged with its `:id` (the date-holidays rule, unique where names repeat), `:name` and `:type`. `Tempo.to_interval/2` converts them to the holidays in a window — a year, or any interval — as a set of occurrences, earliest first, each tagged the same way.

```elixir
import Tempo.Sigils

{:ok, holidays} = Tempo.Holidays.holidays(:AU)
{:ok, this_year} = Tempo.to_interval(holidays, within: ~o"2026")

new_year = Tempo.IntervalSet.first(this_year)
Tempo.metadata(new_year)
# => %{id: "01-01 and if saturday,sunday then next monday", name: "New Year's Day", type: :public}
```

> *"Australia's **holidays** are a set of recurrences; **this year's** are the days they fall on in 2026, the first of them New Year's Day."*

The window keeps every holiday that overlaps it, so a holiday still running when the window opens is among its holidays: Victoria's summer school holidays, from December to late January, are among the next year's as well as their own.

## Territories and subdivisions

A target is a CLDR territory code (`:AU`, `"AU"`) or a BCP 47 locale, given as the first argument or as the `:territory` or `:locale` option. A locale carries its subdivision — `"en-US-u-sd-usca"` selects California — and the `:subdivision` option names one directly, with the ISO 3166-2 code after the territory's (`"ENG"`) or the whole code (`"GB-ENG"`).

```elixir
{:ok, england} = Tempo.Holidays.holidays(:GB, subdivision: "ENG")
{:ok, los_angeles} = Tempo.Holidays.holidays(:US, subdivision: "CA-LA")
```

> *"**England's** holidays are Great Britain's with England's own; **Los Angeles'** are the United States', California's and the city's."*

A subdivision is found at whichever level the data holds it: a state, or a region by its own code or by its path from its state (`"CA-LA"`, where `"LA"` alone is Louisiana). A code the data does not hold is an error, `{:unknown_subdivision, code}`, never the territory's holidays in its place. Territories inherit as in the dataset (Jersey takes Great Britain's set).

## Holidays compose

Because the holidays are a Tempo value, they meet anything else through set algebra. A set operation converts them over the other operand, keeping every occurrence that overlaps it.

```elixir
{:ok, diary} =
  Tempo.IntervalSet.new([
    Tempo.to_interval!(~o"2026-04-03T09/2026-04-03T10"),
    Tempo.to_interval!(~o"2026-04-08T09/2026-04-08T10")
  ])

{:ok, clashes} = Tempo.intersection(diary, holidays, metadata: :merge)
# => the 3 April meeting, labelled "Good Friday"
```

> *"The **clashes** are the diary entries that fall on a holiday, each labelled with the holiday it hit."*

A holiday with a substitute day is one nested member holding its own date and its substitute days, each substitute day marked `substitute: true`; a bridge day or a holiday moved off another is a conditional member (`Tempo.RecurrenceSet.keep_when/2`, `move_when/2`), resolved against the rest of the set — Japan's Citizens' Holiday is kept only between two public holidays, as in 2026.

## Substitute days

A holiday whose own date falls on a weekend is often observed on another day. The `:dates` option says which date it is given on:

* **`:substitute`** — the day it is observed on: its substitute day in place of its own date, so each holiday is counted once. The default.

* **`:gazetted`** — its own date alone, the date its law names.

* **`:both`** — its own date and its substitute day, as date-holidays gives them.

```elixir
{:ok, england} = Tempo.Holidays.holidays(:GB, subdivision: "ENG", exclude: :observance)
{:ok, this_year} = Tempo.to_interval(england, within: ~o"2026")

Tempo.IntervalSet.count(this_year)
# => 8
```

> *"England has **eight** public and bank holidays in 2026: Boxing Day falls on a Saturday and is counted once, on the Monday it is observed."*

date-holidays writes a substitute day two ways, and both are observed in place of the holiday's own date: as part of the holiday's rule (`12-25 and if saturday then next monday`), or as an entry of its own (`substitutes 12-26 if saturday then next monday`), which stands in for the holiday with the same date rule in the years its gates allow. A substitute day date-holidays lists for one named year — Korea's, when two holidays share a day — is a day off beside its holiday. A holiday the data moves rather than substitutes (`12-25 if saturday then next monday`) is on the day it moves to, and on its own date only under `:gazetted`.

## Selecting holiday types

A holiday's `:type` is `:public`, `:bank`, `:school`, `:optional` or `:observance`. `:include` keeps the types it names and `:exclude` leaves types out, winning over `:include`; each takes a type or a list of them.

```elixir
{:ok, days_off} = Tempo.Holidays.holidays(:DE, include: [:public, :bank])
{:ok, without_observances} = Tempo.Holidays.holidays(:US, exclude: :observance)
```

> *"Germany's **days off** are its public and bank holidays; the US holidays **without observances** leave out the likes of Valentine's Day."*

A selection never changes a date. Glarus' Näfelser Fahrt, a public holiday, moves off Maundy Thursday — an observance — to the following Thursday, and still does when only the public holidays are selected.

## Holidays are intervals

Every occurrence is an interval — a span of days, not an instant — so a multi-day holiday is one interval. A period date-holidays splits over the year end, because its data cannot run one past it, is one member too: Victoria's summer school holidays run from 19 December 2026 to 27 January 2027, 31 December included. A holiday's rule is in its own calendar — an Islamic holiday is an Umm al-Qura date, a Chinese one a date in the Chinese calendar — and a set of occurrences is in one calendar, so beside Gregorian holidays it arrives as the Gregorian days it falls on. Its metadata keeps the calendar its rule is in, as `:calendar`.

```elixir
{:ok, saudi} = Tempo.Holidays.holidays(:SA)
{:ok, this_year} = Tempo.to_interval(saudi, within: ~o"2026")
# Eid al-Fitr lands as ~o"2026Y3M19D/22D", with calendar: Calendrical.Islamic.UmmAlQura in its metadata
```

## A holiday from a rule

Every holiday in the data is a rule in the date-holidays grammar, which Tempo reads with `Tempo.DateRule`. The grammar covers fixed and weekday dates, Islamic/Hebrew/Persian/Julian, Chinese/Korean/Vietnamese lunisolar and Chinese solar terms, equinox and solstice dates, Easter, observed-date substitution ("if it falls on a weekend, observe the Monday"), and inter-holiday bridge days; [its reference](https://hexdocs.pm/ex_tempo/date-rule-grammar.html) gives every form. `Tempo.Holidays.compile/2` reads a rule of your own into a holiday, tagged as the dataset's holidays are.

```elixir
{:ok, company_day} = Tempo.Holidays.compile("1st friday in December", name: "Company Day", type: :optional)
{:ok, this_year} = Tempo.to_interval(company_day, within: ~o"2026")
# => 4 December 2026, tagged %{id: "1st friday in December", name: "Company Day", type: :optional}
```

> *"The **company day** is the first Friday in December; **this year's** is the 4th."*

A rule that depends on other holidays, such as a bridge day (`"08-14 if 08-15 is holiday"`), is decided against the holidays of a set it is in, and alone falls on no day.

## Holidays of your own

`Tempo.Holidays.holidays/2` adds holidays of your own to a territory's and leaves out those you name. `:add` takes rules, each with the options of `Tempo.Holidays.compile/2`, read with the request's `:dates` and selected by `:include` and `:exclude` as the dataset's are; `:remove` takes ids or names, and applies first.

```elixir
company_day = {"1st friday in December", name: "Company Day"}
{:ok, australia} = Tempo.Holidays.holidays(:AU, include: :public, add: [company_day])

{:ok, anbima} = Tempo.Holidays.holidays(:BR, include: [:public, :bank], remove: ["Election Day"])
```

> *"Australia's **public holidays**, with the **company day** beside them; Brazil's public and bank holidays **without Election Day**, ANBIMA's list."*

A holiday you add with the id of one of the dataset's takes its place, and a bridge day you add is decided against the territory's holidays. Holidays an application always wants go in its configuration, keyed by territory, or by territory and subdivision, each with the `:add` and `:remove` a request takes:

```elixir
# config/config.exs
config :tempo_holidays,
  holidays: [
    AU: [add: [{"1st friday in December", name: "Company Day", type: :optional}]],
    BR: [remove: ["Election Day"]],
    "AU-VIC": [add: [{"11-02", name: "Office Closure"}]]
  ]
```

A territory's apply to its subdivisions too, a subdivision's come after its territory's, and a request's own after both. The configuration is read at each request, so nothing needs to be started for it.

## Day starts

An Islamic or Hebrew day begins at sunset, not midnight. A day in Tempo is just a day; `Tempo.Holidays.day_start/2` projects the occurrences of a holiday of those calendars, which it tells by the `:calendar` in their metadata, onto the evening their day begins.

```elixir
{:ok, evenings} = Tempo.Holidays.day_start(this_year, {:evening, "Asia/Riyadh"})
# Eid al-Fitr now begins at 18:00 on 18 March 2026 in Riyadh
```

> *"Saudi Arabia's holidays this year, each beginning on the **evening** its day begins."*

A set is of one frame, so the other holidays become the days they are where the day start is read — Founding Day a day in Riyadh. Where no holiday is projected, every day is left as it is. A lazy set needs a location, since its sunset holidays are not known ahead.

`:sunset` (true sunset) and `:evening` (an 18:00 proxy) begin the day the evening before, at the calendar's reference place (Mecca, Jerusalem) or at a location of your own, `{:sunset, location}` or `{:evening, location}`, a zone id or a `{longitude, latitude}` point. `:midnight` leaves the occurrences as they are. See `Tempo.Holidays.DayStart`.

## Updating the holiday data

The holidays are compiled from a release of [date-holidays](https://github.com/commenthol/date-holidays), the one this release of tempo_holidays pins, and the compiled data ships in the package. date-holidays corrects and adds holidays between releases of tempo_holidays, and an application can take a newer release without waiting: name a directory in its `priv` for the data, and build it there.

```elixir
# config/config.exs
config :tempo_holidays, data_dir: {:my_app, "holidays"}
```

```bash
mix tempo.holidays.update --version 3.38.0
```

The task writes the data to `priv/holidays` of your project, which goes into a release with your application and can be committed with it, and tempo_holidays reads it from there. `Tempo.Holidays.Data.version/0` says which date-holidays release is loaded. The task lists any rule of the release that `Tempo.DateRule` does not read yet; those holidays are left out of the data. Data built by a release of tempo_holidays with another data format is not read: the package's own data is, until the task is run again.
