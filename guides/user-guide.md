# User guide

`tempo_holidays` turns the [date-holidays](https://github.com/commenthol/date-holidays) dataset into [Tempo](https://hexdocs.pm/ex_tempo) recurrences: a holiday is a *rule* — "Christmas is the 25th of December", "Eid al-Fitr is the 1st of Shawwal" — that gives the intervals it occupies in any window.

## Getting a territory's holidays

`Tempo.Holidays.holidays/2` returns a territory's holidays as a `Tempo.RecurrenceSet`: one member per holiday, tagged with its `:id` (the date-holidays rule, unique where names repeat), `:name` and `:type`. `Tempo.to_interval/2` converts them to the holidays in a window — a year, or any interval — as a set of occurrences, earliest first, each tagged the same way.

```elixir
iex> import Tempo.Sigils
iex> {:ok, holidays} = Tempo.Holidays.holidays(:AU)
iex> {:ok, this_year} = Tempo.to_interval(holidays, within: ~o"2026")
iex> new_year = Tempo.IntervalSet.first(this_year)
iex> Tempo.metadata(new_year)
%{id: "01-01 and if saturday,sunday then next monday", name: "New Year's Day", type: :public}
```

> *"Australia's **holidays** are a set of recurrences; **this year's** are the days they fall on in 2026, the first of them New Year's Day."*

The window keeps every holiday that overlaps it, so a holiday still running when the window opens is among its holidays: Victoria's summer school holidays, from December to late January, are among the next year's as well as their own.

## Territories and subdivisions

A target is a CLDR territory code (`:AU`, `"AU"`), given as the first argument or as the `:territory` option, or a BCP 47 locale, given as the `:locale` option or as a `Localize.LanguageTag` in first place; a string in first place is always a territory. A locale carries its subdivision — `"en-US-u-sd-usca"` selects California — and the `:subdivision` option names one directly, with the ISO 3166-2 code after the territory's (`"ENG"`) or the whole code (`"GB-ENG"`).

```elixir
iex> {:ok, england} = Tempo.Holidays.holidays(:GB, subdivision: "ENG")
iex> Tempo.metadata(england)
%{territory: "GB", subdivision: "ENG", dates: :substitute}
iex> {:ok, los_angeles} = Tempo.Holidays.holidays(:US, subdivision: "CA-LA")
iex> Tempo.metadata(los_angeles)
%{territory: "US", subdivision: "CA-LA", dates: :substitute}
iex> {:ok, california} = Tempo.Holidays.holidays(locale: "en-US-u-sd-usca")
iex> Tempo.metadata(california)
%{territory: "US", subdivision: "CA", dates: :substitute}
```

> *"**England's** holidays are Great Britain's with England's own; **Los Angeles'** are the United States', California's and the city's."*

A subdivision is found at whichever level the data holds it: a state, or a region by its own code or by its path from its state (`"CA-LA"`, where `"LA"` alone is Louisiana). A code the data does not hold is an error, `{:unknown_subdivision, code}`, never the territory's holidays in its place. Territories inherit as in the dataset (Jersey takes Great Britain's set).

## Holidays compose

Because the holidays are a Tempo value, they meet anything else through set algebra. A set operation converts them over the other operand, keeping every occurrence that overlaps it.

```elixir
iex> import Tempo.Sigils
iex> {:ok, holidays} = Tempo.Holidays.holidays(:AU)
iex> {:ok, diary} =
...>   Tempo.IntervalSet.new([
...>     Tempo.to_interval!(~o"2026-04-03T09/2026-04-03T10"),
...>     Tempo.to_interval!(~o"2026-04-08T09/2026-04-08T10")
...>   ])
iex> {:ok, clashes} = Tempo.intersection(diary, holidays, metadata: :merge)
iex> Tempo.IntervalSet.map(clashes, &Tempo.metadata(&1).name)
["Good Friday"]
```

> *"The **clashes** are the diary entries that fall on a holiday, each labelled with the holiday it hit."*

A holiday with a substitute day is one nested member holding its own date and its substitute days, each substitute day marked `substitute: true`; a bridge day or a holiday moved off another is a conditional member (`Tempo.RecurrenceSet.keep_when/2`, `move_when/2`), resolved against the rest of the set — Japan's Citizens' Holiday is kept only between two public holidays, as in 2026.

## Substitute days

A holiday whose own date falls on a weekend is often observed on another day. The `:dates` option says which date it is given on:

* **`:substitute`** — the day it is observed on: its substitute day in place of its own date, so each holiday is counted once. The default.

