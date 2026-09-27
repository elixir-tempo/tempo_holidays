# User guide

`tempo_holidays` turns the [date-holidays](https://github.com/commenthol/date-holidays) dataset into [Tempo](https://hexdocs.pm/ex_tempo) recurrences: a holiday is a *rule* — "Christmas is the 25th of December", "Eid al-Fitr is the 1st of Shawwal" — that projects onto any window to give the intervals it occupies there.

## Getting a territory's holidays

`Tempo.Holidays.recurrences/2` returns a territory's holidays as a `Tempo.RecurrenceSet`: one member per holiday, tagged with its `:id` (the date-holidays rule, unique where names repeat), `:name` and `:type`. `Tempo.Holidays.materialise/3` projects them onto a window — a year, or any interval — as a `Tempo.IntervalSet` of occurrences, earliest first, each tagged the same way.

```elixir
import Tempo.Sigils

{:ok, holidays} = Tempo.Holidays.recurrences(:AU)
{:ok, this_year} = Tempo.Holidays.materialise(holidays, ~o"2026")

new_year = Tempo.IntervalSet.first(this_year)
Tempo.metadata(new_year)
# => %{id: "01-01 and if saturday,sunday then next monday", name: "New Year's Day", type: :public}
```

> *"Australia's **holidays** are a set of recurrences; **this year's** are the days they fall on in 2026, the first of them New Year's Day."*

A target is a CLDR territory code (`:AU`, `"AU"`), a BCP 47 locale, or a recurrence set `recurrences/2` returned. A locale carries its state and region — `"en-US-u-sd-usca"` selects California — and `:territory`, `:division` and `:subdivision` override the level. Territories inherit as in the dataset (Jersey takes Great Britain's set).

## Holidays compose

Because the holidays are a Tempo value, they meet anything else through set algebra. A set operation materialises them over the other operand, keeping every occurrence that overlaps it.

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

A holiday observed on another day is one nested member holding its own date and its observed days, each observed day marked `substitute: true`; a bridge day or a holiday moved off another is a conditional member (`Tempo.RecurrenceSet.keep_when/2`, `move_when/2`), resolved against the rest of the set — Japan's Citizens' Holiday is kept only between two public holidays, as in 2026.

## Holidays are intervals

Every occurrence is a `Tempo.Interval` — a half-open span, not an instant — so a multi-day holiday is one interval and abutting days of the same holiday merge into the period they describe. Dates in a non-Gregorian calendar are returned *in that calendar*: an Islamic holiday materialises as an Umm al-Qura date, a Chinese one in the Chinese calendar.

```elixir
{:ok, holidays} = Tempo.Holidays.materialise(:SA, ~o"2026")
# Eid al-Fitr lands as ~o"1447Y9M30D[u-ca=islamic-umalqura]", an Umm al-Qura date
```

The grammar covers fixed and weekday dates, Islamic/Hebrew/Persian/Julian, Chinese/Korean/Vietnamese lunisolar and Chinese solar terms, equinox and solstice dates, Easter, observed-date substitution ("if it falls on a weekend, observe the Monday"), and inter-holiday bridge days.

## Day-start projection

An Islamic or Hebrew day begins at sunset, not midnight. A day in Tempo is just a day; the `:day_start` option decides how it lands on the Gregorian timeline.

```elixir
# The in-calendar day (default)
Tempo.Holidays.materialise(:SA, ~o"2026", day_start: :midnight)

# Projected to begin at sunset the evening before
Tempo.Holidays.materialise(:SA, ~o"2026", day_start: :sunset)
```

`:sunset` (true sunset) and `:evening` (an 18:00 proxy) return the datetime interval that begins the evening before, at the calendar's canonical reference (Mecca, Jerusalem) or an explicit `{:sunset, anchor}` / `{:evening, anchor}` zone id or `{longitude, latitude}` location. See `Tempo.Holidays.DayStart`.
