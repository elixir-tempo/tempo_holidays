# User guide

`tempo_holidays` turns the [date-holidays](https://github.com/commenthol/date-holidays) dataset into [Tempo](https://hexdocs.pm/ex_tempo) recurrences: a holiday is a *rule* — "Christmas is the 25th of December", "Eid al-Fitr is the 1st of Shawwal" — that projects onto any year to give the interval it occupies there.

## Getting a territory's holidays

`recurrences/2` returns a territory's holidays as rules; `materialise/3` projects them onto a year, earliest first.

```elixir
import Tempo.Sigils

{:ok, holidays} = Tempo.Holidays.materialise(:AU, ~o"2026")
# => [{%Holiday{name: "New Year's Day"}, ~o"2026Y1M1D"}, ...]
```

A target is a CLDR territory code (`:AU`, `"AU"`), a BCP 47 locale, or a list of holidays to project directly. A locale carries its state and region — `"en-US-u-sd-usca"` selects California — and `:territory`, `:division` and `:subdivision` override the level. Territories inherit as in the dataset (Jersey takes Great Britain's set).

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