* **`:gazetted`** — its own date alone, the date its law names.

* **`:both`** — its own date and its substitute day, as date-holidays gives them.

```elixir
iex> import Tempo.Sigils
iex> {:ok, england} = Tempo.Holidays.holidays(:GB, subdivision: "ENG", exclude: :observance)
iex> {:ok, this_year} = Tempo.to_interval(england, within: ~o"2026")
iex> Tempo.IntervalSet.count(this_year)
8
```

> *"England has **eight** public and bank holidays in 2026: Boxing Day falls on a Saturday and is counted once, on the Monday it is observed."*

date-holidays writes a substitute day two ways, and both are observed in place of the holiday's own date: as part of the holiday's rule (`12-25 and if saturday then next monday`), or as an entry of its own (`substitutes 12-26 if saturday then next monday`), which stands in for the holiday with the same date rule in the years its gates allow. A substitute day date-holidays lists for one named year — Korea's, when two holidays share a day — is a day off beside its holiday. A holiday the data moves rather than substitutes (`12-25 if saturday then next monday`) is on the day it moves to, and on its own date only under `:gazetted`.

## Selecting holiday types

A holiday's `:type` is `:public`, `:bank`, `:school`, `:optional` or `:observance`. `:include` keeps the types it names and `:exclude` leaves types out, winning over `:include`; each takes a type or a list of them.

```elixir
iex> {:ok, _days_off} = Tempo.Holidays.holidays(:DE, include: [:public, :bank])
iex> {:ok, _without_observances} = Tempo.Holidays.holidays(:US, exclude: :observance)
iex> Tempo.Holidays.holidays(:US, include: :festive)
{:error, {:invalid_holiday_type, :festive}}
```

> *"Germany's **days off** are its public and bank holidays; the US holidays **without observances** leave out the likes of Valentine's Day."*

A selection never changes a date. Glarus' Näfelser Fahrt, a public holiday, moves off Maundy Thursday — an observance — to the following Thursday, and still does when only the public holidays are selected.

## Holidays are intervals

Every occurrence is an interval — a span of days, not an instant — so a multi-day holiday is one interval. A period date-holidays splits over the year end, because its data cannot run one past it, is one member too: Victoria's summer school holidays run from 19 December 2026 to 27 January 2027, 31 December included. A holiday's rule is in its own calendar — an Islamic holiday is an Umm al-Qura date, a Chinese one a date in the Chinese calendar — and a set of occurrences is in one calendar, so beside Gregorian holidays it arrives as the Gregorian days it falls on. Its metadata keeps the calendar its rule is in, as `:calendar`.

```elixir
iex> import Tempo.Sigils
iex> {:ok, saudi} = Tempo.Holidays.holidays(:SA)
iex> {:ok, this_year} = Tempo.to_interval(saudi, within: ~o"2026")
iex> eid = Enum.find(Tempo.IntervalSet.members(this_year), &(Tempo.metadata(&1).name =~ "Eid al-Fitr"))
iex> Tempo.equal?(eid, ~o"2026-03-19/2026-03-22")
true
iex> Tempo.metadata(eid).calendar
Calendrical.Islamic.UmmAlQura
```

## A holiday from a rule

