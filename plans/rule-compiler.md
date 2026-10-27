# A public rule compiler, and holidays of your own

**Status:** in progress, 2026-10-27

The grammar and its compiler move to Tempo as `Tempo.DateRule` (D5, below), planned in Tempo's `plans/date-rule.md`. What stays here: the dataset, holiday names and types, territories, the update task, `Tempo.Holidays.compile/2` as the holiday layer over `Tempo.DateRule.parse/2`, and holidays of your own.

Two things the user asked for on 2026-10-27: a public compiler that takes a holiday rule, written in the date-holidays grammar, and gives a Tempo recurrence; and on top of it, holidays an application defines itself, a rule with territories and metadata, which `Tempo.Holidays.holidays/2` gives beside the dataset's. The grammar is to be derived from date-holidays, and the compilers we have reused.

## What there is

As it was on 2026-10-27, before the move; `Grammar`, `Compiler` and `Rule` are retired, and the dataset is read by `Tempo.DateRule`.

* **Public:** `Tempo.Holidays.holidays/2` (a territory's holidays as a recurrence set) and `day_start/2`. A holiday is reached only through a territory.

* **Public functions in modules that read as internal:** `Tempo.Holidays.Compiler.compile/1` (a rule string to a `%Tempo.Holidays.Rule{}`), `Rule.recurrence/2` (a rule to a Tempo recurrence), `Rule.materialise/2`, and `DateHolidays.compile_day/4` (a rule with its metadata to a `%Holiday{}`). None is documented as API, and `%Rule{}` is a 30-field internal struct.

* **How it compiles:** `Compiler.compile/1` tries a list of whole-rule patterns, one regex for each shape the dataset uses ("`<weekday> after <n><weekday> after <MM-DD>`"), into one of about twenty `%Rule{}` kinds. A rule is compiled only where its whole shape has a pattern, so a combination the grammar allows but the dataset does not use is refused.

## The grammar

The authority is date-holidays-parser (`src/Parser.js`, v3.4.7, ISC licence), whose `specification.md` in date-holidays describes it. Its grammar is compositional: a rule is a sequence of parts, read left to right by an ordered list of token readers, then reordered so the base date comes first.

```text
rule         = [same-day] {weekday-step} base [time] [duration] {modifier} [active]

base         = gregorian | month-start | julian | easter | equinox
             | islamic | hebrew | persian | lunisolar | solar-term | bengali
gregorian    = [year "-"] month "-" day                 ; "12-25", "2015-10-09"
month-start  = month-name                               ; "February" = "02-01"
julian       = "julian " gregorian
easter       = ("easter" | "orthodox") [" " signed-days] ; "easter -2", "orthodox 49"
equinox      = season (" equinox" | " solstice") [" in " zone]
islamic      = day " " islamic-month [" " year]         ; "10 Dhu al-Hijjah"
hebrew       = day " " hebrew-month [" " year]          ; "15 Nisan", "AdarII"
persian      = day " " persian-month [" " year]         ; "1 Farvardin 1401"
lunisolar    = ("chinese" | "korean" | "vietnamese") " " [cycle "-" year "-"] month "-" leap "-" day
solar-term   = ("chinese" | "korean" | "vietnamese") " " [cycle "-" year "-"] term "-" day " solarterm"
bengali      = "bengali-revised " [year "-"] month "-" day

weekday-step = [count " "] (weekday | "day" | "days") " " ("before" | "after" | "in" | "next" | "previous") " "
                                                        ; "Friday after", "2nd Sunday after", "4 days before"
time         = ["T"] hour ":" minute | "T" hour         ; "12-31 14:00"
duration     = "P" [n "D"] ["T" [n "H"] [n "M"]]        ; "PT5H", "P1DT12H"

modifier     = ("substitutes" | "and" | "if" | "then" | "if equal") ...  ; joins the clauses below
             | "if " weekdays " then " [direction " " weekday]   ; "if sunday then next monday"
             | "in " ("even" | "odd" | "leap" | "non-leap") " years" | "every " n " years since " year
             | ["not "] "on " weekdays                  ; "on Monday, Tuesday"
             | "is " [type " "] "holiday"                ; a bridge: "09-22 if 09-21 is holiday"
             | "if is " [type " "] "holiday then " [count " "] [direction " " (weekday | "day")] [" omit " weekdays]
active       = "since " date-part [" and"] | "prior to " date-part
same-day     = "#" digits                               ; the same rule, kept apart
```

The metadata beside a rule in `holidays.yaml` (a name per language, `type`, `substitute`, `active` periods, `disable` and `enable` dates, `false` to remove an inherited rule) is not part of the rule; it is the holiday around it.

## How much of it compiles today

A census of every rule in date-holidays-parser's own golden fixture (`test/fixtures/parser.cjs`, 117 rules, each with the tokens the parser makes of it) and every example in the specification, compiled by `Compiler.compile/1` on 2026-10-27:

* **The parser's fixture:** 102 of 117 compile. Of the fifteen that do not, one is no rule (`#1111` alone).

* **The specification's examples:** 52 of 58 compile, leaving out the 16 placeholders the census caught (`<weekday>`, `D`).

* **The dataset (3.38.0):** every rule compiles but three shapes, accepted gaps: the eight Bengali rules, Poland's `Thursday before easter -46`, and a US rule that ended in 2016, `friday before 1st monday before 06-01`.

What does not compile, by production:

* **A base date's optional year or cycle:** `31 Shahrivar 1401`, `chinese 78-32-08-0-15`, `chinese 78-32-24-01 solarterm`, `julian 2015-01-09`.

* **A month alone:** `February`.

* **A weekday step before a base other than a fixed date:** `3rd monday before December solstice`, `3rd Sunday after june solstice in Asia/Tokyo`, `friday before chinese 78-32-8-15 solarterm`, `Thursday before easter -46`.

* **A count of days as a step:** `4 days before 11-23`, `4 days after 11-27`.

* **A nested step whose inner direction is `before`:** `friday before 1st monday before 06-01`.

* **`if equal`:** `2nd sunday after 05-01 if equal easter 49 then 3rd sunday after 05-01`.

* **`prior to` a month:** `09-21 prior to 2020-11`.

* **A time written `T16`:** `03-12T16`.

* **Bengali:** no Bengali calendar in Calendrical (`TODO.md`, blocked).

* **A defect:** the Islamic month 11 is spelled `Dhu al-Qadah` in the compiler and `Dhu al-Qidah` in the grammar, so `4 Dhu al-Qidah` is refused. No rule in the dataset uses the month.

## The shape of the work

1. **Read the grammar as the parser does.** A tokenizer with one reader for each of the parser's token kinds, in the parser's order, giving the same tokens: its fixture of 117 rules becomes a golden test that our tokens are its tokens. The rule is then compiled from its tokens, part by part, into the `%Rule{}` kinds and Tempo builders there are now; a combination is compiled because its parts are, where a whole-rule pattern compiled only the shapes it named. Each gap above is closed by its part, or named as an error.

2. **A public compiler.** One function takes a rule and gives a Tempo recurrence, with the holiday's metadata on it; an error names the rule and where the reading stopped. `%Rule{}` stays internal.

3. **Holidays of your own.** A holiday defined from a rule, its territories and its metadata, given by `holidays/2` for those territories beside the dataset's, and able to replace or remove one of the dataset's.

4. **The guide.** The grammar as a guide page in the house style, each production with examples that run.

## Decisions

Taken by the user on 2026-10-27.

* **D1 — the compiler.** A tokenizer of date-holidays-parser's grammar, one reader for each of its token kinds in its order, tested against the tokens its own 117-rule fixture records; rules compile from the tokens, part by part, into the `%Rule{}` kinds there are. Every rule that compiles today compiles to the same dates (the conformance corpus holds it).

* **D2 — the public function.** `Tempo.Holidays.compile(rule, options)` gives `{:ok, recurrence}`, a `t:Tempo.t/0` tagged as the dataset's members are (`:id`, `:name`, `:type`, and metadata of the caller's), or `{:error, exception}` naming where the rule stopped. `%Rule{}` stays internal.

