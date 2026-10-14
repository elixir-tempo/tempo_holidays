defmodule Tempo.Holidays.Rule do
  @moduledoc """
  A compiled holiday rule, and its projection onto a year.

  A rule is the calendar-agnostic *recurrence* behind a holiday, compiled
  from a [date-holidays](https://github.com/commenthol/date-holidays) rule
  string by `Tempo.Holidays.Compiler`. `materialise/2` projects it onto a
  concrete year, yielding the interval (a `t:Tempo.t/0`) for that occurrence, by
  evaluating the rule's recurrence (`recurrence/1`) — built once by
  `prepare/1`, so projecting a prepared rule onto any number of years parses
  nothing. `materialise_concrete/2` computes the same occurrences kind by kind:
  the path for a rule with no standalone recurrence, and an independent check
  of the ones that have one.

  Each `:kind` maps to the machinery that can express it: `:fixed`,
  `:weekday`, `:relative_weekday` and `:nested_weekday` (a weekday relative to
  a weekday-in-month, such as US Election Day) are Tempo-native date selections
  and arithmetic; `:easter` / `:orthodox` are computed through Calendrical's
  ecclesiastical calendar, since Easter has no fixed-date RRULE and is instead
  a `(easter)e` computed event; and `:islamic`, `:hebrew`, `:persian` and
  `:julian` (Orthodox Christmas and the like) are each materialised in their
  own calendar as a yearly recurrence bounded to the year — Islamic via Umm
  al-Qura, Julian via Calendrical's non-CLDR Julian calendar — returned as an
  `[u-ca=…]`-tagged value.

  `recurrence/1` re-expresses a rule, gates and all, as a standalone,
  re-materialisable recurrence: a calendar date under `[u-ca=…]`, a lunisolar
  date as a traditional-month `m` selection under `[u-ca=…]`, a moveable feast as
  a §12.10 window off `(easter)e`, a relative or nested weekday as a window off
  its anchor date (a weekday after the nth weekday after a date as a window off
  that window), an Islamic day-rollover as the last day of a window off the
  month's 1st, and a lunisolar eve or day-offset folded into the day (`net_day =
  day + offset`). A multi-day holiday (`count > 1`) adds an `:occurrence_duration`
  span over any of these. Its year gates (`since`/`until`, `active` windows,
  every-N-years, even/odd/leap) become the recurrence's `{…}` domain and a weekday
  gate a weekday limit. The gates are Gregorian years and a domain is in its
  recurrence's calendar, so beside a rule of another calendar each is written as
  the years of that calendar whose occurrence falls in it (`12 Cheshvan … since
  1997` is `{5758Y..}`). An observed-date substitution or a `disable`/`enable` move
  makes it a recurrence set of several (`Tempo.RecurrenceSet`). An inter-holiday bridge or
  `if`-holiday move depends on the year's other holidays, so it is a conditional
  member (`Tempo.RecurrenceSet.keep_when/2`, `move_when/2`) wrapping the rule's own
  recurrence, resolved when its holiday set materialises. What stays
  `:needs_window` is a rule no recurrence expresses exactly — a shifted or
  non-Chinese-meridian solar term — which none of the stored rules is.

  A rule may also carry an observed-date `t:substitute/0` — "if it falls on a
  weekend, observe it the following Monday" — as ordered clauses, each with its
  own mode (`:shift` moves the date, `:add` keeps it and adds the observed day,
  `:substitute_only` is the observed day alone); the first clause a date
  triggers fires and the rest leave it alone. Plus year conditions
  (`:from_year`/`:to_year`, even/odd `:year_parity`, and `:leap`) that gate
  whether it occurs at all.

  Finally it may carry date-holidays' occurrence-level metadata gates, applied
  to the computed dates: `:active` restricts the rule to one or more half-open
  `[from, to)` windows, `:disable` removes specific dates, and `:enable` adds
  explicit dates (a `:disable` + `:enable` pair is how the data *moves* an
  occurrence — the UK 2022 Spring bank holiday to the Jubilee Thursday).

  """

  alias Tempo.Duration
  alias Tempo.Interval
  alias Tempo.IntervalSet

  # The kinds whose `count` is a multi-day span (the others use `count` for a
  # weekday, an instance or a solar-term index, so they take no span).
  @span_kinds [
    :fixed,
    :easter,
    :orthodox,
    :equinox,
    :solstice,
    :hebrew,
    :persian,
    :julian,
    :islamic,
    :lunisolar
  ]

  @all_weekdays [1, 2, 3, 4, 5, 6, 7]

  @type kind ::
          :fixed
          | :weekday
          | :relative_weekday
          | :nested_weekday
          | :nested_after_date
          | :islamic
          | :hebrew
          | :persian
          | :julian
          | :lunisolar
          | :solar_term
          | :equinox
          | :solstice
          | :easter
          | :orthodox

  @typedoc """
  An observed-date substitution: ordered
  `{trigger_weekdays, direction, target_weekday, mode}` clauses in ISO weekday
  numbering (Monday = 1 … Sunday = 7). When a materialised date lands on one of
  a clause's trigger weekdays, that clause fires and no later clause touches the
  date; its `mode` decides what happens — `:shift` moves the holiday to the
  target weekday, `:add` keeps the original and adds the observed day, and
  `:substitute_only` yields the observed day alone (and drops the holiday when no
  clause fires). "If it falls on a weekend, take the following Monday" is
  `[{[6, 7], :next, 1, :shift}]`.
  """
  @type substitute :: [{[1..7], :next | :previous, 1..7, :shift | :add | :substitute_only}]

  @typedoc """
  A substitute entry that stands in for a holiday's own date: date-holidays'
  `substitutes 12-26 if saturday then next monday` beside the `12-26` it
  substitutes. Under `dates: :substitute` the holiday is not observed on its
  own date where the entry gives a substitute day instead — on the `triggers`
  weekdays, in the years the entry's `from_year`/`to_year` and `active` gates
  allow — `years`, the inclusive year ranges `prepare/1` found them to be, or
  `nil` when the entry was not prepared.
  """
  @type replacement :: %{
          triggers: [1..7],
          years: [{integer() | nil, integer() | nil}] | nil,
          from_year: integer() | nil,
          to_year: integer() | nil,
          active: [{Date.t() | nil, Date.t() | nil}] | nil
        }

  @type t :: %__MODULE__{
          kind: kind(),
          month: pos_integer() | nil,
          day: pos_integer() | nil,
          count: integer() | nil,
          weekday: 1..7 | nil,
          inner_weekday: 1..7 | nil,
          direction: :before | :after | nil,
          offset: integer() | nil,
          calendar: module() | nil,
          leap_month: boolean() | nil,
          timezone: String.t() | nil,
          substitute: substitute() | nil,
          replaced_by: [replacement()] | nil,
          from_year: integer() | nil,
          to_year: integer() | nil,
          year_parity: :even | :odd | nil,
          leap: :leap | :non_leap | nil,
          every_years: pos_integer() | nil,
          weekday_gate: {:only | :except, [1..7]} | nil,
          active: [{Date.t() | nil, Date.t() | nil}] | nil,
          disable: [Date.t()] | nil,
          enable: [Date.t()] | nil,
          conditional: conditional() | nil,
          source: String.t() | nil,
          recurrence: Tempo.t() | :needs_window | nil,
          observed: %{optional(:substitute | :gazetted) => Tempo.t() | :needs_window} | nil,
          years: [{integer() | nil, integer() | nil}] | nil
        }

  @typedoc """
  An inter-holiday condition that turns a rule's occurrence on or off, or moves
  it, depending on the *other* holidays of the year — so it is resolved in a
  second pass with the year's holiday set. `:bridge` keeps the occurrence only
  when every `:on` date (`{month, day}`) is itself a holiday of `:type`
  (`"09-22 if 09-21 and 09-23 is public holiday"`); `:if_holiday` moves the
  occurrence by `:move` when it coincides with a holiday of `:type`
  (`"… if is observance holiday then next Thursday"`). `:type` defaults to
  `:public`.
  """
  @type conditional ::
          %{kind: :bridge, type: atom(), on: [{pos_integer(), pos_integer()}]}
          | %{kind: :if_holiday, type: atom(), move: move()}

  @typedoc """
  A relative move applied to a date: `count` steps in `direction` to the next
  `target` — a weekday `1..7`, or `:day` (a plain day step that skips the `omit`
  weekdays).
  """
  @type move :: %{
          count: pos_integer(),
          direction: :next | :after | :before | :previous,
          target: 1..7 | :day,
          omit: [1..7]
        }

  @enforce_keys [:kind]
  defstruct [
    :kind,
    :month,
    :day,
    :count,
    :weekday,
    :inner_weekday,
    :direction,
    :offset,
    :calendar,
    :leap_month,
    :timezone,
    :substitute,
    # The substitute entries that stand in for the holiday's own date, set by
    # `observe/3`; never stored with the data.
    :replaced_by,
    :from_year,
    :to_year,
    :year_parity,
    :leap,
    :every_years,
    :weekday_gate,
    :active,
    :disable,
    :enable,
    :conditional,
    :source,
    # The rule's recurrence once `prepare/1` has built it (or `:needs_window`
    # when it has none); `nil` until then.
    :recurrence,
    # The recurrences of the rule as `observe/3` observes it under `dates:
    # :substitute` and `:gazetted`, where they differ, built by `prepare/1`.
    :observed,
    # A substitute entry's years, the inclusive ranges its gates allow, found by
    # `prepare/1`.
    :years
  ]

  @doc """
  Project a rule onto a Gregorian `year`, returning its occurrences as
  intervals.

  The rule's recurrence (`recurrence/1`) is evaluated against the year, so a
  rule that `prepare/1` has already built is projected without building or
  parsing anything. A rule with no standalone recurrence — a bridge or
  `if`-holiday move, an equinox or solstice outside UTC — is computed kind by
  kind instead (`materialise_concrete/2`).

  Most holidays fall exactly once a year, but a lunar-calendar holiday can
  fall zero, one or two times within a single Gregorian year — Eid al-Fitr
  fell twice in 2000 — so the result is a list, earliest first.

  ### Arguments

  * `rule` is a `t:t/0`.

  * `year` is a year-resolution Gregorian `t:Tempo.t/0` such as `~o"2026"`.

  ### Returns

  * `{:ok, [Tempo.t()]}` — the holiday's spans in that Gregorian
    year, earliest first. Usually one; empty when the rule does not fall in
    the year, two for a lunar holiday that recurs within it. A conditional
    rule (a bridge day, an `if`-holiday move) gives its spans before the
    condition, which only its holiday set can resolve, when it converts to its
    occurrences.

  * `{:error, reason}` when the rule cannot be projected.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("12-25")
      iex> {:ok, [interval]} = Tempo.Holidays.Rule.materialise(rule, ~o"2026")
      iex> Tempo.Interval.from(interval)
      ~o"2026Y12M25D"

  """
  @spec materialise(t(), Tempo.t()) :: {:ok, [Tempo.t()]} | {:error, term()}
  def materialise(%__MODULE__{} = rule, %Tempo{} = year) do
    case built_recurrence(rule) do
      :needs_window -> materialise_concrete(rule, year)
      _recurrence -> materialise_recurrence(base_of(rule), year)
    end
  end

  # A conditional rule alone is its base: the condition reads the rule's
  # holiday set, which resolves it when the set converts to its occurrences.
  defp base_of(%__MODULE__{conditional: nil} = rule), do: built_recurrence(rule)

  defp base_of(%__MODULE__{} = rule) do
    case base_recurrence(rule) do
      {:ok, base} -> base
      _needs_window_or_error -> :needs_window
    end
  end

  @doc """
  Project a rule onto a Gregorian `year` by computing its kind directly, without
  its recurrence.

  This is how `materialise/2` projects a rule that has no standalone recurrence.
  For one that has, it is a second, independent computation of the same
  occurrences — the check that `recurrence/1` is exact.

  ### Arguments

  * `rule` is a `t:t/0`.

  * `year` is a year-resolution Gregorian `t:Tempo.t/0` such as `~o"2026"`.

  ### Returns

  * `{:ok, [Tempo.t()]}` — the holiday's spans in that Gregorian
    year, earliest first, as for `materialise/2`.

  * `{:error, reason}` when the rule cannot be projected.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("12-25")
      iex> {:ok, [interval]} = Tempo.Holidays.Rule.materialise_concrete(rule, ~o"2026")
      iex> Tempo.Interval.from(interval)
      ~o"2026Y12M25D"

  """
  @spec materialise_concrete(t(), Tempo.t()) :: {:ok, [Tempo.t()]} | {:error, term()}
  def materialise_concrete(%__MODULE__{} = rule, %Tempo{} = year) do
    with {:ok, occurrences} <- gather_occurrences(rule, year) do
      move_disabled(occurrences, rule, year)
    end
  end

  @doc """
  Returns the rule with its recurrence built and attached.

  `materialise/2` evaluates a rule's recurrence, so a prepared rule — which
  carries it — is projected onto any number of years without its recurrence
  being built or parsed again. `Tempo.Holidays.Data` prepares every rule it
  loads.

  ### Arguments

  * `rule` is a `t:t/0`.

  ### Returns

  * The `t:t/0` with `:recurrence` set to its recurrence, or to `:needs_window`
    when it has no standalone recurrence (see `recurrence/1`).

  ### Examples

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("12-25")
      iex> prepared = Tempo.Holidays.Rule.prepare(rule)
      iex> Tempo.to_iso8601!(prepared.recurrence)
      "R/../P1Y/FL12M25DN"

  """
  @spec prepare(t()) :: t()
  def prepare(%__MODULE__{recurrence: nil} = rule),
    do: %{
      rule
      | recurrence: build_recurrence(rule),
        observed: observed_forms(rule),
        years: entry_years(rule)
    }

  def prepare(%__MODULE__{} = rule), do: rule

  # The recurrences a substitution rule has under `dates: :substitute` and
  # `:gazetted`, where they differ from its own: an `and if …` rule moves to its
  # substitute day under the first, and any substitution is dropped under the
  # second, whose caller leaves out a substitute entry.
  defp observed_forms(%__MODULE__{substitute: [_ | _] = clauses} = rule) do
    gazetted =
      if substitute_only?(clauses),
        do: %{},
        else: %{gazetted: build_recurrence(%{rule | substitute: nil})}

    substitute =
      if Enum.any?(clauses, &(elem(&1, 3) == :add)),
        do: %{
          substitute: build_recurrence(%{rule | substitute: Enum.map(clauses, &move_added/1)})
        },
        else: %{}

    Map.merge(gazetted, substitute)
  end

  defp observed_forms(_rule), do: nil

  # The years a substitute entry is in force, which each holiday it stands in
  # for reads (`replacement_pieces/1`).
  defp entry_years(rule) do
    with true <- substitute_entry?(rule),
         {:ok, ranges} <- active_ranges(rule) do
      ranges
    else
      _not_an_entry_or_no_ranges -> nil
    end
  end

  # A prepared rule carries its recurrence; an unprepared one builds it here.
  defp built_recurrence(%__MODULE__{recurrence: nil} = rule), do: build_recurrence(rule)
  defp built_recurrence(%__MODULE__{recurrence: recurrence}), do: recurrence

  # The rule's recurrence, or `:needs_window` for a rule that has none (a
  # recurrence that cannot be constructed is computed concretely as well).
  defp build_recurrence(rule) do
    case recurrence(rule) do
      {:ok, recurrence} -> recurrence
      _needs_window_or_error -> :needs_window
    end
  end

  # The `:within` window keeps every occurrence that overlaps it, so a span still
  # running from December is in January's window too. A holiday belongs to the
  # year it starts in, as date-holidays counts it.
  defp materialise_recurrence(recurrence, year) do
    with {:ok, set} <- Tempo.to_interval(recurrence, within: year) do
      target = Tempo.year(year)

      {:ok, Enum.filter(IntervalSet.members(set), &(gregorian_year(Interval.from(&1)) == target))}
    end
  end

  @doc """
  Returns the rule as a re-materialisable recurrence, the member
  `Tempo.Holidays.holidays/2` gives its holiday.

  A holiday that falls on one date a year — a fixed date, an nth weekday, a
  calendar date, a computed event — is a single `%Tempo.Interval{}` recurrence
  that projects onto any window. Its gates are part of the recurrence: a
  `since`/`until` range, an `active` window and an every-N-years cadence fold into
  the `{…}` year domain (`to_year` is exclusive, the half-open `[from, to)`
  convention), an even/odd/leap rule into the domain's filter, and a weekday gate
  into a weekday limit (`FL5M4D{2..6}KN`). A domain is in its recurrence's
  calendar, so the gates of a rule of another calendar are written in that
  calendar's years, and one with an even/odd/leap rule or an every-N-years
  cadence, which count Gregorian years, has no recurrence. A holiday with an observed-date
  substitution is several recurrences at once — the date itself on the weekdays
  that keep it, and a §12.10 window off the date for each clause that moves it
  (`FLLL12M25D{6..7}KN/P8DN1K-1IN`, "the following Monday when Christmas falls on a
  weekend") — so it is a recurrence set (`Tempo.RecurrenceSet`), as is a
  `disable`/`enable` move, whose moved date is a member of its own. Both
  materialise the same way, through `Tempo.to_interval/2` with a `:within`
  window. Every recurrence is built from its parts (`Tempo.every/2`), never
  written as text and read.

  A bridge or `if`-holiday move depends on the year's other holidays, so it is a
  conditional member wrapping the rule's own recurrence —
  `Tempo.RecurrenceSet.keep_when/2` with offsets to the named dates,
  `Tempo.RecurrenceSet.move_when/2` to the next target weekday — resolved when
  its holiday set materialises. A rule no recurrence expresses exactly returns
  `:needs_window`, and the caller materialises it concretely against a window.

  ### Arguments

  * `rule` is a `t:t/0`.

  * `options` is a keyword list of options.

  ### Options

  * `:falls_on` is what a conditional rule's holidays are read from: a map
    their metadata holds, or a `t:Tempo.t/0` of their recurrences. The
    default is `%{type: type}`, the type the rule names.

  ### Returns

  * `{:ok, recurrence}` with a `t:Tempo.t/0`: a recurrence, a recurrence set
    of them, or a conditional member for a conditional rule.

  * `:needs_window` when the rule needs a window to materialise.

  * `{:error, reason}` when the recurrence cannot be constructed.

  ### Examples

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("12-25")
      iex> {:ok, recurrence} = Tempo.Holidays.Rule.recurrence(rule)
      iex> Tempo.to_iso8601!(recurrence)
      "R/../P1Y/FL12M25DN"

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("12-25 since 2020 until 2025")
      iex> {:ok, recurrence} = Tempo.Holidays.Rule.recurrence(rule)
      iex> Tempo.to_iso8601!(recurrence)
      "R/{2020Y..2024Y}/P1Y/FL12M25DN"

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("12-25 and if saturday, sunday then next monday")
      iex> {:ok, recurrence} = Tempo.Holidays.Rule.recurrence(rule)
      iex> recurrence |> Tempo.RecurrenceSet.members() |> Enum.map(&Tempo.to_iso8601!/1)
      ["R/../P1Y/FL12M25DN", "R/../P1Y/FLL12M25D{6..7}KN/P8D1K-1IN"]

  """
  @spec recurrence(t(), keyword()) :: {:ok, Tempo.t()} | :needs_window | {:error, term()}
  def recurrence(rule, options \\ [])

  # A prepared rule already carries its recurrence (see `prepare/1`).
  def recurrence(%__MODULE__{recurrence: :needs_window}, _options), do: :needs_window

  def recurrence(%__MODULE__{recurrence: %Tempo{} = recurrence}, []), do: {:ok, recurrence}

  # A conditional rule (a bridge day, an `if is … holiday then …` move) depends on
  # the year's other holidays: its base recurrence is a conditional member of the
  # holiday set, resolved against the others when the set materialises. The
  # holidays it reads are those of a type (`falls_on: %{type: :public}`), or
  # `:falls_on`, a set of their recurrences, where those of its type are left
  # out of the set.
  def recurrence(%__MODULE__{conditional: conditional} = rule, options)
      when not is_nil(conditional) do
    falls_on = Keyword.get(options, :falls_on, %{type: conditional.type})

    with {:ok, base} <- base_recurrence(rule) do
      conditional_recurrence(base, conditional, rule, falls_on)
    end
  end

  def recurrence(%__MODULE__{} = rule, _options) do
    with {:ok, shapes} <- occurrence_shapes(rule),
         {:ok, domain} <- year_domain(rule),
         members = Enum.map(shapes, &shape_member(&1, domain)),
         {:ok, members} <- moved_members(members, rule),
         {:ok, recurrences} <- reduce_ok(members, &member_recurrence(&1, rule)) do
      {:ok, assemble(Enum.reject(recurrences, &is_nil/1))}
    end
  end

  @doc """
  Returns a rule's recurrence before any condition: what a bridge day or an
  `if`-holiday move is where the other holidays leave it alone.

  ### Arguments

  * `rule` is a `t:t/0`.

  ### Returns

  * `{:ok, recurrence}`, `:needs_window` or `{:error, reason}`, as
    `recurrence/2` returns them.

  ### Examples

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("09-22 if 09-21 and 09-23 is public holiday")
      iex> {:ok, base} = Tempo.Holidays.Rule.base_recurrence(rule)
      iex> Tempo.to_iso8601!(base)
      "R/../P1Y/FL9M22DN"

  """
  @spec base_recurrence(t()) :: {:ok, Tempo.t()} | :needs_window | {:error, term()}
  def base_recurrence(%__MODULE__{} = rule),
    do: recurrence(%{rule | conditional: nil, recurrence: nil})

  # ── conditional members ───────────────────────────────────────────────

  # A bridge keeps its day when every named date is a holiday of its type
  # (`PostRule.bridge`). The dates become offsets from the base date, exact when
  # each is in the base's own month.
  defp conditional_recurrence(
         base,
         %{kind: :bridge, on: on},
         %__MODULE__{kind: :fixed, month: month, day: day},
         falls_on
       ) do
    if Enum.all?(on, fn {on_month, _on_day} -> on_month == month end),
      do: bridge_member(base, on, day, falls_on),
      else: :needs_window
  end

  # An if-holiday moves an occurrence that falls on a holiday of its type to the
  # next target weekday (`PostRule.ruleIfHoliday` with a single `next` step).
  defp conditional_recurrence(
         base,
         %{kind: :if_holiday, move: %{count: 1, direction: :next, target: weekday, omit: []}},
         _rule,
         falls_on
       )
       when weekday in 1..7 do
    with {:ok, selector} <- Tempo.new(day_of_week: weekday) do
      {:ok, Tempo.RecurrenceSet.move_when(base, falls_on: falls_on, to_next: selector)}
    end
  end

  defp conditional_recurrence(_base, _conditional, _rule, _falls_on), do: :needs_window

  defp bridge_member(base, on, day, falls_on) do
    with {:ok, offsets} <-
           reduce_ok(on, fn {_month, on_day} -> Duration.new(day: on_day - day) end) do
      {:ok, Tempo.RecurrenceSet.keep_when(base, at: offsets, falls_on: falls_on)}
    end
  end

  # ── occurrence shapes ─────────────────────────────────────────────────
  #
  # A shape is what a recurrence selects in each year — the parts of its
  # selection and the calendar they are in — tagged `:base` (the holiday's own
  # date, which a multi-day span extends) or `:observed` (a substituted day).
  # The year domain is given to each when the members are built.

  # An ungated rule is its base alone.
  defp occurrence_shapes(
         %__MODULE__{substitute: substitute, weekday_gate: nil, replaced_by: replaced} = rule
       )
       when substitute in [nil, []] and replaced in [nil, []] do
    with {:ok, shape} <- base_shape(rule), do: {:ok, [{:base, shape}]}
  end

  # Easter falls on a Sunday, so a moveable feast's weekday is fixed and a gate
  # or substitution resolves statically — the observed day is another offset.
  defp occurrence_shapes(%__MODULE__{kind: kind} = rule) when kind in [:easter, :orthodox] do
    {:ok, easter_gated_shapes(rule)}
  end

  # A weekday gate, a substitution or a substitute entry limits the plain date
  # the holiday falls on to weekdays, and opens each observed-day window from it.
  defp occurrence_shapes(%__MODULE__{} = rule) do
    case plain_anchor(rule) do
      {:ok, anchor, calendar} -> gated(rule, anchor, calendar)
      :none -> :needs_window
    end
  end

  defp gated(rule, anchor, calendar) do
    with {:ok, pieces} <- replacement_pieces(rule) do
      {:ok, gated_shapes(rule, anchor, calendar, pieces)}
    end
  end

  defp shape(parts, calendar \\ Calendar.ISO), do: %{parts: parts, calendar: calendar}

  defp days(count), do: Duration.new!(day: count)

  defp base_shape(%__MODULE__{kind: :weekday} = rule), do: {:ok, weekday_shape(rule)}

  # A weekday relative to a fixed date — "Monday before 06-01", "Friday after
  # 06-19". An ISO 8601-2 §12.10 window off the anchor date picks the count-th
  # target weekday in the direction; taking the window off the real date lets
  # Tempo resolve the month boundary and leap years, so the recurrence stays
  # year-independent.
  defp base_shape(%__MODULE__{
         kind: :relative_weekday,
         month: month,
         day: day,
         weekday: target,
         direction: direction,
         count: count
       }) do
    {:ok,
     shape(
       [selection: [month: month, day: day]] ++
         relative_weekday_window(direction, count || 1, target)
     )}
  end

  # A weekday relative to an nth weekday-in-month — "Friday after the 4th
  # Thursday in November" (Black Friday), "Tuesday after the 1st Monday in
  # November" (US Election Day). The inner nth weekday is the anchor; a §12.10
  # window off it picks the outer weekday.
  defp base_shape(%__MODULE__{
         kind: :nested_weekday,
         month: month,
         inner_weekday: inner,
         weekday: outer,
         direction: direction,
         count: count
       }) do
    inner_weekday = [month: month, day_of_week: inner, instance: count]
    {:ok, shape([selection: inner_weekday] ++ relative_weekday_window(direction, 1, outer))}
  end

  # A weekday relative to the nth weekday after a fixed date — "Thursday after the
  # 1st Sunday after 09-01" (Jeûne genevois), "Monday after the 3rd Sunday after
  # 09-01". The inner weekday is a §12.10 window off the date, as for a relative
  # weekday, and the outer weekday a window off that one.
  defp base_shape(%__MODULE__{
         kind: :nested_after_date,
         month: month,
         day: day,
         inner_weekday: inner,
         weekday: outer,
         count: count
       }) do
    inner_date =
      [selection: [month: month, day: day]] ++ relative_weekday_window(:after, count, inner)

    {:ok, shape([selection: inner_date] ++ relative_weekday_window(:after, 1, outer))}
  end

  # Easter itself, or a moveable feast a fixed offset from it (Ash Wednesday −46,
  # Ascension +39, …) as a §12.10 window off `(easter)e`. A multi-day span
  # (`count > 1`) is added by `apply_span/2`.
  defp base_shape(%__MODULE__{kind: kind, offset: offset}) when kind in [:easter, :orthodox] do
    {:ok, easter_shape(kind, offset || 0)}
  end

  defp base_shape(%__MODULE__{} = rule) do
    case plain_anchor(rule) do
      {:ok, anchor, calendar} -> {:ok, shape(anchor, calendar)}
      :none -> offset_base_shape(rule)
    end
  end

  # A day at or beyond the Islamic month's length (date-holidays' `30 Ramadan`,
  # `30 Safar`) is the sunset-convention rollover: the 1st of the month plus
  # `day - 1` days, which becomes the next month's 1st when the month is short.
  # Declaratively that is the final day of the `day`-long window from the 1st —
  # `{1..7}K-1I` picks the window's last day regardless of weekday — reproducing
  # the same in-calendar arithmetic `materialise/2` uses, never forming an
  # out-of-range date.
  defp offset_base_shape(%__MODULE__{kind: :islamic, calendar: calendar, month: month, day: day})
       when is_integer(day) and day >= 30 do
    window = [window: days(day), day_of_week: 1..7, instance: -1]
    {:ok, shape([selection: [month: month, day: 1]] ++ window, calendar)}
  end

  # A lunisolar day-offset folds into the day (`net_day = day + offset`), so `day
  # 1` shifted `-1` and a `day 0` are the same eve. At or before the eve it is a
  # backward window off the traditional month's 1st, whose first day (`{1..7}K1I`,
  # the earliest regardless of weekday) lands `net_day - 1` days before it.
  defp offset_base_shape(%__MODULE__{
         kind: :lunisolar,
         calendar: calendar,
         month: month,
         day: day,
         leap_month: leap_month,
         offset: offset
       })
       when is_integer(month) and is_integer(day) do
    case day + (offset || 0) do
      net_day when net_day <= 0 ->
        first_day = [traditional_month: traditional_month(month, leap_month), day: 1]
        window = [window: days(-(1 - net_day)), day_of_week: 1..7, instance: 1]
        {:ok, shape([selection: first_day] ++ window, calendar)}

      _later_day ->
        :needs_window
    end
  end

  defp offset_base_shape(%__MODULE__{}), do: :needs_window

  # The plain date a rule falls on, as a selection with any calendar suffix — the
  # anchor a weekday gate limits and a substitution opens its window from. A
  # calendar date is a `[u-ca=…]` selection; a lunisolar date is a
  # traditional-month `m` selection (`<month>+m` for a leap month), whose
  # traditional→ordinal step and Gregorian-year attribution resolve per year at
  # materialisation; a Chinese solar term, and an equinox or solstice in its
  # zone, are computed events. `:none` for a kind whose date is itself a window
  # off another, that needs a concrete projection (a shifted or
  # non-Chinese-meridian solar term), or whose calendar has no faithful
  # `[u-ca=…]` identifier. Easter and its feasts never come here — their weekday
  # is fixed, so their gates resolve statically.
  defp plain_anchor(%__MODULE__{kind: :fixed, month: month, day: day}),
    do: {:ok, [month: month, day: day], Calendar.ISO}

  defp plain_anchor(%__MODULE__{kind: kind, calendar: calendar, day: day} = rule)
       when kind in [:hebrew, :persian] do
    {:ok, [month_part(rule), day: day], calendar}
  end

  defp plain_anchor(%__MODULE__{kind: :julian, month: month, day: day}),
    do: {:ok, [month: month, day: day], Calendrical.Julian}

  defp plain_anchor(%__MODULE__{kind: :islamic, calendar: calendar, month: month, day: day})
       when is_integer(day) and day <= 29 do
    {:ok, [month: month, day: day], calendar}
  end

  defp plain_anchor(%__MODULE__{kind: kind, month: month, offset: offset, timezone: timezone})
       when kind in [:equinox, :solstice] and offset in [nil, 0] do
    case {solar_event_name(kind, month), event_zone(timezone)} do
      {nil, _zone} -> :none
      {_event, :error} -> :none
      {event, {:ok, zone}} -> {:ok, [event: {event, zone}], Calendar.ISO}
    end
  end

  defp plain_anchor(%__MODULE__{kind: :solar_term, calendar: calendar, count: term, day: day})
       when calendar in [nil, Calendrical.Chinese] and day in [nil, 1] do
    # A solar term is asked of a calendar that has them. Tempo's default
    # calendar has none, so the event is named in the Gregorian calendar,
    # whose years and days are the ones the term is a date of.
    case Calendrical.Lunisolar.solar_term_name(term) do
      {:ok, name} -> {:ok, [event: name], Calendrical.Gregorian}
      {:error, _reason} -> :none
    end
  end

  defp plain_anchor(%__MODULE__{
         kind: :lunisolar,
         calendar: calendar,
         month: month,
         day: day,
         leap_month: leap_month,
         offset: offset
       })
       when is_integer(month) and is_integer(day) do
    case day + (offset || 0) do
      net_day when net_day >= 1 ->
        {:ok, [traditional_month: traditional_month(month, leap_month), day: net_day], calendar}

      _eve ->
        :none
    end
  end

  defp plain_anchor(%__MODULE__{}), do: :none

  defp traditional_month(month, true), do: {month, :leap}
  defp traditional_month(month, _leap_month), do: month

  # A Hebrew month is named by its traditional number (`<n>m`, and `5+m` for
  # Adar I), which Tempo resolves to its position in each year; a Persian
  # month keeps its ordinal number.
  defp month_part(%__MODULE__{kind: :hebrew, month: month, leap_month: leap_month}),
    do: {:traditional_month, traditional_month(month, leap_month)}

  defp month_part(%__MODULE__{month: month}), do: {:month, month}

  defp solar_event_name(:equinox, 3), do: "march-equinox"
  defp solar_event_name(:equinox, 9), do: "september-equinox"
  defp solar_event_name(:solstice, 6), do: "june-solstice"
  defp solar_event_name(:solstice, 12), do: "december-solstice"
  defp solar_event_name(_kind, _month), do: nil

  # The zone an equinox or solstice takes its date in: none for UTC, and a
  # `±HH:MM` offset or an IANA zone as written. An IANA zone resolves through the
  # application's time zone database, which tempo_holidays requires.
  defp event_zone(timezone) when timezone in [nil, "GMT", "UTC"], do: {:ok, nil}

  defp event_zone(<<sign, _hours::binary-size(2), ?:, _minutes::binary-size(2)>> = offset)
       when sign in [?+, ?-],
       do: {:ok, offset}

  defp event_zone(timezone) when is_binary(timezone) do
    if String.contains?(timezone, "/"), do: {:ok, timezone}, else: :error
  end

  defp event_zone(_timezone), do: :error

  defp easter_event(:orthodox), do: "orthodox-easter"
  defp easter_event(:easter), do: "easter"

  defp easter_shape(kind, 0), do: shape(event: easter_event(kind))

  defp easter_shape(kind, offset),
    do: shape([selection: [event: easter_event(kind)]] ++ easter_offset_window(offset))

  # The §12.10 window that picks `easter + offset` off `(easter)e`: a forward
  # window taking the last occurrence of the target weekday for a positive
  # offset, a backward window taking the first for a negative one. Easter is a
  # Sunday (ISO weekday 7), so the weekday is `mod(6 + offset, 7) + 1`.
  defp easter_offset_window(offset) when offset > 0,
    do: [window: days(offset + 1), day_of_week: easter_offset_weekday(offset), instance: -1]

  defp easter_offset_window(offset),
    do: [window: days(offset - 1), day_of_week: easter_offset_weekday(offset), instance: 1]

  defp easter_offset_weekday(offset), do: Integer.mod(6 + offset, 7) + 1

  # The §12.10 window that picks the count-th `target` weekday relative to an
  # anchor date: a backward window taking the earliest for "before", a forward
  # window taking the latest for "after" (which is on-or-after the anchor).
  defp relative_weekday_window(:before, count, target),
    do: [window: days(-7 * count), day_of_week: target, instance: 1]

  defp relative_weekday_window(:after, count, target),
    do: [window: days(7 * count), day_of_week: target, instance: -1]

  # ── weekday gates and observed-date substitution ─────────────────────

  # The date itself is kept on the weekdays that keep it — the gate's, less those
  # a clause moves (unless the clause adds the observed day rather than moving
  # to it), and none when a `substitutes` clause did not fire — and each clause
  # that fires is a §12.10 window off the date, limited to its weekdays. A
  # substitute entry standing in for the date takes its weekdays away in the
  # years it is in force, so the date is a member for each run of years that
  # keeps the same weekdays.
  defp gated_shapes(rule, anchor, calendar, pieces) do
    {kept, observed} = substitution_plan(rule.substitute || [], gate_weekdays(rule.weekday_gate))

    base =
      for {ranges, replaced} <- pieces, weekdays = kept -- replaced, weekdays != [] do
        {:base, limited_shape(anchor, calendar, weekdays), ranges}
      end

    windows =
      for {weekdays, direction, target} <- observed, weekdays != [] do
        {:observed, observed_shape(anchor, calendar, weekdays, direction, target)}
      end

    base ++ windows
  end

  defp gate_weekdays(nil), do: @all_weekdays
  defp gate_weekdays({:only, weekdays}), do: Enum.filter(@all_weekdays, &(&1 in weekdays))
  defp gate_weekdays({:except, weekdays}), do: Enum.reject(@all_weekdays, &(&1 in weekdays))

  # Walk the clauses in order, as `substitute_all/2` does: each fires on the
  # allowed weekdays no earlier clause claimed. Returns the weekdays that keep the
  # date, and each clause's `{weekdays, direction, target}`.
  defp substitution_plan(clauses, allowed) do
    {observed, claimed, added} =
      Enum.reduce(clauses, {[], [], []}, fn {triggers, direction, target, mode},
                                            {observed, claimed, added} ->
        fires = Enum.filter(allowed, &(&1 in triggers and &1 not in claimed))
        added = if mode == :add, do: added ++ fires, else: added
        {observed ++ [{fires, direction, target}], claimed ++ triggers, added}
      end)

    untriggered =
      if substitute_only?(clauses), do: [], else: Enum.reject(allowed, &(&1 in claimed))

    {Enum.sort(untriggered ++ added), observed}
  end

  defp substitute_only?(clauses), do: Enum.any?(clauses, &(elem(&1, 3) == :substitute_only))

  defp limited_shape(anchor, calendar, @all_weekdays), do: shape(anchor, calendar)

  defp limited_shape(anchor, calendar, weekdays),
    do: shape(anchor ++ [day_of_week: weekday_set(weekdays)], calendar)

  defp observed_shape(anchor, calendar, weekdays, direction, target) do
    limit = if weekdays == @all_weekdays, do: [], else: [day_of_week: weekday_set(weekdays)]
    shape([selection: anchor ++ limit] ++ observed_window(direction, target), calendar)
  end

  # date-holidays observes a clause's target weekday strictly after (or before)
  # the date — a full week on when it is the date's own weekday — which is the
  # last `target` in the eight days from the date, or the first in the seven
  # days before it.
  defp observed_window(:next, target), do: [window: days(8), day_of_week: target, instance: -1]

  defp observed_window(:previous, target),
    do: [window: days(-7), day_of_week: target, instance: 1]

  # A weekday set as a selection holds it: a single weekday bare, consecutive
  # runs as ranges — `{6..7}`, `{1..5}`, `{1,3..5}`.
  defp weekday_set([weekday]), do: weekday
  defp weekday_set(weekdays), do: weekdays |> weekday_runs() |> Enum.map(&weekday_run/1)

  defp weekday_runs(weekdays) do
    Enum.chunk_while(weekdays, [], &extend_run/2, &close_run/1)
  end

  defp extend_run(weekday, [previous | _] = run) when weekday == previous + 1,
    do: {:cont, [weekday | run]}

  defp extend_run(weekday, []), do: {:cont, [weekday]}
  defp extend_run(weekday, run), do: {:cont, Enum.reverse(run), [weekday]}

  defp close_run([]), do: {:cont, []}
  defp close_run(run), do: {:cont, Enum.reverse(run), []}

  defp weekday_run([first, _second | _rest] = run), do: first..List.last(run)
  defp weekday_run([weekday]), do: weekday

  # Easter is a Sunday, so a feast `offset` days from it falls on a fixed weekday:
  # a gate either always or never admits it, and the first clause that fires on
  # that weekday moves it to another fixed offset.
  defp easter_gated_shapes(%__MODULE__{kind: kind, offset: offset} = rule) do
    offset = offset || 0
    weekday = easter_offset_weekday(offset)

    if weekday in gate_weekdays(rule.weekday_gate),
      do: easter_substituted(kind, offset, weekday, rule.substitute || []),
      else: []
  end

  defp easter_substituted(kind, offset, weekday, clauses) do
    clauses
    |> Enum.find(fn {triggers, _direction, _target, _mode} -> weekday in triggers end)
    |> easter_observed(kind, offset, weekday, clauses)
  end

  defp easter_observed(nil, kind, offset, _weekday, clauses) do
    if substitute_only?(clauses), do: [], else: [{:base, easter_shape(kind, offset)}]
  end

  defp easter_observed({_triggers, direction, target, mode}, kind, offset, weekday, _clauses) do
    observed =
      {:observed, easter_shape(kind, offset + observed_shift(weekday, direction, target))}

    if mode == :add, do: [{:base, easter_shape(kind, offset)}, observed], else: [observed]
  end

  # The days from a date on `weekday` to the clause's observed day — strictly
  # after or before, a full week when the target is the date's own weekday.
  defp observed_shift(weekday, :next, target),
    do: nonzero_shift(Integer.mod(target - weekday, 7), 7)

  defp observed_shift(weekday, :previous, target),
    do: nonzero_shift(-Integer.mod(weekday - target, 7), -7)

  # ── substitute entries ───────────────────────────────────────────────

  # The runs of years a rule's date keeps different weekdays in, each with the
  # weekdays taken from it: a substitute entry takes its trigger weekdays in the
  # years its own gates allow, decided on this rule's date as `active_ranges/1`
  # decides any window. With no entry, every year keeps every weekday.
  defp replacement_pieces(%__MODULE__{replaced_by: replaced}) when replaced in [nil, []],
    do: {:ok, [{[{nil, nil}], []}]}

  defp replacement_pieces(%__MODULE__{replaced_by: replaced} = rule) do
    with {:ok, spans} <- reduce_ok(replaced, &replacement_span(rule, &1)) do
      pieces =
        spans
        |> year_runs()
        |> Enum.map(&{&1, replaced_in(&1, spans)})
        |> Enum.chunk_by(&elem(&1, 1))
        |> Enum.map(&join_runs/1)

      {:ok, pieces}
    end
  end

  defp replacement_span(_rule, %{triggers: triggers, years: years}) when is_list(years),
    do: {:ok, {years, triggers}}

  defp replacement_span(rule, %{triggers: triggers} = entry) do
    gated = %{rule | from_year: entry.from_year, to_year: entry.to_year, active: entry.active}

    with {:ok, ranges} <- active_ranges(gated), do: {:ok, {ranges, triggers}}
  end

  # The runs of years between every bound the entries' ranges name.
  defp year_runs(spans) do
    bounds =
      spans
      |> Enum.flat_map(fn {ranges, _triggers} -> Enum.flat_map(ranges, &range_bounds/1) end)
      |> Enum.uniq()
      |> Enum.sort()

    Enum.zip([nil | bounds], Enum.map(bounds, &(&1 - 1)) ++ [nil])
  end

  defp range_bounds({from, to}), do: Enum.reject([from, to && to + 1], &is_nil/1)

  # The weekdays taken from a run by the entries in force through it. The runs
  # split at every range's bounds, so each lies wholly inside a range or wholly
  # outside it.
  defp replaced_in(run, spans) do
    spans
    |> Enum.filter(fn {ranges, _triggers} -> Enum.any?(ranges, &covers?(&1, run)) end)
    |> Enum.flat_map(fn {_ranges, triggers} -> triggers end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Consecutive runs that keep the same weekdays are one run of years.
  defp join_runs([{{from, _to}, weekdays} | _rest] = runs) do
    {{_from, to}, _weekdays} = List.last(runs)
    {[{from, to}], weekdays}
  end

  defp covers?({from, to}, {run_from, run_to}),
    do: not_before?(run_from, from) and not_after?(run_to, to)

  defp not_before?(_year, nil), do: true
  defp not_before?(nil, _from), do: false
  defp not_before?(year, from), do: year >= from

  defp not_after?(_year, nil), do: true
  defp not_after?(nil, _to), do: false
  defp not_after?(year, to), do: year <= to

  # The weekdays a substitute entry takes from the date in `year`, as a weekday
  # gate for the concrete path.
  defp replaced_gate(%__MODULE__{replaced_by: replaced}, _year) when replaced in [nil, []],
    do: {:ok, nil}

  defp replaced_gate(rule, year) do
    with {:ok, pieces} <- replacement_pieces(rule) do
      {:ok, {:except, replaced_in_year(pieces, year)}}
    end
  end

  defp replaced_in_year(pieces, year) do
    for {ranges, weekdays} <- pieces,
        Enum.any?(ranges, &covers?(&1, {year, year})),
        weekday <- weekdays,
        do: weekday
  end

  # ── the year domain ───────────────────────────────────────────────────

  # The rule's year gates as a recurrence domain: the inclusive year ranges it is
  # active in (`since`/`until`, intersected with any `active` windows), the years
  # a disabled date excludes (added per member by `moved_members/2`), an
  # even/odd/leap/common filter, and the cadence of an every-N-years rule.
  defp year_domain(%__MODULE__{} = rule) do
    with {:ok, filter} <- domain_filter(rule),
         {:ok, ranges} <- active_ranges(rule),
         {:ok, cadence} <- domain_cadence(rule, ranges) do
      {:ok, %{ranges: ranges, exclusions: [], filter: filter, cadence: cadence}}
    end
  end

  # A domain carries one filter, so a rule both even/odd and leap or non-leap
  # stays concrete.
  defp domain_filter(%__MODULE__{year_parity: parity, leap: leap})
       when not is_nil(parity) and not is_nil(leap),
       do: :needs_window

  defp domain_filter(%__MODULE__{year_parity: :even}), do: {:ok, :even}
  defp domain_filter(%__MODULE__{year_parity: :odd}), do: {:ok, :odd}
  defp domain_filter(%__MODULE__{leap: :leap}), do: {:ok, :leap}
  defp domain_filter(%__MODULE__{leap: :non_leap}), do: {:ok, :common}
  defp domain_filter(%__MODULE__{}), do: {:ok, nil}

  # Every N years counts from the `since` year, so the domain must start there.
  defp domain_cadence(%__MODULE__{every_years: nil}, _ranges), do: {:ok, 1}

  defp domain_cadence(%__MODULE__{every_years: every, from_year: from}, [{from, _to}])
       when is_integer(every) and is_integer(from),
       do: {:ok, every}

  defp domain_cadence(%__MODULE__{}, _ranges), do: :needs_window

  # `since`/`until` is an inclusive year range (`to_year` is exclusive). An
  # `active` window is date-precise, but a holiday that falls once a year is
  # inside it exactly in the years its date is, so each window becomes the range
  # of years whose occurrence it contains — decided at the window's first and
  # last year by materialising the base there — intersected with `since`/`until`.
  defp active_ranges(%__MODULE__{active: active} = rule) when active in [nil, []] do
    {:ok, rule |> since_until_range() |> intersect_ranges({nil, nil}) |> List.wrap()}
  end

  defp active_ranges(%__MODULE__{active: active} = rule) do
    with {:ok, windows} <- reduce_ok(active, &window_year_range(rule, &1)) do
      {:ok, Enum.flat_map(windows, &List.wrap(intersect_ranges(&1, since_until_range(rule))))}
    end
  end

  defp since_until_range(%__MODULE__{from_year: from, to_year: nil}), do: {from, nil}
  defp since_until_range(%__MODULE__{from_year: from, to_year: to}), do: {from, to - 1}

  # A window whose first or last year cannot be decided leaves the rule without a
  # recurrence, so it is computed concretely instead.
  defp window_year_range(rule, window) do
    case active_year_range(rule, window) do
      :needs_window -> {:error, :needs_window}
      decided -> decided
    end
  end

  defp active_year_range(rule, {from_date, to_date}) do
    with {:ok, first} <- first_active_year(rule, from_date),
         {:ok, last} <- last_active_year(rule, to_date) do
      {:ok, {first, last}}
    end
  end

  defp first_active_year(_rule, nil), do: {:ok, nil}

  defp first_active_year(rule, %Date{year: year} = from) do
    rule
    |> base_days_in(year)
    |> first_year_from(year, Date.to_gregorian_days(from))
  end

  defp first_year_from({:ok, [days]}, year, from_days),
    do: {:ok, if(days >= from_days, do: year, else: year + 1)}

  defp first_year_from({:ok, []}, year, _from_days), do: {:ok, year + 1}
  defp first_year_from(_other, _year, _from_days), do: :needs_window

  defp last_active_year(_rule, nil), do: {:ok, nil}

  defp last_active_year(rule, %Date{year: year} = to) do
    rule
    |> base_days_in(year)
    |> last_year_before(year, Date.to_gregorian_days(to))
  end

  defp last_year_before({:ok, [days]}, year, to_days),
    do: {:ok, if(days < to_days, do: year, else: year - 1)}

  defp last_year_before({:ok, []}, year, _to_days), do: {:ok, year - 1}
  defp last_year_before(_other, _year, _to_days), do: :needs_window

  # The Gregorian day counts of the rule's base occurrences in `year`.
  defp base_days_in(rule, year) do
    with {:ok, tempo} <- Tempo.new(year: year),
         {:ok, occurrences} <- materialise_base(rule, tempo) do
      reduce_ok(occurrences, &occurrence_day_count/1)
    end
  end

  defp occurrence_day_count(interval) do
    case occurrence_days(interval) do
      {:ok, days} -> {:ok, days}
      :error -> {:error, :no_gregorian_date}
    end
  end

  # Two inclusive year ranges' overlap (`nil` is an open end), or `nil` when
  # they do not meet.
  defp intersect_ranges({from_1, to_1}, {from_2, to_2}) do
    from = later_year(from_1, from_2)
    to = earlier_year(to_1, to_2)
    if is_integer(from) and is_integer(to) and from > to, do: nil, else: {from, to}
  end

  defp later_year(nil, year), do: year
  defp later_year(year, nil), do: year
  defp later_year(year_1, year_2), do: max(year_1, year_2)

  defp earlier_year(nil, year), do: year
  defp earlier_year(year, nil), do: year
  defp earlier_year(year_1, year_2), do: min(year_1, year_2)

  # ── disable / enable moves ────────────────────────────────────────────

  # date-holidays' `disable`/`enable` move an occurrence (`move_disabled/3`): where
  # a disabled date is one of the rule's occurrences that year, it is dropped and
  # the year's enabled dates are added in its place. Declaratively, the member
  # producing the disabled date excludes that year from its domain and each
  # enabled date is a one-year member of its own — as is any occurrence the
  # excluded member still keeps that year (a lunar holiday falling twice in it,
  # only one of them disabled).
  defp moved_members(members, %__MODULE__{disable: disable}) when disable in [nil, []],
    do: {:ok, members}

  defp moved_members(members, %__MODULE__{disable: disable, enable: enable}) do
    blocked = MapSet.new(disable, &Date.to_gregorian_days/1)

    disable
    |> Enum.map(& &1.year)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, members}, fn year, {:ok, acc} ->
      case move_year(acc, year, blocked, enable || []) do
        {:ok, moved} -> {:cont, {:ok, moved}}
        other -> {:halt, other}
      end
    end)
  end

  defp move_year(members, year, blocked, enable) do
    with {:ok, matches} <- reduce_ok(members, &member_match(&1, year, blocked)) do
      apply_move(matches, members, year, enable)
    end
  end

  defp apply_move(matches, members, year, enable) do
    if Enum.any?(matches, &match?({:matched, _kept}, &1)) do
      moved =
        members
        |> Enum.zip(matches)
        |> Enum.flat_map(&moved_member(&1, year))

      {:ok, moved ++ enabled_members(enable, year)}
    else
      {:ok, members}
    end
  end

  defp moved_member({member, :none}, _year), do: [member]

  defp moved_member({member, {:matched, kept}}, year),
    do: [exclude_year(member, year) | kept_members(member, kept)]

  # Whether any of a member's occurrences in `year` is disabled — `{:matched,
  # kept}` with the day counts of the ones it keeps — or none is (`:none`).
  defp member_match(member, year, blocked) do
    with {:ok, days} <- member_days_in(member, year) do
      case Enum.split_with(days, &MapSet.member?(blocked, &1)) do
        {[], _kept} -> {:ok, :none}
        {_matched, kept} -> {:ok, {:matched, kept}}
      end
    end
  end

  # The occurrences a member keeps in a year it is excluded from, each a one-year
  # member on its Gregorian date, in the member's role.
  defp kept_members(%{role: role}, kept_days) do
    for days <- kept_days do
      date = Date.from_gregorian_days(days)
      member(role, shape(month: date.month, day: date.day), single_year_domain(date.year))
    end
  end

  defp member_days_in(member, year) do
    case built_member(member) do
      {:ok, recurrence} -> days_in(recurrence, year)
      :never -> {:ok, []}
      {:error, _reason} = error -> error
    end
  end

  defp days_in(recurrence, year) do
    with {:ok, window} <- Tempo.new(year: year),
         {:ok, set} <- Tempo.to_interval(recurrence, within: window) do
      set
      |> IntervalSet.members()
      |> reduce_ok(&occurrence_day_count/1)
    end
  end

  defp exclude_year(%{domain: domain} = member, year),
    do: %{member | domain: %{domain | exclusions: [year | domain.exclusions]}}

  defp enabled_members(enable, year) do
    for %Date{year: ^year, month: month, day: day} <- enable do
      member(:enabled, shape(month: month, day: day), single_year_domain(year))
    end
  end

  defp single_year_domain(year),
    do: %{ranges: [{year, year}], exclusions: [], filter: nil, cadence: 1}

  # ── members ───────────────────────────────────────────────────────────

  defp member(role, shape, domain), do: %{role: role, shape: shape, domain: domain}

  # A shape limited to runs of years takes only those years of the domain.
  defp shape_member({role, shape}, domain), do: member(role, shape, domain)

  defp shape_member({role, shape, ranges}, domain),
    do: member(role, shape, %{domain | ranges: intersect_range_lists(domain.ranges, ranges)})

  defp intersect_range_lists(ranges, others) do
    for range <- ranges,
        other <- others,
        overlap = intersect_ranges(range, other),
        overlap != nil,
        do: overlap
  end

  # A member whose domain admits no year never occurs, so it is dropped.
  defp member_recurrence(%{role: role} = member, rule) do
    case built_member(role_shape(member, rule)) do
      {:ok, recurrence} -> {:ok, Tempo.put_metadata(recurrence, role_metadata(role, rule))}
      :never -> {:ok, nil}
      {:error, _reason} = error -> error
    end
  end

  # The base carries the holiday's span; an observed day is marked, as
  # date-holidays marks the substitute it reports.
  defp role_shape(%{role: :base, shape: shape} = member, rule),
    do: %{member | shape: apply_span(shape, rule)}

  defp role_shape(member, _rule), do: member

  # A rule of another calendar than the Gregorian says so on each of its
  # members, the date a `disable`/`enable` move gives it among them. A set of
  # occurrences is in one calendar, so the day of an Islamic holiday beside
  # Gregorian ones is a Gregorian day, and the rule's calendar is what is left
  # to say that its day begins at sunset (`Tempo.Holidays.day_start/2`).
  defp role_metadata(role, %__MODULE__{calendar: calendar}) do
    observed = if role == :observed, do: %{substitute: true}, else: %{}
    in_calendar = if is_atom(calendar) and calendar != nil, do: %{calendar: calendar}, else: %{}
    Map.merge(observed, in_calendar)
  end

  # A member's recurrence: `:never` for a member whose domain admits no year,
  # and an error where its gates have no form in the calendar of its shape.
  defp built_member(%{domain: %{ranges: []}}), do: :never

  defp built_member(%{shape: shape, domain: domain}) do
    with {:ok, domain} <- domain_of_shape(domain, shape) do
      every_year(domain, shape)
    end
  end

  defp every_year(%{ranges: []}, _shape), do: :never

  defp every_year(domain, %{parts: parts, calendar: calendar}) do
    with {:ok, from} <- domain_set(domain, calendar) do
      options =
        [select: parts, calendar: calendar]
        |> with_option(:from, from)
        |> with_option(:years, domain.filter)

      Tempo.every(days_of_years(domain.cadence), options)
    end
  end

  defp days_of_years(cadence), do: Duration.new!(year: cadence)

  defp with_option(options, _key, nil), do: options
  defp with_option(options, key, value), do: Keyword.put(options, key, value)

  # ── a gate in the calendar of its shape ───────────────────────────────

  # A rule's gates are Gregorian years: date-holidays computes one Gregorian
  # year at a time, so `since 1997`, a disabled date and an `active` window all
  # say which Gregorian years a holiday is in. A recurrence is in one calendar,
  # its domain with it, so where a member's shape is of another calendar
  # (`[u-ca=hebrew]`) each gate is converted when the member is built. A
  # Gregorian year becomes the years of the shape's calendar whose occurrence
  # starts in it, which Tempo is asked for: `12 Cheshvan … since 1997` is
  # `{5758Y..}`, and the year a disabled date excludes is the year, or the two,
  # whose occurrence of the shape falls in it.
  #
  # An even/odd or leap filter and an every-N-years step count Gregorian years
  # and have no form in another calendar, so such a rule has no recurrence and
  # is computed concretely.
  defp domain_of_shape(
         %{ranges: [{nil, nil}], exclusions: [], filter: nil, cadence: 1} = domain,
         _shape
       ) do
    {:ok, domain}
  end

  defp domain_of_shape(domain, %{calendar: calendar} = shape),
    do: domain_in(domain, shape, calendar)

  # The Gregorian years the gates are in are the years of a Gregorian shape.
  defp domain_in(domain, _shape, calendar)
       when calendar in [Calendar.ISO, Calendrical.Gregorian] do
    {:ok, domain}
  end

  defp domain_in(%{filter: filter, cadence: cadence}, _shape, _calendar)
       when filter != nil or cadence != 1 do
    {:error, :needs_window}
  end

  defp domain_in(%{ranges: ranges, exclusions: exclusions} = domain, shape, calendar) do
    with {:ok, ranges} <- reduce_ok(ranges, &range_in(&1, shape, calendar)),
         {:ok, excluded} <- reduce_ok(exclusions, &years_in(&1, shape, calendar)) do
      ranges = Enum.reject(ranges, &empty_range?/1)
      {:ok, %{domain | ranges: ranges, exclusions: List.flatten(excluded)}}
    end
  end

  # An inclusive range of Gregorian years, as the range of years of the shape's
  # calendar whose occurrences start in it.
  defp range_in({from, to}, shape, calendar) do
    with {:ok, first} <- first_year_on_or_after(from, shape, calendar),
         {:ok, next} <- first_year_on_or_after(year_after(to), shape, calendar) do
      {:ok, {first, year_before(next)}}
    end
  end

  # A Gregorian year, as the years of the shape's calendar whose occurrences
  # start in it: none, one or two.
  defp years_in(year, shape, calendar) do
    with {:ok, {first, last}} <- range_in({year, year}, shape, calendar) do
      {:ok, Enum.to_list(first..last//1)}
    end
  end

  defp year_after(nil) do
    nil
  end

  defp year_after(year) do
    year + 1
  end

  defp year_before(nil) do
    nil
  end

  defp year_before(year) do
    year - 1
  end

  defp empty_range?({from, to}) when is_integer(from) and is_integer(to) do
    from > to
  end

  defp empty_range?(_open_at_an_end) do
    false
  end

  # The first year of the shape's calendar whose occurrence starts on or after
  # 1 January of a Gregorian year. The year of that calendar the day is in, the
  # one before it and the one after it are each asked for their occurrence: an
  # occurrence is in its own year or beside it, and a later year's is later.
  defp first_year_on_or_after(nil, _shape, _calendar) do
    {:ok, nil}
  end

  defp first_year_on_or_after(year, shape, calendar) do
    with {:ok, new_year} <- Date.new(year, 1, 1),
         {:ok, there} <- year_in_calendar(new_year, calendar) do
      years = [there - 1, there, there + 1]
      sides_of(years, shape, date_days(new_year))
    end
  end

  defp sides_of(years, shape, boundary) do
    with {:ok, sides} <- reduce_ok(years, &side_of(&1, shape, boundary)) do
      years
      |> Enum.zip(sides)
      |> first_after()
    end
  end

  defp year_in_calendar(%Date{} = date, calendar) do
    with {:ok, day} <- Tempo.from_elixir(date),
         {:ok, there} <- Tempo.to_calendar(day, calendar) do
      {:ok, Tempo.year(there)}
    end
  end

  # Whether a year's occurrence starts before a day, on or after it, or the
  # year has none. A year with occurrences on both sides of the day has no
  # place in a range of years.
  defp side_of(year, shape, boundary) do
    with {:ok, starts} <- starts_in(year, shape) do
      starts
      |> Enum.split_with(&(&1 < boundary))
      |> side()
    end
  end

  defp side({[], []}) do
    {:ok, :none}
  end

  defp side({[_ | _], []}) do
    {:ok, :before}
  end

  defp side({[], [_ | _]}) do
    {:ok, :after}
  end

  defp side({_before, _after}) do
    {:error, :needs_window}
  end

  # The day counts of the occurrences a shape has in one year of its calendar.
  defp starts_in(year, shape) do
    with {:ok, recurrence} <- every_year(single_year_domain(year), shape),
         {:ok, set} <- Tempo.to_interval(recurrence) do
      set
      |> IntervalSet.members()
      |> reduce_ok(&occurrence_day_count/1)
    end
  end

  # The first year whose occurrence starts on or after the day. Where none of
  # the years asked has one, it is the year after the last whose occurrence
  # starts before it, or the first of the years asked.
  defp first_after([{earliest, _side} | _rest] = sides) do
    on_or_after =
      for {year, :after} <- sides do
        year
      end

    before =
      for {year, :before} <- sides do
        year
      end

    first_of(on_or_after, before, earliest)
  end

  defp first_of([_ | _] = on_or_after, _before, _earliest) do
    {:ok, Enum.min(on_or_after)}
  end

  defp first_of([], [_ | _] = before, _earliest) do
    {:ok, Enum.max(before) + 1}
  end

  defp first_of([], [], earliest) do
    {:ok, earliest}
  end

  # One member is the recurrence itself; several are a recurrence set.
  defp assemble([recurrence]), do: recurrence
  defp assemble(recurrences), do: Tempo.RecurrenceSet.new!(recurrences)

  # A domain as the set of years a recurrence starts in: none when it is every
  # year, else its ranges of years less the years it excludes. A fully open
  # domain cannot hold an exclusion (`{..,^2020Y}` is not a set), so it is
  # split around the excluded years instead (`{..2019Y,2021Y..}`).
  defp domain_set(%{ranges: [{nil, nil}], exclusions: []}, _calendar), do: {:ok, nil}

  defp domain_set(%{ranges: [{nil, nil}], exclusions: exclusions} = domain, calendar),
    do: domain_set(%{domain | ranges: split_open_range(exclusions), exclusions: []}, calendar)

  defp domain_set(%{ranges: ranges, exclusions: exclusions}, calendar) do
    with {:ok, members} <- reduce_ok(ranges, &range_member(&1, calendar)),
         {:ok, excluded} <-
           reduce_ok(Enum.sort(exclusions), &Tempo.new(year: &1, calendar: calendar)) do
      IntervalSet.new(members, except: excluded)
    end
  end

  defp range_member({nil, to}, calendar) do
    with {:ok, last} <- Tempo.new(year: to, calendar: calendar),
         do: Interval.new(from: :open, to: last)
  end

  defp range_member({from, nil}, calendar) do
    with {:ok, first} <- Tempo.new(year: from, calendar: calendar),
         do: Interval.new(from: first, to: :open)
  end

  defp range_member({year, year}, calendar), do: Tempo.new(year: year, calendar: calendar)
  defp range_member({from, to}, calendar), do: Tempo.new(year: from..to, calendar: calendar)

  defp split_open_range(exclusions) do
    years = exclusions |> Enum.uniq() |> Enum.sort()
    starts = [nil | Enum.map(years, &(&1 + 1))]
    ends = Enum.map(years, &(&1 - 1)) ++ [nil]

    starts
    |> Enum.zip(ends)
    |> Enum.reject(fn {from, to} -> is_integer(from) and is_integer(to) and from > to end)
  end

  # A multi-day holiday (`count > 1`) spans that many days from each occurrence:
  # a §12.10 window of that length from the day its shape selects, however that
  # day resolves — a plain date, a calendar date, a computed event, an Islamic
  # rollover, or a lunisolar eve all take the same span. Only the holiday's own
  # date takes it — an observed day is a single day, as `materialise/2`
  # observes it — and only `@span_kinds` treat `count` as a span.
  defp apply_span(%{parts: parts} = shape, %__MODULE__{kind: kind, count: count})
       when kind in @span_kinds and is_integer(count) and count > 1 do
    %{shape | parts: [selection: parts, window: days(count)]}
  end

  defp apply_span(shape, _rule), do: shape

  @doc """
  Whether a rule is a substitute entry: date-holidays' `substitutes …`, which
  gives a holiday's substitute day and nothing on the holiday's own date.

  ### Arguments

  * `rule` is a `t:t/0`.

  ### Returns

  * `true` when the rule is a substitute entry, `false` otherwise.

  ### Examples

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("substitutes 12-26 if saturday then next monday")
      iex> Tempo.Holidays.Rule.substitute_entry?(rule)
      true

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("12-26 and if saturday then next monday")
      iex> Tempo.Holidays.Rule.substitute_entry?(rule)
      false

  """
  @spec substitute_entry?(t()) :: boolean()
  def substitute_entry?(%__MODULE__{substitute: [_ | _] = clauses}), do: substitute_only?(clauses)
  def substitute_entry?(%__MODULE__{}), do: false

  @doc """
  Whether a substitute entry stands in for a rule's own date.

  It does when both name the same single day in the same way — a fixed date, a
  calendar date, a weekday in a month — and the rule has no substitution of its
  own. An entry dated in one named year (Korea's Seollal and Chuseok overlaps)
  names no recurring holiday's date, so its substitute day is an extra one.

  ### Arguments

  * `entry` is a substitute entry, a `t:t/0`.

  * `rule` is the `t:t/0` it may stand in for.

  ### Returns

  * `true` when `entry` stands in for `rule`'s date, `false` otherwise.

  ### Examples

      iex> {:ok, entry} = Tempo.Holidays.Compiler.compile("substitutes 12-26 if saturday then next monday")
      iex> {:ok, boxing_day} = Tempo.Holidays.Compiler.compile("12-26")
      iex> Tempo.Holidays.Rule.substitutes?(entry, boxing_day)
      true

  """
  @spec substitutes?(t(), t()) :: boolean()
  def substitutes?(%__MODULE__{} = entry, %__MODULE__{} = rule) do
    substitute_entry?(entry) and plain_date?(rule) and year_gated_only?(entry) and
      date_rule(entry) == date_rule(rule)
  end

  def substitutes?(_entry, _rule), do: false

  # The fields that name the date a rule falls on before any gate or
  # substitution, and whether it is the date of one named year.
  @date_fields [
    :kind,
    :month,
    :day,
    :count,
    :weekday,
    :inner_weekday,
    :direction,
    :offset,
    :calendar,
    :leap_month,
    :timezone
  ]

  defp date_rule(rule), do: {Map.take(rule, @date_fields), one_year?(rule)}

  defp one_year?(%__MODULE__{from_year: from, to_year: to}),
    do: is_integer(from) and to == from + 1

  # A single day with no substitution or condition of its own. Easter's feasts
  # fall on fixed weekdays, so their substitutions resolve statically instead.
  defp plain_date?(%__MODULE__{kind: kind, count: count, substitute: clauses, conditional: nil})
       when kind not in [:easter, :orthodox] and count in [nil, 1] and clauses in [nil, []],
       do: true

  defp plain_date?(_rule), do: false

  # An entry's years are its `since`/`until` and `active` windows alone.
  defp year_gated_only?(%__MODULE__{} = entry) do
    is_nil(entry.every_years) and is_nil(entry.year_parity) and is_nil(entry.leap) and
      is_nil(entry.weekday_gate) and entry.disable in [nil, []] and entry.enable in [nil, []] and
      is_nil(entry.conditional)
  end

  @doc """
  Returns the rule as `Tempo.Holidays.holidays/2`'s `:dates` option observes it.

  `:both` is the rule as date-holidays gives it. `:gazetted` keeps the holiday on
  its own date alone, with no substitution. `:substitute` observes it on its
  substitute day where there is one: an `and if …` rule, which gives both days,
  moves to its substitute day instead, and each substitute entry standing in
  for its date (`substitutes?/2`) takes the date away on the weekdays and in
  the years it gives a substitute day. A substitute entry itself is left to the
  caller, which drops it under `:gazetted`.

  ### Arguments

  * `rule` is a `t:t/0`.

  * `dates` is `:substitute`, `:gazetted` or `:both`.

  * `entries` are the substitute entries of the rule's holiday list.

  ### Returns

  * The `t:t/0`, its recurrence rebuilt when anything changed.

  ### Examples

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("12-25 and if saturday, sunday then next monday")
      iex> {:ok, recurrence} = rule |> Tempo.Holidays.Rule.observe(:substitute, []) |> Tempo.Holidays.Rule.recurrence()
      iex> recurrence |> Tempo.RecurrenceSet.members() |> Enum.map(&Tempo.to_iso8601!/1)
      ["R/../P1Y/FL12M25D{1..5}KN", "R/../P1Y/FLL12M25D{6..7}KN/P8D1K-1IN"]

  """
  @spec observe(t(), :substitute | :gazetted | :both, [t()]) :: t()
  def observe(%__MODULE__{} = rule, :both, _entries), do: rule

  def observe(%__MODULE__{substitute: clauses} = rule, :gazetted, _entries)
      when clauses in [nil, []],
      do: rule

  def observe(%__MODULE__{} = rule, :gazetted, _entries),
    do: %{rule | substitute: nil, recurrence: observed_recurrence(rule, :gazetted)}

  def observe(%__MODULE__{} = rule, :substitute, entries) do
    rule
    |> moved_not_added()
    |> with_replacements(Enum.filter(entries, &substitutes?(&1, rule)))
  end

  # `and if …` observes a holiday on its date and on the substitute day; the
  # substitute day standing in for the date is a move.
  defp moved_not_added(%__MODULE__{substitute: [_ | _] = clauses} = rule) do
    if Enum.any?(clauses, &(elem(&1, 3) == :add)) do
      moved = Enum.map(clauses, &move_added/1)
      %{rule | substitute: moved, recurrence: observed_recurrence(rule, :substitute)}
    else
      rule
    end
  end

  defp moved_not_added(rule), do: rule

  # The recurrence `prepare/1` built for the observed rule, or `nil` for one it
  # did not prepare, which `recurrence/1` then builds.
  defp observed_recurrence(%__MODULE__{observed: %{} = observed}, dates),
    do: Map.get(observed, dates)

  defp observed_recurrence(_rule, _dates), do: nil

  defp move_added({triggers, direction, target, :add}), do: {triggers, direction, target, :shift}
  defp move_added(clause), do: clause

  defp with_replacements(rule, []), do: rule

  defp with_replacements(rule, entries),
    do: %{rule | replaced_by: Enum.map(entries, &replacement/1), recurrence: nil}

  defp replacement(%__MODULE__{substitute: clauses} = entry) do
    triggers = clauses |> Enum.flat_map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()

    %{
      triggers: triggers,
      years: entry.years,
      from_year: entry.from_year,
      to_year: entry.to_year,
      active: entry.active
    }
  end

  @doc """
  Joins a period date-holidays splits over the year end.

  date-holidays cannot run a period past the year end, so it writes one as two
  dated entries under one name: a December part that ends as the year does, or
  a day before it, and a January part from the 1st. Victoria's summer school
  holidays are written this way.

  ### Arguments

  * `december` is the December part, a `t:t/0`.

  * `january` is the `t:t/0` that may continue it.

  ### Returns

  * `{:ok, rule}` — the December part spanning both, 31 December included.

  * `:error` when `january` does not continue `december`.

  ### Examples

      iex> {:ok, december} = Tempo.Holidays.Compiler.compile("2026-12-19 P12D")
      iex> {:ok, january} = Tempo.Holidays.Compiler.compile("2027-01-01 P27D")
      iex> {:ok, summer} = Tempo.Holidays.Rule.join_year_end(december, january)
      iex> summer.count
      40

  """
  @spec join_year_end(t(), t()) :: {:ok, t()} | :error
  def join_year_end(
        %__MODULE__{kind: :fixed, month: 12} = december,
        %__MODULE__{kind: :fixed, month: 1, day: 1} = january
      ) do
    with true <- one_year?(december) and one_year?(january),
         true <- january.from_year == december.from_year + 1,
         {:ok, first} <- Date.new(december.from_year, 12, december.day),
         {:ok, new_year} <- Date.new(january.from_year, 1, 1),
         true <- (Date.diff(new_year, first) - (december.count || 1)) in [0, 1] do
      {:ok,
       %{december | count: Date.diff(new_year, first) + (january.count || 1), recurrence: nil}}
    else
      _other -> :error
    end
  end

  def join_year_end(_december, _january), do: :error

  @doc """
  Whether a rule carries an inter-holiday `t:conditional/0`.

  A conditional rule (a *bridge* day, or an `if is … holiday then …` move)
  depends on the *other* holidays of the year, so it cannot be materialised in
  isolation — `materialise/2` yields its base occurrences and the second pass
  (`resolve_conditional/4`) turns them on, off or moves them.

  ### Arguments

  * `rule` is a `t:t/0`.

  ### Returns

  * `true` when the rule has a conditional, `false` otherwise.

  ### Examples

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("12-25")
      iex> Tempo.Holidays.Rule.conditional?(rule)
      false

      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("09-22 if 09-21 and 09-23 is public holiday")
      iex> Tempo.Holidays.Rule.conditional?(rule)
      true

  """
  @spec conditional?(t()) :: boolean()
  def conditional?(%__MODULE__{conditional: nil}), do: false
  def conditional?(%__MODULE__{}), do: true

  @doc """
  Resolve a conditional rule's base occurrences against the year's holidays.

  The second pass of materialisation. `present?` answers whether a holiday of a
  given `t:Tempo.Holidays.Holiday.type/0` falls on a Gregorian day count in the
  year — the caller builds it from the year's other holidays. A `:bridge` keeps
  its occurrences only when every named date is present; an `:if_holiday` moves
  each occurrence that coincides with a present holiday, and leaves the rest.

  ### Arguments

  * `rule` is a conditional `t:t/0` (see `conditional?/1`).

  * `occurrences` are the rule's base occurrences from `materialise/2`.

  * `year` is the year-resolution `t:Tempo.t/0` being projected.

  * `present?` is a `(gregorian_days, type) -> boolean()` function.

  ### Returns

  * `{:ok, [Tempo.t()]}` — the resolved occurrences, possibly empty
    (a bridge whose conditions are not met) or moved (an if-holiday coincidence).

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("09-22 if 09-21 and 09-23 is public holiday")
      iex> {:ok, base} = Tempo.Holidays.Rule.materialise(rule, ~o"2026")
      iex> Tempo.Holidays.Rule.resolve_conditional(rule, base, ~o"2026", fn _days, _type -> false end)
      {:ok, []}

  """
  @spec resolve_conditional(t(), [Tempo.t()], Tempo.t(), (integer(), atom() -> boolean())) ::
          {:ok, [Tempo.t()]} | {:error, term()}
  def resolve_conditional(
        %__MODULE__{conditional: %{kind: :bridge} = conditional},
        occurrences,
        year,
        present?
      ) do
    if bridge_satisfied?(conditional, year, present?), do: {:ok, occurrences}, else: {:ok, []}
  end

  def resolve_conditional(
        %__MODULE__{conditional: %{kind: :if_holiday} = conditional},
        occurrences,
        _year,
        present?
      ) do
    reduce_ok(occurrences, &move_if_holiday(&1, conditional, present?))
  end

  # A bridge keeps its day only when every named date is itself a holiday of the
  # conditional's type that year (`PostRule.bridge`).
  defp bridge_satisfied?(%{on: on, type: type}, year, present?) do
    target = Tempo.year(year)

    Enum.all?(on, fn {month, day} ->
      case Date.new(target, month, day) do
        {:ok, date} -> present?.(Date.to_gregorian_days(date), type)
        {:error, _} -> false
      end
    end)
  end

  # An if-holiday moves an occurrence that coincides with a holiday of the type,
  # and leaves one that does not (`PostRule.ruleIfHoliday`).
  defp move_if_holiday(interval, %{type: type, move: move}, present?) do
    case occurrence_days(interval) do
      {:ok, days} ->
        if present?.(days, type),
          do: days |> Date.from_gregorian_days() |> apply_move(move) |> enabled_interval(),
          else: {:ok, interval}

      :error ->
        {:ok, interval}
    end
  end

  # date-holidays' `dateDir`: step `count` in `direction` to the `target`
  # weekday (or a plain `:day`, skipping `omit` weekdays). The arithmetic is in
  # JS weekday indices (Sunday 0 … Saturday 6) to mirror the reference exactly.
  defp apply_move(%Date{} = date, %{
         count: count,
         direction: direction,
         target: target,
         omit: omit
       }) do
    weekday = js_weekday(date)
    Date.add(date, move_offset(target, direction, count, weekday, Enum.map(omit, &js_index/1)))
  end

  defp js_weekday(%Date{} = date), do: js_index(Date.day_of_week(date))

  # ISO Monday 1 … Sunday 7 → JS Sunday 0 … Saturday 6.
  defp js_index(iso_weekday), do: rem(iso_weekday, 7)

  defp move_offset(:day, direction, count, weekday, omit) do
    {from, delta} = if backward?(direction), do: {-count, -1}, else: {count, +1}
    skip_omit(from, delta, weekday, omit, 0)
  end

  defp move_offset(target, direction, count, weekday, _omit) when is_integer(target) do
    rule_weekday = js_index(target)
    base = count - 1

    if backward?(direction) do
      steps = if weekday == rule_weekday, do: base + 1, else: base
      -(Integer.mod(7 + weekday - rule_weekday, 7) + steps * 7)
    else
      steps = if direction == :next and weekday == rule_weekday, do: base + 1, else: base
      Integer.mod(7 - weekday + rule_weekday, 7) + steps * 7
    end
  end

  defp backward?(direction), do: direction in [:before, :previous]

  # A `:day` move skips over any `omit` weekday, up to a week, mirroring the
  # reference's bounded `while`.
  defp skip_omit(offset, _delta, _weekday, _omit, tries) when tries >= 7, do: offset

  defp skip_omit(offset, delta, weekday, omit, tries) do
    if Integer.mod(offset + weekday, 7) in omit,
      do: skip_omit(offset + delta, delta, weekday, omit, tries + 1),
      else: offset
  end

  # Gather the occurrences before the `disable`/`enable` post-step. The common
  # case is a single year; a substituted rule that could cross the Gregorian
  # year boundary is materialised across the target year and its neighbours and
  # filtered back to the target.
  defp gather_occurrences(rule, year) do
    target = Tempo.year(year)

    case boundary_years(rule, target) do
      [_only] ->
        occurrences_for_year(rule, year)

      years ->
        with {:ok, groups} <- reduce_ok(years, &occurrences_for(rule, &1)) do
          {:ok, groups |> List.flatten() |> Enum.filter(&in_gregorian_year?(&1, target))}
        end
    end
  end

  # A substitution can push an observed date across the Gregorian year boundary
  # — New Year on a Saturday observed the previous Friday, 31 December — and
  # date-holidays attributes each observed date to the year it falls in. So a
  # substituted rule is materialised across the target year and its two
  # neighbours and then filtered to the target; an unsubstituted rule, whose
  # base always lands in its own year, needs only the target year.
  defp boundary_years(%__MODULE__{substitute: substitute}, target)
       when substitute in [nil, []],
       do: [target]

  defp boundary_years(rule, target) do
    if boundary_capable?(rule), do: [target - 1, target, target + 1], else: [target]
  end

  # A substitution shifts a date by at most a week, so it can only cross a
  # Gregorian year boundary when the holiday itself falls within a week of 1
  # January or 31 December. A fixed or weekday rule whose month is February
  # through November never can; Easter is always spring; everything else
  # (January/December, and calendars whose Gregorian date drifts year to year)
  # is treated conservatively as boundary-capable.
  defp boundary_capable?(%__MODULE__{kind: kind}) when kind in [:easter, :orthodox], do: false

  defp boundary_capable?(%__MODULE__{kind: kind, month: month})
       when kind in [:fixed, :weekday, :nested_weekday, :relative_weekday] and is_integer(month),
       do: month in [1, 12]

  defp boundary_capable?(_rule), do: true

  # A neighbouring year, built from its integer, for the boundary case.
  defp occurrences_for(rule, year_int) do
    with {:ok, year} <- Tempo.new(year: year_int) do
      occurrences_for_year(rule, year)
    end
  end

  # The per-year gates: the year conditions, active windows, weekday gate and
  # substitution. `disable`/`enable` are a separate post-step (see
  # `move_disabled/3`) applied once to the gathered occurrences.
  defp occurrences_for_year(rule, year) do
    if active_in_year?(rule, Tempo.year(year)) do
      with {:ok, base} <- materialise_base(rule, year),
           {:ok, replaced} <- replaced_gate(rule, Tempo.year(year)) do
        base
        |> filter_active(rule.active)
        |> gate_by_weekday(rule.weekday_gate)
        |> gate_by_weekday(replaced)
        |> substitute_all(rule.substitute)
      end
    else
      {:ok, []}
    end
  end

  defp in_gregorian_year?(interval, target) do
    case occurrence_days(interval) do
      {:ok, days} -> Date.from_gregorian_days(days).year == target
      :error -> false
    end
  end

  # `on <weekday>` keeps an occurrence only when it lands on one of those
  # weekdays; `not on <weekday>` drops it when it does.
  defp gate_by_weekday(intervals, nil), do: intervals

  defp gate_by_weekday(intervals, {mode, weekdays}) do
    Enum.filter(intervals, fn interval ->
      weekday = Tempo.day_of_week(Interval.from(interval), :monday)

      case mode do
        :only -> weekday in weekdays
        :except -> weekday not in weekdays
      end
    end)
  end

  # ── occurrence-level metadata gates: active / disable / enable ──────
  #
  # date-holidays' `active`, `disable` and `enable` metadata operate on the
  # rule's *computed* dates (see the upstream `docs/specification.md`), so they
  # are applied to the materialised occurrences, not gated at the year level.

  # `disable`/`enable` are a *move*, mirroring date-holidays' `PostRule.disable`:
  # only when a `disable` date equals a computed occurrence is that occurrence
  # dropped and the year's `enable` dates added in its place. A `disable` that
  # matches nothing — or an `enable` with no matching `disable` — does nothing.
  defp move_disabled(occurrences, %__MODULE__{disable: disable}, _year)
       when disable in [nil, []],
       do: {:ok, occurrences}

  defp move_disabled(occurrences, rule, year) do
    blocked = MapSet.new(rule.disable, &date_days/1)
    {matched, survivors} = Enum.split_with(occurrences, &disabled?(&1, blocked))

    if matched == [], do: {:ok, survivors}, else: append_enabled(survivors, rule.enable, year)
  end

  defp disabled?(interval, blocked) do
    case occurrence_days(interval) do
      {:ok, days} -> MapSet.member?(blocked, days)
      :error -> false
    end
  end

  # `active` restricts the rule to one or more half-open `[from, to)` windows;
  # an occurrence whose date falls outside every window is dropped.
  defp filter_active(intervals, nil), do: intervals

  defp filter_active(intervals, ranges) do
    Enum.filter(intervals, fn interval ->
      case occurrence_days(interval) do
        {:ok, days} -> Enum.any?(ranges, &within_range?(days, &1))
        :error -> false
      end
    end)
  end

  defp within_range?(days, {from, to}) do
    (is_nil(from) or days >= date_days(from)) and (is_nil(to) or days < date_days(to))
  end

  # `enable` adds explicit observed dates — the target of a disable/enable move
  # — materialised as single days, keeping only those in the requested year.
  defp append_enabled(intervals, nil, _year), do: {:ok, intervals}

  defp append_enabled(intervals, enabled, year) do
    target = Tempo.year(year)

    with {:ok, added} <-
           enabled |> Enum.filter(&(&1.year == target)) |> reduce_ok(&enabled_interval/1) do
      {:ok, intervals ++ added}
    end
  end

  defp enabled_interval(%Date{} = date) do
    with {:ok, day} <- Tempo.from_elixir(date), do: day |> Tempo.to_interval() |> first_interval()
  end

  @doc """
  An occurrence's start as a proleptic-Gregorian day count.

  A value in any calendar (an Islamic or Hebrew holiday) reduces to a single
  integer, so occurrences compare against each other and against the Gregorian
  `active`/`disable`/condition dates regardless of the calendar they are held
  in. Used to build the year's holiday-day set for the conditional second pass
  (`resolve_conditional/4`).

  ### Arguments

  * `interval` is one occurrence, an interval (a `t:Tempo.t/0`).

  ### Returns

  * `{:ok, integer()}` — the start date as a Gregorian day count.

  * `:error` when the value will not convert to a Gregorian date.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("12-25")
      iex> {:ok, [interval]} = Tempo.Holidays.Rule.materialise(rule, ~o"2026")
      iex> Tempo.Holidays.Rule.occurrence_days(interval)
      {:ok, 740340}

  """
  @spec occurrence_days(Tempo.t()) :: {:ok, integer()} | :error
  def occurrence_days(interval) do
    with tempo <- Interval.from(interval),
         {:ok, date} <- Tempo.to_date(tempo),
         {:ok, iso} <- Date.convert(date, Calendar.ISO) do
      {:ok, Date.to_gregorian_days(iso)}
    else
      _ -> :error
    end
  end

  defp date_days(%Date{} = date), do: Date.to_gregorian_days(date)

  # A `since <year>` / `prior to <year>` window, an even/odd-year filter, and a
  # leap/non-leap-year filter each gate the whole rule: when the year fails any
  # of them the holiday does not occur, so it materialises to nothing.
  defp active_in_year?(%__MODULE__{} = rule, year) do
    in_year_range?(rule.from_year, rule.to_year, year) and
      matches_parity?(rule.year_parity, year) and
      matches_leap?(rule.leap, year) and
      matches_every?(rule.every_years, rule.from_year, year)
  end

  defp matches_every?(nil, _from, _year), do: true
  defp matches_every?(n, from, year), do: rem(year - (from || year), n) == 0

  defp in_year_range?(from, to, year) do
    (is_nil(from) or year >= from) and (is_nil(to) or year < to)
  end

  defp matches_parity?(nil, _year), do: true
  defp matches_parity?(:even, year), do: rem(year, 2) == 0
  defp matches_parity?(:odd, year), do: rem(year, 2) == 1

  defp matches_leap?(nil, _year), do: true
  defp matches_leap?(:leap, year), do: Calendar.ISO.leap_year?(year)
  defp matches_leap?(:non_leap, year), do: not Calendar.ISO.leap_year?(year)

  defp materialise_base(
         %__MODULE__{kind: :fixed, month: month, day: day, count: count},
         %Tempo{} = year
       ) do
    with {:ok, selector} <- Tempo.new(month: month, day: day),
         {:ok, set} <- Tempo.select(year, selector),
         {:ok, start} <- first_value(set) do
      day_interval(start, count) |> wrap_one()
    end
  end

  defp materialise_base(%__MODULE__{kind: :weekday} = rule, %Tempo{} = year) do
    with {:ok, recurrence} <- yearly(weekday_shape(rule)),
         {:ok, set} <- Tempo.to_interval(recurrence, within: year) do
      case first_interval(set) do
        {:ok, interval} -> {:ok, [interval]}
        {:error, :no_occurrence} -> {:ok, []}
      end
    end
  end

  defp materialise_base(
         %__MODULE__{kind: :relative_weekday, weekday: target, direction: direction} = rule,
         %Tempo{} = year
       ) do
    with {:ok, anchor} <- Tempo.new(year: Tempo.year(year), month: rule.month, day: rule.day),
         shift =
           relative_shift(direction, Tempo.day_of_week(anchor, :monday), target, rule.count || 1),
         {:ok, day} <- Tempo.shift(anchor, day: shift) do
      day |> Tempo.to_interval() |> first_interval() |> wrap_one()
    end
  end

  # A nested weekday — "friday after 4th thursday in November" (Black Friday),
  # "Tuesday after 1st Monday in November" (US Election Day) — first places the
  # inner weekday-in-month, then steps to the outer weekday relative to it.
  defp materialise_base(
         %__MODULE__{kind: :nested_weekday, weekday: outer, inner_weekday: inner} = rule,
         %Tempo{} = year
       ) do
    inner_weekday = shape(month: rule.month, day_of_week: inner, instance: rule.count)

    with {:ok, recurrence} <- yearly(inner_weekday),
         {:ok, set} <- Tempo.to_interval(recurrence, within: year),
         {:ok, inner_interval} <- first_interval(set),
         anchor = Interval.from(inner_interval),
         shift = relative_shift(rule.direction, Tempo.day_of_week(anchor, :monday), outer, 1),
         {:ok, day} <- Tempo.shift(anchor, day: shift) do
      day |> Tempo.to_interval() |> first_interval() |> wrap_one()
    end
  end

  # "monday after 3rd sunday after 09-01": the Nth inner weekday on or after a
  # fixed date, then the outer weekday after that. Both steps use the inclusive
  # "after" that date-holidays applies.
  defp materialise_base(
         %__MODULE__{kind: :nested_after_date, weekday: outer, inner_weekday: inner} = rule,
         %Tempo{} = year
       ) do
    with {:ok, anchor} <- Tempo.new(year: Tempo.year(year), month: rule.month, day: rule.day),
         inner_shift =
           relative_shift(:after, Tempo.day_of_week(anchor, :monday), inner, rule.count),
         {:ok, inner_date} <- Tempo.shift(anchor, day: inner_shift),
         outer_shift = relative_shift(:after, Tempo.day_of_week(inner_date, :monday), outer, 1),
         {:ok, day} <- Tempo.shift(inner_date, day: outer_shift) do
      day |> Tempo.to_interval() |> first_interval() |> wrap_one()
    end
  end

  # A Hebrew or Persian fixed date, returned in its own calendar (`year` is the
  # *Gregorian* year). The yearly recurrence bounded to the year finds which
  # occurrences of the calendar date fall in it — zero, one, or (for a lunar
  # date, as Eid al-Fitr in 2000) two — declaratively, Tempo resolving the
  # calendar arithmetic. A `count` greater than one spans that many days.
  defp materialise_base(
         %__MODULE__{kind: kind, calendar: calendar, day: day, count: count} = rule,
         %Tempo{} = year
       )
       when kind in [:hebrew, :persian] do
    calendar_date_holiday(shape([month_part(rule), day: day], calendar), count, year)
  end

  # date-holidays encodes some Islamic holidays as a day *beyond* the month's
  # length — Saudi Eid al-Fitr as `30 Ramadan P4D`, Iran's end-of-Safar
  # observance as `30 Safar` — leaning on the sunset-convention rollover its
  # table gives (the spec's 18:00 day-start). Declared as the always-valid 1st
  # of the month plus a `day - 1` day offset, `Tempo.shift` reproduces the
  # rollover in-calendar (a 30th of a 29-day month becomes the next month's 1st)
  # without ever forming an out-of-range date.
  defp materialise_base(
         %__MODULE__{kind: :islamic, calendar: calendar, month: month, day: day, count: count},
         %Tempo{} = year
       ) do
    offset_calendar_holiday(shape([month: month, day: 1], calendar), day - 1, count, year)
  end

  # A lunisolar date — Chinese (`chinese …`), Korean (`korean …`) or Vietnamese
  # (`vietnamese …`). date-holidays writes `<month>-<leap>-<day>` in *traditional*
  # month numbering, which drifts from the calendar's ordinal months in a year
  # carrying an intercalary month, so Calendrical resolves the traditional month
  # to a Gregorian date; that is converted back into the source calendar (ordinal
  # months) and returned in-calendar.
  #
  # date-holidays attributes a lunar date to the Gregorian year it *falls in*, so
  # a late lunar month (Ông Táo, the 12th month) belongs to the Gregorian year
  # after its lunar new year. The candidate is therefore taken from each
  # neighbouring lunar year and filtered to the target Gregorian year — the same
  # convention `dates_in_gregorian_year/3` gives the Islamic and Hebrew tiers.
  defp materialise_base(
         %__MODULE__{kind: :lunisolar, calendar: calendar} = rule,
         %Tempo{} = year
       ) do
    target = Tempo.year(year)
    lunar_month = if rule.leap_month, do: {rule.month, :leap}, else: rule.month

    rule
    |> lunisolar_anchor_years(target)
    |> Enum.map(&calendar.gregorian_date_for_lunar(&1, lunar_month, rule.day))
    |> Enum.filter(&(&1.year == target))
    |> Enum.uniq()
    |> reduce_ok(&converted_interval(offset_date(&1, rule.offset), calendar, rule.count))
  end

  # A Chinese solar term — `chinese <term>-<day> solarterm`. `Calendrical`
  # resolves the 1-based term index to the Gregorian day the sun reaches its
  # ecliptic longitude, observed at the calendar's meridian (`calendar.location/1`);
  # nothing calendrical is computed here. `<day>` is a 1-based offset into the
  # term. Solar, so a Gregorian civil date. The meridian defaults to the Chinese
  # one when the rule carries no calendar — solar terms are Chinese-tradition —
  # so a missing calendar projects correctly rather than crashing on `nil`.
  defp materialise_base(
         %__MODULE__{kind: :solar_term, calendar: calendar, count: term, day: day},
         %Tempo{} = year
       ) do
    meridian = calendar || Calendrical.Chinese

    with {:ok, date} <-
           Calendrical.Lunisolar.solar_term(term, Tempo.year(year), &meridian.location(&1)),
         {:ok, start} <- Tempo.from_elixir(date),
         {:ok, day} <- Tempo.shift(start, day: day - 1) do
      day |> Tempo.to_interval() |> first_interval() |> wrap_one()
    end
  end

  # An equinox or solstice, its civil date in the rule's timezone (GMT when
  # none is named). Astro gives the UTC instant; a numeric offset (`+09:00`)
  # shifts it directly, and a named zone (`America/Santiago`) resolves through
  # the application's time zone database, as Tempo does. `offset` carries an
  # `<n> days before/after` adjustment.
  defp materialise_base(
         %__MODULE__{kind: kind, month: month, offset: offset, timezone: timezone},
         %Tempo{} = year
       )
       when kind in [:equinox, :solstice] do
    with {:ok, utc} <- solar_event_utc(kind, month, Tempo.year(year)),
         {:ok, date} <- solar_event_date(utc, timezone),
         {:ok, base} <- Tempo.from_elixir(date),
         {:ok, day} <- Tempo.shift(base, day: offset || 0) do
      day |> Tempo.to_interval() |> first_interval() |> wrap_one()
    end
  end

  # A Julian fixed date (Orthodox Christmas et al.). date-holidays writes these
  # as `julian MM-DD`. The occurrence is returned in the Julian calendar like
  # every other calendar tier, and the yearly recurrence bounded to the
  # Gregorian year does the projection declaratively.
  defp materialise_base(
         %__MODULE__{kind: :julian, month: month, day: day, count: count},
         %Tempo{} = year
       ) do
    calendar_date_holiday(shape([month: month, day: day], Calendrical.Julian), count, year)
  end

  defp materialise_base(%__MODULE__{kind: kind, offset: offset, count: count}, %Tempo{} = year)
       when kind in [:easter, :orthodox] do
    computed_event_holiday(easter_event(kind), offset, count, year)
  end

  # A date of another calendar, projected onto the Gregorian `year`
  # declaratively: its yearly recurrence bounded to the year yields every
  # occurrence that falls in it — zero, one, or (for a calendar whose year
  # drifts against the Gregorian one) two — each in its own calendar. `count`
  # greater than one extends the span to that many days. Tempo resolves the
  # calendar arithmetic, so nothing here computes a date.
  defp calendar_date_holiday(shape, count, %Tempo{} = year) do
    with {:ok, recurrence} <- yearly(shape),
         {:ok, set} <- Tempo.to_interval(recurrence, within: year) do
      set
      |> IntervalSet.members()
      |> reduce_ok(&day_interval(Interval.from(&1), count))
    end
  end

  # A calendar date declared as the 1st of its month plus a day `offset`. The
  # 1st always exists, so `Tempo.shift/2` can reach the intended day — and roll
  # a day beyond the month's length into the next month — without ever forming
  # an out-of-range date. The 1st is materialised across the neighbouring years
  # too, because the offset can carry the day across the Gregorian boundary; an
  # occurrence is kept when its own Gregorian projection lands in `year`, a lunar
  # date still able to fall in it twice. `count` extends the span.
  defp offset_calendar_holiday(first_of_month, offset, count, %Tempo{} = year) do
    target = Tempo.year(year)

    with {:ok, first} <- Tempo.new(year: target - 1),
         {:ok, last} <- Tempo.new(year: target + 1),
         {:ok, window} <- Interval.new(from: first, to: last),
         {:ok, recurrence} <- yearly(first_of_month),
         {:ok, set} <- Tempo.to_interval(recurrence, within: window),
         {:ok, starts} <-
           reduce_ok(IntervalSet.members(set), &Tempo.shift(Interval.from(&1), day: offset)) do
      starts
      |> Enum.filter(fn start -> gregorian_year(start) == target end)
      |> Enum.uniq()
      |> reduce_ok(&day_interval(&1, count))
    end
  end

  # A holiday fixed by a computed event (`(easter)e`, `(orthodox-easter)e`) plus
  # a day `offset`. The whole calendar computation is delegated to `Tempo.Event`
  # (and Calendrical/Astro beneath it): the event recurrence bounded to the year
  # resolves the event's date, `Tempo.shift` applies the offset, and `count`
  # extends the span. Nothing here computes a date.
  defp computed_event_holiday(event, offset, count, %Tempo{} = year) do
    with {:ok, recurrence} <- yearly(shape(event: event)),
         {:ok, set} <- Tempo.to_interval(recurrence, within: year),
         {:ok, starts} <-
           reduce_ok(IntervalSet.members(set), &Tempo.shift(Interval.from(&1), day: offset || 0)) do
      reduce_ok(starts, &day_interval(&1, count))
    end
  end

  # A recurrence of every year from its shape, with no start.
  defp yearly(%{parts: parts, calendar: calendar}),
    do: Tempo.every(days_of_years(1), select: parts, calendar: calendar)

  # One day-resolution value becomes its interval, spanning `count` days.
  defp day_interval(%Tempo{} = start, count) when count in [nil, 1],
    do: start |> Tempo.to_interval() |> first_interval()

  defp day_interval(%Tempo{} = start, count) do
    with {:ok, span} <- Interval.new(from: start, to: days(count)), do: Tempo.to_interval(span)
  end

  # The Gregorian year a value falls in, whatever calendar it is stated in.
  defp gregorian_year(%Tempo{} = value) do
    with {:ok, date} <- Tempo.to_date(value),
         {:ok, gregorian} <- Date.convert(date, Calendrical.Gregorian) do
      gregorian.year
    else
      _other -> nil
    end
  end

  # A non-leap rule's integer month is valid in every lunar year, so its
  # candidate is taken from the previous, current and next lunar year and
  # filtered by Gregorian year. A leap-month rule names a month that exists only
  # in specific years, so it stays anchored to the target year to avoid asking a
  # neighbour for a month it does not have.
  defp lunisolar_anchor_years(%__MODULE__{leap_month: true}, target), do: [target]
  defp lunisolar_anchor_years(%__MODULE__{}, target), do: [target - 1, target, target + 1]

  # A `<n> day[s] before/after` prefix (Vietnam's Tết eve) shifts the computed
  # Gregorian date; no offset leaves it untouched.
  defp offset_date(%Date{} = date, nil), do: date
  defp offset_date(%Date{} = date, offset), do: Date.add(date, offset)

  # A Gregorian occurrence converted into the source calendar (ordinal months)
  # and returned in-calendar, spanning `count` days. Shared by the lunisolar
  # tiers (whose `gregorian_date_for_lunar/3` yields a Gregorian date) and the
  # Islamic tier (whose anchored first-of-month-plus-offset does too); the
  # rolled-over Islamic day converts to its true in-calendar value (a `30 Safar`
  # in a 29-day Safar becomes `1 Rabi al-awwal`).
  defp converted_interval(%Date{} = gregorian, calendar, count) do
    with {:ok, in_calendar} <- Date.convert(gregorian, calendar),
         {:ok, base} <- Tempo.from_elixir(in_calendar) do
      day_interval(base, count)
    end
  end

  # The UTC instant of the named event in the given Gregorian year.
  defp solar_event_utc(:equinox, 3, year), do: Astro.equinox(year, :march)
  defp solar_event_utc(:equinox, 9, year), do: Astro.equinox(year, :september)
  defp solar_event_utc(:solstice, 6, year), do: Astro.solstice(year, :june)
  defp solar_event_utc(:solstice, 12, year), do: Astro.solstice(year, :december)

  # The event's civil date in its timezone. No timezone is GMT; a numeric
  # offset shifts the UTC instant directly; a named zone goes through the host
  # app's configured time-zone database (a clean error, skipped upstream, when
  # none is configured).
  defp solar_event_date(%DateTime{} = utc, nil), do: {:ok, DateTime.to_date(utc)}

  defp solar_event_date(%DateTime{} = utc, timezone) do
    case offset_seconds(timezone) do
      {:ok, seconds} -> {:ok, utc |> DateTime.add(seconds, :second) |> DateTime.to_date()}
      :error -> named_zone_date(utc, timezone)
    end
  end

  defp named_zone_date(%DateTime{} = utc, timezone) do
    case DateTime.shift_zone(utc, timezone, Tempo.Holidays.Application.time_zone_database()) do
      {:ok, local} -> {:ok, DateTime.to_date(local)}
      {:error, _reason} = error -> error
    end
  end

  # A fixed UTC offset — `GMT`/`UTC`, `+09`, `+09:00`, `-0430` — as seconds,
  # or `:error` for a named zone.
  defp offset_seconds(timezone) do
    case Regex.run(~r/^\s*(?:GMT|UTC)?([+-])(\d{1,2}):?(\d{2})?\s*$/i, timezone) do
      [_, sign, hours | rest] ->
        minutes = rest |> List.first() |> to_minutes()
        magnitude = (String.to_integer(hours) * 60 + minutes) * 60
        {:ok, if(sign == "-", do: -magnitude, else: magnitude)}

      _no_offset ->
        if String.upcase(String.trim(timezone)) in ["GMT", "UTC", "Z"], do: {:ok, 0}, else: :error
    end
  end

  defp to_minutes(nil), do: 0
  defp to_minutes(""), do: 0
  defp to_minutes(minutes), do: String.to_integer(minutes)

  # ── observed-date substitution ──────────────────────────────────────

  # Apply the ordered substitution clauses to every occurrence, mirroring
  # date-holidays: the first clause whose trigger a date matches fires and
  # locks the date, so no later clause touches it. A `:shift` clause moves the
  # date to the observed day; `:add` keeps the original and adds the observed
  # day; `:substitute_only` yields the observed day, and drops the occurrence
  # when no clause fires. A no-op when the rule names no substitution.
  defp substitute_all(intervals, nil), do: {:ok, intervals}
  defp substitute_all(intervals, []), do: {:ok, intervals}

  defp substitute_all(intervals, clauses) do
    with {:ok, per_occurrence} <- reduce_ok(intervals, &substitute_one(&1, clauses)) do
      {:ok, List.flatten(per_occurrence)}
    end
  end

  defp substitute_one(interval, clauses) do
    date = Interval.from(interval)
    weekday = Tempo.day_of_week(date, :monday)
    apply_clauses(clauses, interval, date, weekday, false)
  end

  # No clause fired: keep the occurrence, unless a `:substitute_only` clause it
  # failed to trigger has marked it for removal.
  defp apply_clauses([], interval, _date, _weekday, dropped) do
    {:ok, if(dropped, do: [], else: [interval])}
  end

  defp apply_clauses(
         [{triggers, direction, target, mode} | rest],
         interval,
         date,
         weekday,
         dropped
       ) do
    if weekday in triggers do
      # This clause fires and locks the date; `:add` also keeps the original.
      with {:ok, observed} <- observe_on(date, weekday, direction, target) do
        {:ok, if(mode == :add, do: [interval, observed], else: [observed])}
      end
    else
      apply_clauses(rest, interval, date, weekday, dropped or mode == :substitute_only)
    end
  end

  defp observe_on(date, weekday, :next, target) do
    shift_days(date, nonzero_shift(Integer.mod(target - weekday, 7), 7))
  end

  defp observe_on(date, weekday, :previous, target) do
    shift_days(date, nonzero_shift(-Integer.mod(weekday - target, 7), -7))
  end

  # date-holidays moves a full week when the observed target is the date's own
  # weekday, rather than leaving it in place.
  defp nonzero_shift(0, fallback), do: fallback
  defp nonzero_shift(offset, _fallback), do: offset

  defp shift_days(date, days) do
    with {:ok, day} <- Tempo.shift(date, day: days) do
      day |> Tempo.to_interval() |> first_interval()
    end
  end

  # ── projection helpers ──────────────────────────────────────────────

  # The `count`-th `weekday` of `month`. date-holidays counts the Nth weekday on
  # from the 1st, past the month's end if need be — the 5th Monday of a
  # four-Monday October is 1 November (NZ-MBH's anniversary) — so from the 5th
  # on it is taken within the `7n`-day window from the 1st, where each weekday
  # falls exactly n times. Up to the 4th it always lies inside the month, so the
  # plain selection is the same date. A negative count (`last`) cannot overflow.
  defp weekday_shape(%__MODULE__{month: month, count: count, weekday: weekday})
       when is_integer(count) and count >= 5 do
    shape(
      selection: [month: month, day: 1],
      window: days(7 * count),
      day_of_week: weekday,
      instance: count
    )
  end

  defp weekday_shape(%__MODULE__{month: month, count: count, weekday: weekday}) do
    shape(month: month, day_of_week: weekday, instance: count)
  end

  # The signed day offset from an anchor date (whose weekday is
  # `anchor_weekday`) to the `count`-th `target` weekday from it. "before" is
  # strict — "the Monday before June 1" steps back even when June 1 is itself a
  # Monday — while "after" is inclusive, matching date-holidays: "the Monday
  # after May 27" is May 27 when that day is already a Monday.
  defp relative_shift(:before, anchor_weekday, target, count) do
    -(strict_step(anchor_weekday - target) + 7 * (count - 1))
  end

  defp relative_shift(:after, anchor_weekday, target, count) do
    inclusive_step(target - anchor_weekday) + 7 * (count - 1)
  end

  defp strict_step(delta) do
    case Integer.mod(delta, 7) do
      0 -> 7
      step -> step
    end
  end

  defp inclusive_step(delta), do: Integer.mod(delta, 7)

  # `to_interval/2` returns one span for a value and a set of them for a
  # recurrence. Normalise both to the first (and, for a holiday, only) member.
  defp first_interval({:ok, %Tempo{} = expression}), do: first_interval(expression)
  defp first_interval({:error, _} = error), do: error

  defp first_interval(%Tempo{} = expression) do
    case IntervalSet.first(expression) do
      %Tempo{} = interval -> {:ok, interval}
      nil -> {:error, :no_occurrence}
    end
  end

  # The first value a selection picks.
  defp first_value(set) do
    case IntervalSet.members(set) do
      [first | _rest] -> {:ok, first}
      [] -> {:error, :no_occurrence}
    end
  end

  # A single-occurrence kind yields one interval; lift it into the
  # one-element list `materialise/2` returns, propagating any error.
  defp wrap_one({:ok, %Tempo{} = interval}), do: {:ok, [interval]}
  defp wrap_one({:error, _} = error), do: error

  # Map an `{:ok, _} | {:error, _}` function over `items`, collecting the
  # values in order into `{:ok, list}`, or returning the first error.
  defp reduce_ok(items, fun) do
    items
    |> Enum.reduce_while([], &collect_ok(fun.(&1), &2))
    |> finish_ok()
  end

  defp collect_ok({:ok, value}, acc), do: {:cont, [value | acc]}
  defp collect_ok({:error, _} = error, _acc), do: {:halt, error}

  defp finish_ok({:error, _} = error), do: error
  defp finish_ok(acc) when is_list(acc), do: {:ok, Enum.reverse(acc)}
end