Every holiday in the data is a rule in the date-holidays grammar, which Tempo reads with `Tempo.DateRule`. The grammar covers fixed and weekday dates, Islamic/Hebrew/Persian/Julian, Chinese/Korean/Vietnamese lunisolar and Chinese solar terms, equinox and solstice dates, Easter, observed-date substitution ("if it falls on a weekend, observe the Monday"), and inter-holiday bridge days; [its reference](https://hexdocs.pm/ex_tempo/date-rule-grammar.html) gives every form. `Tempo.Holidays.compile/2` reads a rule of your own into a holiday, tagged as the dataset's holidays are.

```elixir
iex> import Tempo.Sigils
iex> {:ok, company_day} = Tempo.Holidays.compile("1st friday in December", name: "Company Day", type: :optional)
iex> {:ok, this_year} = Tempo.to_interval(company_day, within: ~o"2026")
iex> Tempo.IntervalSet.map(this_year, &Tempo.day/1)
[4]
```

> *"The **company day** is the first Friday in December; **this year's** is the 4th."*

A rule that depends on other holidays, such as a bridge day (`"08-14 if 08-15 is holiday"`), is decided against the holidays of a set it is in, and alone falls on no day.

## Holidays of your own

`Tempo.Holidays.add/3` adds a holiday of your own to the set `Tempo.Holidays.holidays/2` returns, read from a rule with the options of `Tempo.Holidays.compile/2`, and `Tempo.Holidays.remove/2` removes holidays by id or name.

```elixir
iex> import Tempo.Sigils
iex> {:ok, public} = Tempo.Holidays.holidays(:AU, include: :public)
iex> {:ok, australia} = Tempo.Holidays.add(public, "1st friday in December", name: "Company Day")
iex> {:ok, december} = Tempo.to_interval(australia, within: ~o"2026-12")
iex> Tempo.IntervalSet.map(december, &Tempo.metadata(&1).name)
["Company Day", "Christmas Day", "Boxing Day"]

iex> import Tempo.Sigils
iex> {:ok, brazil} = Tempo.Holidays.holidays(:BR, include: [:public, :bank])
iex> {:ok, anbima} = Tempo.Holidays.remove(brazil, "Election Day")
iex> {:ok, october} = Tempo.to_interval(anbima, within: ~o"2026-10")
iex> Tempo.IntervalSet.map(october, &Tempo.metadata(&1).name)
["Our Lady of Aparecida"]
```

> *"Australia's **public holidays**, with the **company day** added; Brazil's public and bank holidays **without Election Day**, ANBIMA's list."*

An added holiday is read with the `:dates` the set was read with, kept whatever its type, and takes the place of a holiday of its id. A name can be shared, so removing a name removes every holiday of that name. A bridge day, or a holiday moved off another, is decided against the holidays in the set: an added bridge day counts the set's holidays, Norfolk Island's King's Birthday moves off a holiday you add on its day, and Japan's Citizens' Holiday no longer counts a holiday you remove.

Holidays an application always wants go in its configuration, keyed by territory, or by territory and subdivision, each with an `:add` (rules, or `{rule, options}`) and a `:remove` (ids or names):

```elixir
# config/config.exs
config :tempo_holidays,
  holidays: [
    AU: [add: [{"1st friday in December", name: "Company Day", type: :optional}]],
    BR: [remove: ["Election Day"]],
    "AU-VIC": [add: [{"11-02", name: "Office Closure"}]]
  ]
```

A configured holiday is one of the territory's, selected by type as the dataset's are: the optional Company Day above is left out of `holidays(:AU, include: :public)`. A territory's apply to its subdivisions too, and a subdivision's come after its territory's; `Tempo.Holidays.add/3` and `Tempo.Holidays.remove/2` then change what they give. The configuration is read at each request, so nothing needs to be started for it.

## Business days

A territory's weekend and its holidays are both Tempo values, so its business days are what is left of a period once both are taken away, and `Tempo.count/3` counts them in days.

```elixir
iex> import Tempo.Sigils
iex> {:ok, brazil} = Tempo.Holidays.holidays(:BR, include: [:public, :bank])
iex> {:ok, anbima} = Tempo.Holidays.remove(brazil, "Election Day")
iex> {:ok, weekends} = Tempo.weekends(:BR)
iex> {:ok, business_days} = Tempo.difference(~o"2026-01-02/2026-03-31", [weekends, anbima])
iex> Tempo.count(business_days, :day)
{:ok, 61}
```

> *"Brazil's public and bank holidays **without Election Day** are ANBIMA's calendar. The **business days** from the 2nd of January to the 31st of March are those days **less** the weekends and **less** those holidays: 61 of them."*

A period written to dates holds both its first day and its last, so the count above includes the 31st of March. `Tempo.workdays/2` takes the holidays as its `:except`, for the business day five days after another (`Tempo.add_workdays/3`) or whether a day is one (`Tempo.workday?/2`).

## Day starts

An Islamic or Hebrew day begins at sunset, not midnight. A day in Tempo is just a day; `Tempo.Holidays.day_start/2` projects the occurrences of a holiday of those calendars, which it tells by the `:calendar` in their metadata, onto the evening their day begins.

```elixir
iex> import Tempo.Sigils
iex> {:ok, saudi} = Tempo.Holidays.holidays(:SA, include: :public)
iex> {:ok, this_year} = Tempo.to_interval(saudi, within: ~o"2026")
iex> {:ok, evenings} = Tempo.Holidays.day_start(this_year, {:evening, "Asia/Riyadh"})
iex> eid = Enum.find(Tempo.IntervalSet.members(evenings), &(Tempo.metadata(&1).name =~ "Eid al-Fitr"))
iex> {:ok, begins} = Tempo.to_elixir(Tempo.Interval.from(eid))
iex> {DateTime.to_date(begins), DateTime.to_time(begins)}
{~D[2026-03-18], ~T[18:00:00]}
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