* **D3 — rules that depend on other holidays.** A bridge, `if is holiday` and `if equal` compile to the conditional member the dataset's rules are: decided against the other holidays when it is in a set, and against none when it is converted alone, which the documentation says.

* **D5 — where the grammar lives** (2026-10-27, the user: "the rule compiler better belongs in Tempo itself since it's a generally useful tool"). In Tempo, as `Tempo.DateRule`, a reader beside `Tempo.RRule` and `Tempo.Cron` giving Tempo expressions; tempo_holidays compiles its dataset with it.

* **D4 — where your holidays come from.** Both: `holidays(:AU, add: [...], remove: [...])` for a call, and `config :tempo_holidays, holidays: [...]` for those an application always wants, read at call time, with no process to supervise.

Taken by the user on 2026-10-27, for what the holiday layer applies on top of a rule (a census of the 5,154 entries of the 3.38.0 data: 333 `and if` rules, 229 `substitutes …` entries, 253 `active` windows, 51 `disable` and 45 `enable` dates, 5 year-end pairs). Each of D6 to D8 is an option of `Tempo.DateRule.parse/2` (Tempo's `plans/date-rule.md`):

* **D6 — the `:dates` option.** Read with `observed: :moved` for `:substitute`, `:none` for `:gazetted`, `:as_written` for `:both`.

* **D7 — substitute entries.** A holiday a `substitutes` entry stands in for is read with `replaced_by: [entry]`: not on the entry's trigger weekdays in its years.

* **D8 — `active`, `disable` and `enable`.** Passed as `active:`, `disable:` and `enable:`, folded into the domain as `Rule` folds them now.

* **D9 — a period split at the year end.** One member: the union of the two dated spans, coalesced into the one period.

Taken by the user on 2026-10-27, for the move itself:

* **D10 — Tempo while the move is under way.** From GitHub `main` (`{:ex_tempo, github: "elixir-tempo/tempo"}`), so a change the move needs in Tempo lands before Tempo 2.1 is published; then `~> 2.1` from hex before this library's release.

* **D11 — when a rule is read.** At call time, cached per territory, subdivision and `:dates` reading for the life of the VM, as `Rule.prepare/1` is today: the built data holds each holiday's rule text and its metadata. Reading a territory took 2–44 ms, Japan 203 ms (its `active` windows), measured on the 3.38.0 data.

* **D12 — a substitute entry under `:gazetted`.** Read with `observed: :none`, which gives a `substitutes` rule no date (Tempo `164d6de`); what is empty is dropped.

## Tasks

* [ ] **Tempo.DateRule** — the tokenizer, compiling from its tokens and the census gaps, in Tempo (`plans/date-rule.md` there); Tempo 2.1.

* [ ] **`Tempo.Holidays.compile/2`** — a rule read by `Tempo.DateRule`, tagged as the dataset's members are.

* [ ] **Holidays of your own** — `add:` and `remove:` on `holidays/2`, `config :tempo_holidays, holidays:`, a holiday's territories and subdivisions, replacing or removing a dataset holiday by id.

### Done

* [x] **The dataset on Tempo.DateRule** — Tempo from `main` (D10); each `%Holiday{}` holds its rule text and its `active`, `disable` and `enable` dates (format 5); `holidays/2` reads them with `Tempo.DateRule` (D6–D9, D12), cached (D11); the conformance harness on the public path; `Grammar`, `Compiler`, `Rule` and the vendored parser fixture retired. The move found two defects in Tempo, fixed there (`8e70b68`, `a904215`), and gaps in the built subdivisions (`_days` below the country, a country's top-level `regions`, a subdivision with no days of its own), fixed here. Conformance: 170,818 checks, 169,799 matched, 0 mismatched, 0 unsupported, 120 Bengali, 899 accepted differences (850 Mauritius district fixtures of an older release, 30 Timaru and Buller fixtures that ignore their region's data, 19 Islamic). 2026-10-27.

* [x] **The tokenizer** — `Tempo.Holidays.Grammar.tokens/1` and `tokenize/1`: the parser's 23 readers in its order and its reordering; every one of the 119 rules of its fixture (`test/fixtures/date_holidays_parser_tokens.json`, vendored with its ISC notice in `NOTICE`) read to the parser's tokens; retired with the module once Tempo held the grammar. `on <weekdays>` is read only at the start of what is left. 2026-10-27.
