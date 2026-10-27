defmodule Tempo.Holidays do
  @moduledoc """
  Holidays as Tempo recurrences, for any window.

  A holiday is a *recurrence*, not a date: "Christmas is the 25th of
  December", "Thanksgiving is the fourth Thursday of November". A territory's
  holidays are a recurrence set (a `t:Tempo.t/0`) — one member per holiday, each
  tagged with the holiday's metadata — and `Tempo.to_interval/2` converts
  it to the set (a `t:Tempo.t/0`) of the holidays in a window, each
  occurrence tagged the same way. Because both are Tempo values, holidays
  compose with anything else through set algebra.

  The data is the [date-holidays](https://github.com/commenthol/date-holidays)
  dataset for every territory, carrying every `:type` (public holidays through
  to observances). Fixed dates and weekday-in-month holidays are ISO 8601-2
  selections (`FL12M25DN`, `FL6M1K2IN`); Easter-relative holidays are windows
  off the computed `(easter)e` event; Islamic, Hebrew and other calendar
  holidays are recurrences in their own calendar, which a set of occurrences
  brings to the one calendar it is in; a holiday
  observed on its own date and a substitute day is a nested set of both; and a
  bridge day or a holiday moved off another is a conditional member
  (`Tempo.RecurrenceSet.keep_when/2`, `move_when/2`), resolved against the
  others when the set converts.

  Each holiday's metadata is `:id` (its date-holidays rule, unique within the
  set, where names repeat), `:name` and `:type`; a substitute day adds
  `substitute: true`, and a holiday whose rule is in another calendar than the
  Gregorian adds `:calendar`, that calendar's module. The set's own metadata
  names its territory and subdivision.

  The primary API is `holidays/2`, which gives holidays of your own beside
  the dataset's (`:include`, `:exclude` and the `:holidays` configuration);
  `compile/2` reads a holiday from a rule in the dataset's grammar, and
  `day_start/2` projects the Islamic and Hebrew holidays whose day begins at
  sunset onto the evening before.

  ## Example

      {:ok, holidays} = Tempo.Holidays.holidays(:AU)
      {:ok, this_year} = Tempo.to_interval(holidays, within: ~o"2026")

      {:ok, clashes} = Tempo.intersection(my_diary, holidays, metadata: :merge)

  > *"Australia's **holidays** are a set of recurrences. **This year's** are the
  > days they fall on in 2026; the diary's **clashes** are its entries that fall
  > on one, each labelled with the holiday it hit."*

  """

  alias Tempo.Holidays.{Data, DayStart, Holiday, Locale}
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.RecurrenceSet

  @typedoc """
  A holiday request's target: a positional CLDR territory code (atom or string,
  always a territory — never a language), a `t:Localize.LanguageTag.t/0`, or a
  keyword list carrying a `:territory` or `:locale` option.
  """
  @type target :: atom() | String.t() | Localize.LanguageTag.t() | keyword()

  @typedoc """
  The dates a holiday observed on another day is given on: `:substitute` the
  day it is observed on, `:gazetted` its own date, or `:both`.
  """
  @type dates :: :substitute | :gazetted | :both

  @typedoc """
  The category a holiday falls under, following
  [date-holidays](https://github.com/commenthol/date-holidays): a `:public`
  holiday is a statutory day off, `:bank` a banking holiday, `:school` a school
  holiday, `:optional` a day observed at the holder's discretion, and
  `:observance` a marked but non-statutory day.
  """
  @type holiday_type :: :public | :bank | :school | :optional | :observance

  @holiday_types [:public, :bank, :school, :optional, :observance]

  @dates [:substitute, :gazetted, :both]

  @options [:territory, :locale, :subdivision, :include, :exclude, :dates]

  @rule_options [:id, :name, :type, :metadata, :dates]

  @config_options [:include, :exclude]

  # The calendars whose day begins at sunset, so `day_start/2` projects their
  # holidays onto the evening before.
  @sunset_calendar_types [
    :hebrew,
    :islamic,
    :islamic_civil,
    :islamic_rgsa,
    :islamic_tbla,
    :islamic_umalqura
  ]

  @doc """
  Returns a territory's holidays as a recurrence set.

  Each member is one holiday — its recurrence, a nested set of its own date and
  its substitute days, or a conditional member for a bridge day or a holiday
  moved off another — tagged with `:id`, `:name` and `:type` metadata. The
  set's own metadata names the territory, and the subdivision when one is given.
  `Tempo.to_interval/2` converts it to the holidays in a window.

  A period date-holidays splits over the year end, because its data cannot run
  one past it, is one member: Victoria's summer school holidays run from
  December to the end of January, 31 December included.

  A selection by type never changes a holiday's date: a kept holiday that moves
  off another (Näfelser Fahrt off Maundy Thursday, an observance) carries the
  holidays it depends on when their type is left out.

  Holidays of your own sit beside the dataset's: the holidays a request's
  `:include` and `:exclude` name, and `config :tempo_holidays, holidays:` for
  every request, keyed by territory, or by territory and subdivision, each
  with an `:include` and an `:exclude` that name holidays alone. A
  territory's apply to its subdivisions too, a subdivision's come after its
  territory's, and a request's own after both. The configured holidays are
  the territory's, selected by type as the dataset's are; the holidays a
  request names are kept whatever their type. The configuration is read at
  each request.

      config :tempo_holidays,
        holidays: [
          AU: [include: [{"1st friday in December", name: "Company Day", type: :optional}]],
          BR: [exclude: ["Election Day"]],
          "AU-VIC": [include: [{"11-02", name: "Office Closure"}]]
        ]

  ### Arguments

  * `target` names the territory — a positional CLDR territory code (`:AU`,
    `"AU"`, always a territory, never a language) or a `t:Localize.LanguageTag.t/0`.
    Omit it and pass the target by option instead. See `Tempo.Holidays.Locale`.

  ### Options

  * `:territory` — an explicit CLDR territory code, validated (`territory: :SA`
    is Saudi Arabia).

  * `:locale` — a BCP 47 locale identifier or `t:Localize.LanguageTag.t/0` whose
    territory is derived (`locale: "en-US-u-sd-usca"` selects California).

  * `:subdivision` — a subdivision code, the ISO 3166-2 part after the
    territory's (`"ENG"`, `"CA"`), or the whole code (`"GB-ENG"`), in place of
    a locale's `u-sd` subdivision. It names a subdivision at whichever level
    the data holds it: a state, or a region by its own code or by its path from
    its state (`"CA-LA"`, Los Angeles, where `"LA"` alone is Louisiana). See
    `Tempo.Holidays.Data.subdivision/2`.

  * `:include` — what to keep, an item or a list of them, each a
    `t:holiday_type/0` or a holiday of your own: a rule in the date-holidays
    grammar, or `{rule, options}` with the options of `compile/2` but
    `:dates`. The types kept are those it names, or every type when it names
    none but holidays. A holiday it names is read with the request's
    `:dates`, kept whatever its type, and takes the place of a holiday of its
    id. The default is every type.

  * `:exclude` — what to leave out, an item or a list of them, each a
    `t:holiday_type/0`, winning over `:include`, or a holiday's id or name:
    `"Election Day"` leaves out every holiday of that name. A holiday
    `:include` names is never left out. The default is none.

  * `:dates` — the dates a holiday observed on another day is given on, when
    its own date falls on a weekend, say:

    * `:substitute` — the day it is observed on: its substitute day in place
      of its own date, so each holiday is counted once. The default.

    * `:gazetted` — its own date alone, the date its law names.

    * `:both` — its own date and its substitute day, as date-holidays gives
      them. A holiday the data moves to another day, rather than observing on
      both, is on the day it moves to.

  ### Returns

  * `{:ok, recurrence_set}` — a recurrence set (a `t:Tempo.t/0`) of the holidays: the
    territory's, with a subdivision's own in place of the ones it redefines.

  * `{:error, reason}` — `{:unknown_territory, territory}`,
    `{:invalid_locale, target}`, `{:unknown_subdivision, subdivision}`,
    `{:ambiguous_subdivision, subdivision}`, `{:invalid_holiday_type, value}`,
    `{:invalid_dates, value}`, `{:invalid_include, item}`,
    `{:invalid_exclude, item}`, `{:invalid_config, entry}` or
    `{:invalid_option, option}`, or

  * an error `compile/2` returns for a holiday `:include` names.

  ### Examples

      iex> {:ok, holidays} = Tempo.Holidays.holidays(:AU)
      iex> holidays |> Tempo.RecurrenceSet.members() |> Enum.map(&Tempo.metadata(&1).name) |> Enum.take(2)
      ["New Year's Day", "Australia Day"]
      iex> Tempo.metadata(holidays)
      %{territory: "AU"}

      iex> {:ok, banking} = Tempo.Holidays.holidays(:AT, include: :bank)
      iex> banking |> Tempo.RecurrenceSet.members() |> Enum.map(&Tempo.metadata(&1).type) |> Enum.uniq()
      [:bank]

      iex> import Tempo.Sigils
      iex> {:ok, england} = Tempo.Holidays.holidays(:GB, subdivision: "ENG", exclude: :observance)
      iex> {:ok, this_year} = Tempo.to_interval(england, within: ~o"2026")
      iex> Tempo.IntervalSet.count(this_year)
      8

      iex> import Tempo.Sigils
      iex> company_day = {"1st friday in December", name: "Company Day"}
      iex> {:ok, australia} = Tempo.Holidays.holidays(:AU, include: [:public, company_day])
      iex> {:ok, december} = Tempo.to_interval(australia, within: ~o"2026-12")
      iex> Tempo.IntervalSet.map(december, &Tempo.metadata(&1).name)
      ["Company Day", "Christmas Day", "Boxing Day"]

  """
  @spec holidays(target(), keyword()) ::
          {:ok, Tempo.t()} | {:error, {atom(), term()} | Exception.t()}
  def holidays(target \\ [], options \\ [])

  def holidays(options, extra) when is_list(options) and is_list(extra),
    do: holiday_set(nil, extra ++ options)

  def holidays(target, options), do: holiday_set(target, options)

  defp holiday_set(target, options) do
    with :ok <- known_options(options, @options),
         {:ok, selection} <- selection(options),
         {:ok, dates} <- selected_dates(options),
         {:ok, resolved} <- Locale.resolve(target, options),
         {:ok, subdivision} <- Data.subdivision(resolved.territory, resolved.subdivision),
         {:ok, changes} <- configured_changes(resolved.territory, subdivision),
         {:ok, dataset} <- read_holidays(resolved.territory, subdivision, dates),
         {:ok, territorial} <- with_own(dataset, changes, dates),
         {:ok, own} <- read_added(selection.holidays, dates, []) do
      members = selected_members(territorial, own, selection, dates)
      RecurrenceSet.new(members, metadata: set_metadata(resolved.territory, subdivision))
    end
  end

  # A request's members: the territory's holidays (the dataset's and the
  # configured) of the kept types, less those it names in `:exclude`, then
  # the holidays its `:include` names, each kept whatever its type.
  defp selected_members(territorial, own, %{types: types, names: names}, dates) do
    kept = without(territorial, names, own)
    read = kept ++ own
    selected = for {holiday, _expression} = entry <- kept, holiday.type in types, do: entry

    for {holiday, expression} <- selected ++ own,
        member <- holiday_member(holiday, expression, read, types, dates),
        do: member
  end

  defp known_options(options, known) when is_list(options) do
    case Enum.reject(options, &known_option?(&1, known)) do
      [] -> :ok
      [{option, _value} | _rest] -> {:error, {:invalid_option, option}}
      [other | _rest] -> {:error, {:invalid_option, other}}
    end
  end

  defp known_options(options, _known), do: {:error, {:invalid_option, options}}

  defp known_option?({option, _value}, known), do: option in known
  defp known_option?(_other, _known), do: false

  # What a request's `:include` and `:exclude` name: the holiday types it
  # keeps, the holidays of its own it adds and the ids or names it leaves out.
  defp selection(options) do
    with {:ok, {types, holidays}} <- included(Keyword.get(options, :include, @holiday_types)),
         {:ok, {excluded, names}} <- excluded(Keyword.get(options, :exclude, [])) do
      {:ok, %{types: kept_types(types, holidays) -- excluded, holidays: holidays, names: names}}
    end
  end

  # The types an `:include` keeps: those it names, or every type when it names
  # holidays and no type.
  defp kept_types([], [_ | _]) do
    @holiday_types
  end

  defp kept_types(types, _holidays) do
    types
  end

  # An `:include` or `:exclude` is one item or a list of them.
  defp included(include) do
    included_items(items(include), [], [])
  end

  defp excluded(exclude) do
    excluded_items(items(exclude), [], [])
  end

  defp items(items) when is_list(items) do
    items
  end

  defp items(item) do
    [item]
  end

  # An `:include` item is a type, or a holiday of your own: a rule, or a rule
  # and the options of `compile/2`.
  defp included_items([], types, holidays) do
    {:ok, {Enum.reverse(types), Enum.reverse(holidays)}}
  end

  defp included_items([type | rest], types, holidays) when type in @holiday_types do
    included_items(rest, [type | types], holidays)
  end

  defp included_items([rule | rest], types, holidays) when is_binary(rule) do
    included_items(rest, types, [{rule, []} | holidays])
  end

  defp included_items([{rule, options} = holiday | rest], types, holidays)
       when is_binary(rule) and is_list(options) do
    included_items(rest, types, [holiday | holidays])
  end

  defp included_items([other | _rest], _types, _holidays) when is_atom(other) do
    {:error, {:invalid_holiday_type, other}}
  end

  defp included_items([other | _rest], _types, _holidays) do
    {:error, {:invalid_include, other}}
  end

  # An `:exclude` item is a type, or a holiday's id or name.
  defp excluded_items([], types, names) do
    {:ok, {Enum.reverse(types), Enum.reverse(names)}}
  end

  defp excluded_items([type | rest], types, names) when type in @holiday_types do
    excluded_items(rest, [type | types], names)
  end

  defp excluded_items([name | rest], types, names) when is_binary(name) do
    excluded_items(rest, types, [name | names])
  end

  defp excluded_items([other | _rest], _types, _names) when is_atom(other) do
    {:error, {:invalid_holiday_type, other}}
  end

  defp excluded_items([other | _rest], _types, _names) do
    {:error, {:invalid_exclude, other}}
  end

  # The configured changes to a territory's holidays, in the order they
  # apply: its territory's, then its subdivision's. Each is a list of ids or
  # names to leave out and a list of rules to add.
  defp configured_changes(territory, subdivision) do
    entries = Application.get_env(:tempo_holidays, :holidays, [])

    with {:ok, entries} <- configured_entries(entries, []) do
      changes =
        entries
        |> Enum.filter(&applies?(&1, territory, subdivision))
        |> Enum.sort_by(&depth/1)
        |> Enum.map(&elem(&1, 1))

      {:ok, changes}
    end
  end

  defp configured_entries([], entries) do
    {:ok, Enum.reverse(entries)}
  end

  defp configured_entries([{key, options} = entry | rest], entries)
       when is_atom(key) or is_binary(key) do
    case configured_change(options) do
      {:ok, change} -> configured_entries(rest, [{config_path(key), change} | entries])
      {:error, _reason} -> {:error, {:invalid_config, entry}}
    end
  end

  defp configured_entries([entry | _rest], _entries) do
    {:error, {:invalid_config, entry}}
  end

  defp configured_entries(entries, _entries) do
    {:error, {:invalid_config, entries}}
  end

  # A config key, `:AU` or `:"US-CA"`, as its territory and the path of its
  # subdivision.
  defp config_path(key) do
    key
    |> to_string()
    |> String.upcase()
    |> String.split("-", parts: 2)
  end

  # A territory's entry applies to it and its subdivisions; a subdivision's
  # to it and the regions within it.
  defp applies?({[territory], _options}, territory, _subdivision) do
    true
  end

  defp applies?({[territory, path], _options}, territory, subdivision)
       when is_binary(subdivision) do
    code = String.upcase(subdivision)
    code == path or String.starts_with?(code, path <> "-")
  end

  defp applies?(_entry, _territory, _subdivision) do
    false
  end

  defp depth({path, _change}) do
    length(path)
  end

  # A configured entry's `:include` and `:exclude` name holidays alone: the
  # types are a request's to select.
  defp configured_change(options) do
    with :ok <- known_options(options, @config_options),
         {:ok, included} <- included(Keyword.get(options, :include, [])),
         {:ok, excluded} <- excluded(Keyword.get(options, :exclude, [])) do
      holidays_alone(included, excluded)
    end
  end

  defp holidays_alone({[], holidays}, {[], names}) do
    {:ok, {names, holidays}}
  end

  defp holidays_alone(_included, _excluded) do
    {:error, :configured_type}
  end

  # The dataset's holidays with each configured change applied in turn: the
  # holidays it names left out, then its own added, each in place of a
  # holiday of its id.
  defp with_own(read, [], _dates) do
    {:ok, read}
  end

  defp with_own(read, [{names, holidays} | changes], dates) do
    with {:ok, added} <- read_added(holidays, dates, []) do
      with_own(without(read, names, added) ++ added, changes, dates)
    end
  end

  # Holidays less those of the names and of the ids of the added.
  defp without(read, names, added) do
    Enum.reject(read, &(named_in?(&1, names) or same_id?(&1, added)))
  end

  defp read_added([], _dates, added) do
    {:ok, Enum.reverse(added)}
  end

  defp read_added([{rule, options} | rest], dates, added) do
    with {:ok, holiday} <- read_own(rule, options, dates) do
      read_added(rest, dates, [holiday | added])
    end
  end

  # A holiday of your own, read with the request's `:dates` as `compile/2`
  # reads it, beside the holiday it stands for.
  defp read_own(rule, options, dates) do
    if List.keymember?(options, :dates, 0) do
      {:error, {:invalid_option, :dates}}
    else
      own_holiday(rule, compile(rule, [dates: dates] ++ options))
    end
  end

  defp own_holiday(rule, {:ok, expression}) do
    %{name: name, type: type} = Tempo.metadata(expression)
    {:ok, {%Holiday{rule: rule, name: name, type: type}, expression}}
  end

  defp own_holiday(_rule, error) do
    error
  end

  defp named_in?({_holiday, expression}, names) do
    %{id: id, name: name} = Tempo.metadata(expression)
    id in names or name in names
  end

  defp same_id?({_holiday, expression}, added) do
    %{id: id} = Tempo.metadata(expression)
    Enum.any?(added, fn {_other, other} -> Tempo.metadata(other).id == id end)
  end

  defp selected_dates(options) do
    case Keyword.get(options, :dates, :substitute) do
      dates when dates in @dates -> {:ok, dates}
      other -> {:error, {:invalid_dates, other}}
    end
  end

  # A territory's holidays, each with its rule read by `Tempo.DateRule` as
  # `:dates` observes it, kept for the life of the VM: a territory, a
  # subdivision and a reading is one `:persistent_term` entry, written once.
  defp read_holidays(territory, subdivision, dates) do
    key = {__MODULE__, territory, subdivision, dates}

    case :persistent_term.get(key, nil) do
      nil -> read_and_keep(key, territory, subdivision, dates)
      read -> {:ok, read}
    end
  end

  defp read_and_keep(key, territory, subdivision, dates) do
    with {:ok, holidays} <- Data.for_territory(territory, subdivision) do
      read =
        holidays
        |> observed_entries(dates)
        |> read_each(dates)
        |> joined_year_ends()
        |> Enum.map(fn {holiday, expression} -> {holiday, tagged(expression, holiday)} end)

      :persistent_term.put(key, read)
      {:ok, read}
    end
  end

  # A substitute entry gives nothing under `:gazetted`, and under
  # `:substitute` stands in for the holidays of its own type, so a selection
  # by type keeps or drops both together.
  defp observed_entries(holidays, :gazetted) do
    Enum.reject(holidays, & &1.substitute)
  end

  defp observed_entries(holidays, _dates) do
    holidays
  end

  # Each holiday with its rule read; one that reads to no date has no member.
  defp read_each(holidays, dates) do
    for holiday <- holidays,
        {:ok, expression} <- [read(holiday, holidays, dates, [])],
        match?([_ | _], RecurrenceSet.members(expression)) do
      {holiday, expression}
    end
  end

  defp read(%Holiday{} = holiday, holidays, dates, options) do
    dated = [active: holiday.active, disable: holiday.disable, enable: holiday.enable]
    replacing = replaced_by(holiday, holidays, dates)

    Tempo.DateRule.parse(
      holiday.rule,
      [observed: observed(dates)] ++ dated ++ replacing ++ options
    )
  end

  defp observed(:substitute) do
    :moved
  end

  defp observed(:gazetted) do
    :none
  end

  defp observed(:both) do
    :as_written
  end

  # Under `:substitute` the substitute entries of a holiday's type stand in
  # for it, each in its `active` windows; `Tempo.DateRule` takes those of the
  # holiday's own date.
  defp replaced_by(holiday, holidays, :substitute) do
    entries =
      for entry <- holidays, entry.substitute, entry.type == holiday.type, entry != holiday do
        {entry.rule, active: entry.active}
      end

    [replaced_by: entries]
  end

  defp replaced_by(_holiday, _holidays, _dates) do
    []
  end

  # date-holidays cannot run a period past the year end, so it writes one as
  # two dated entries under one name; they are one member here, the period
  # they describe, the 31st of December within it.
  defp joined_year_ends(read) do
    {joined, continuations} =
      Enum.map_reduce(read, [], fn {holiday, _expression} = entry, continuations ->
        case Enum.find_value(read, &continuation(entry, &1)) do
          {january, period} -> {{holiday, period}, [january | continuations]}
          nil -> {entry, continuations}
        end
      end)

    Enum.reject(joined, fn {holiday, _expression} -> holiday in continuations end)
  end

  defp continuation(
         {%Holiday{name: name, type: type} = december, december_expression},
         {%Holiday{name: name, type: type} = january, january_expression}
       )
       when december != january do
    year_end_period(single_span(december_expression), single_span(january_expression), january)
  end

  defp continuation(_december, _january) do
    nil
  end

  defp single_span(expression) do
    case Tempo.to_interval(expression) do
      {:ok, occurrences} -> one_span(IntervalSet.members(occurrences))
      {:error, _reason} -> :none
    end
  end

  defp one_span([span]) do
    {:ok, span}
  end

  defp one_span(_spans) do
    :none
  end

  # A December period that ends with the year or the day before, and a
  # January one from the 1st of the next, are the one period from the first
  # through the last.
  defp year_end_period({:ok, december}, {:ok, january}, january_holiday) do
    if year_end?(Interval.to(december), Interval.from(january)) do
      joined_period(
        Interval.new(from: Interval.from(december), to: Interval.to(january)),
        january_holiday
      )
    end
  end

  defp year_end_period(_december, _january, _january_holiday) do
    nil
  end

  defp year_end?(last, first) do
    dated_year_end?(Tempo.to_date(last), Tempo.to_date(first))
  end

  defp dated_year_end?({:ok, last}, {:ok, %Date{month: 1, day: 1} = first}) do
    Date.diff(first, last) in [1, 2]
  end

  defp dated_year_end?(_last, _first) do
    false
  end

  defp joined_period({:ok, period}, january) do
    {january, period}
  end

  defp joined_period({:error, _reason}, _january) do
    nil
  end

  # A holiday is one member: its expression, tagged with the holiday's id,
  # name and type when it was read. A conditional (a bridge, an `if is
  # holiday` move) reads the rest of the territory as it would unselected:
  # when the type it falls on is left out, it reads those holidays as its own
  # `:falls_on` set, and keeps its tags.
  defp holiday_member(holiday, expression, read, types, dates) do
    type = conditional_type(expression)

    if is_nil(type) or type in types do
      [expression]
    else
      carried_member(holiday, expression, read, type, dates)
    end
  end

  defp carried_member(holiday, expression, read, type, dates) do
    carried =
      for {other, other_expression} <- read,
          other.type == type,
          other != holiday,
          do: other_expression

    holidays = Enum.map(read, &elem(&1, 0))

    case read_falling_on(holiday, holidays, dates, carried) do
      {:ok, carrying} -> [with_tags_of(carrying, expression)]
      {:error, _reason} -> []
    end
  end

  defp with_tags_of(expression, tagged) do
    metadata = Map.merge(Tempo.metadata(expression), Tempo.metadata(tagged))
    Tempo.put_metadata(expression, metadata)
  end

  defp read_falling_on(holiday, holidays, dates, carried) do
    with {:ok, falls_on} <- RecurrenceSet.new(carried) do
      read(holiday, holidays, dates, falls_on: falls_on)
    end
  end

  # The type of the holidays a conditional is decided against.
  defp conditional_type(%Tempo{form: {:when, _member, conditions}}) do
    Enum.find_value(conditions, &condition_type/1)
  end

  defp conditional_type(_expression) do
    nil
  end

  defp condition_type({_condition, options}) do
    case Keyword.get(options, :falls_on) do
      %{type: type} -> type
      _other -> nil
    end
  end

  # A holiday of another calendar than the Gregorian says so, as a set of
  # occurrences is in one calendar: the day of an Islamic holiday beside
  # Gregorian ones is a Gregorian day, and its calendar is what is left to say
  # that its day begins at sunset (`day_start/2`).
  defp tagged(expression, %Holiday{rule: rule, name: name, type: type}) do
    tagged(expression, %{id: rule, name: name, type: type})
  end

  defp tagged(expression, tags) do
    metadata =
      expression
      |> Tempo.metadata()
      |> Map.merge(tags)
      |> Map.merge(calendar_metadata(expression))

    Tempo.put_metadata(expression, metadata)
  end

  defp calendar_metadata(%Tempo{calendar: Calendar.ISO}) do
    %{}
  end

  defp calendar_metadata(%Tempo{calendar: calendar}) do
    %{calendar: calendar}
  end

  defp set_metadata(territory, nil), do: %{territory: territory}
  defp set_metadata(territory, subdivision), do: %{territory: territory, subdivision: subdivision}

  @doc """
  Reads a holiday rule into the holiday it describes.

  The rule is written in the date-holidays grammar the dataset's holidays are
  written in, which Tempo reads with `Tempo.DateRule`: `"12-25"`, `"4th
  thursday in November"`, `"01-26 and if saturday, sunday then next monday"`,
  `"15 Nisan"`. The holiday is tagged as a member of `holidays/2` is, so it
  sits beside a territory's holidays as one of them.

  A rule that depends on other holidays, a bridge day (`"08-14 if 08-15 is
  holiday"`) or a holiday moved off another, is a conditional member: decided
  against the other members of a set it is in, and against none when it is
  converted alone, so alone it falls on no day.

  ### Arguments

  * `rule` is a holiday rule in the date-holidays grammar. See
    [the grammar](https://hexdocs.pm/ex_tempo/date-rule-grammar.html).

  * `options` is a keyword list of options.

  ### Options

  * `:name` — the holiday's name. The default is the rule.

  * `:type` — its `t:holiday_type/0`. The default is `:public`.

  * `:id` — its id, unique within a set of holidays. The default is the rule,
    as a dataset holiday's id is its rule.

  * `:metadata` — a map of metadata of your own, kept beside the id, name and
    type. The default is `%{}`.

  * `:dates` — the dates a holiday observed on another day is given on,
    `:substitute`, `:gazetted` or `:both`, as for `holidays/2`. The default
    is `:substitute`.

  ### Returns

  * `{:ok, holiday}` — the holiday, a `t:Tempo.t/0`: a yearly recurrence, a
    recurrence set of its date and its observed days, or a conditional
    member, tagged with `:id`, `:name`, `:type` and your own metadata, and
    with `:calendar` for a rule of another calendar than the Gregorian.

  * `{:error, exception}` — a `Tempo.ParseError` for a rule that cannot be
    read, naming where reading stopped, or another exception for a date the
    rule names that its calendar does not have (`Tempo.DateRule.parse/2`), or

  * `{:error, reason}` — `{:invalid_option, option}`, `{:invalid_id, value}`,
    `{:invalid_name, value}`, `{:invalid_holiday_type, value}`,
    `{:invalid_metadata, value}` or `{:invalid_dates, value}`.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, thanksgiving} = Tempo.Holidays.compile("4th thursday in November", name: "Thanksgiving Day")
      iex> Tempo.metadata(thanksgiving)
      %{id: "4th thursday in November", name: "Thanksgiving Day", type: :public}
      iex> {:ok, this_year} = Tempo.to_interval(thanksgiving, within: ~o"2026")
      iex> Tempo.IntervalSet.map(this_year, &Tempo.day/1)
      [26]

      iex> {:error, %Tempo.ParseError{}} = Tempo.Holidays.compile("12-25 on a full moon")

  """
  @spec compile(String.t(), keyword()) ::
          {:ok, Tempo.t()} | {:error, {atom(), term()} | Exception.t()}
  def compile(rule, options \\ []) do
    with :ok <- known_options(options, @rule_options),
         {:ok, dates} <- selected_dates(options),
         {:ok, expression} <- Tempo.DateRule.parse(rule, observed: observed(dates)),
         {:ok, tags} <- rule_tags(rule, options),
         {:ok, metadata} <- caller_metadata(options) do
      {:ok, tagged(expression, Map.merge(metadata, tags))}
    end
  end

  # The id, name and type a holiday of your own is tagged with.
  defp rule_tags(rule, options) do
    with {:ok, id} <- rule_id(Keyword.get(options, :id, rule)),
         {:ok, name} <- rule_name(Keyword.get(options, :name, rule)),
         {:ok, type} <- holiday_type(Keyword.get(options, :type, :public)) do
      {:ok, %{id: id, name: name, type: type}}
    end
  end

  defp rule_id(id) when is_binary(id) do
    {:ok, id}
  end

  defp rule_id(id) do
    {:error, {:invalid_id, id}}
  end

  defp rule_name(name) when is_binary(name) do
    {:ok, name}
  end

  defp rule_name(name) do
    {:error, {:invalid_name, name}}
  end

  defp holiday_type(type) when type in @holiday_types do
    {:ok, type}
  end

  defp holiday_type(type) do
    {:error, {:invalid_holiday_type, type}}
  end

  defp caller_metadata(options) do
    case Keyword.get(options, :metadata, %{}) do
      metadata when is_map(metadata) -> {:ok, metadata}
      other -> {:error, {:invalid_metadata, other}}
    end
  end

  @doc """
  Projects holiday occurrences onto the evening their day begins.

  A day in Tempo is just a day: an Islamic or Hebrew holiday converts to a day
  in its own calendar, which carries no day-start convention. That calendar's
  day begins at sunset, so on the Gregorian timeline the holiday begins the
  evening before. `day_start/2` projects each occurrence of a holiday of such a
  calendar onto the datetime interval from the boundary that begins its first
  day to the one that begins the day after its last. A set of occurrences is
  in one calendar, so a holiday is told by the `:calendar` its metadata
  carries, the calendar its rule is in, and an occurrence that carries none by
  the calendar its own day is in.

  A set is of one frame, so every other occurrence becomes the civil day it
  is where the day start is read: in the zone it names, at its location, or,
  for a bare `:evening` or `:sunset`, at the reference place of the set's
  sunset holidays. Where no holiday is projected, as for a set of Gregorian
  holidays alone, every occurrence is left as it is.

  ### Arguments

  * `occurrences` is a set (a `t:Tempo.t/0`) of holiday occurrences, as
    `Tempo.to_interval/2` converts the set `holidays/2` returns.

  * `day_start` is how the day begins, a `t:Tempo.Holidays.DayStart.t/0`:

    * `:midnight` — leaves the occurrences as they are.

    * `:evening` or `:sunset` — 18:00, or sunset, at the calendar's reference
      place: Mecca for an Islamic date, Jerusalem for a Hebrew one.

    * `{:evening, location}` or `{:sunset, location}` — the same at a location
      of your own, an IANA zone id (`"Asia/Kuala_Lumpur"`) or a `{longitude,
      latitude}` point.

  ### Returns

  * `{:ok, interval_set}` — the occurrences, each projected one a datetime
    interval and each other one a day in the day start's zone, keeping their
    metadata. A lazy set stays lazy.

  * `{:error, {:invalid_day_start, day_start}}`,
    `{:error, {:invalid_occurrences, occurrences}}`, or
    `{:error, {:location_required, day_start}}` for a lazy set and a bare
    `:evening` or `:sunset`, since a set read as it is walked cannot be looked
    through for the reference place of its sunset holidays.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, holidays} = Tempo.Holidays.holidays(:SA, include: :public)
      iex> {:ok, this_year} = Tempo.to_interval(holidays, within: ~o"2026")
      iex> {:ok, evenings} = Tempo.Holidays.day_start(this_year, {:evening, "Asia/Riyadh"})
      iex> eid = Enum.find(Tempo.IntervalSet.members(evenings), &(Tempo.metadata(&1).name =~ "Eid al-Fitr"))
      iex> {:ok, begins} = Tempo.to_elixir(Tempo.Interval.from(eid))
      iex> {DateTime.to_date(begins), DateTime.to_time(begins)}
      {~D[2026-03-18], ~T[18:00:00]}

  """
  @spec day_start(Tempo.t(), DayStart.t()) :: {:ok, Tempo.t()} | {:error, term()}
  def day_start(%Tempo{} = occurrences, day_start) do
    with {:ok, day_start} <- DayStart.validate(day_start) do
      project_day_start(occurrences, day_start)
    end
  end

  def day_start(occurrences, _day_start), do: {:error, {:invalid_occurrences, occurrences}}

  # A day is just a day until it is projected onto the Gregorian timeline. Each
  # occurrence of a holiday of a sunset-starting calendar (Islamic, Hebrew) is
  # projected to the datetime interval that begins when its day begins, keeping
  # its metadata; every other occurrence, and `:midnight`, is left as the civil
  # day it already is. A lazy set is projected as it is walked.
  defp project_day_start(occurrences, :midnight), do: {:ok, occurrences}

  # A set is of one frame, so the civil days beside the projected ones are
  # days where the day start is read: in the zone it names, at its location,
  # or for a bare boundary at the reference place of the set's sunset
  # holidays, and with none of those nothing is projected (decision 41 of
  # Tempo). A set read as it is walked cannot be looked through for its
  # sunset holidays, so it is given a location.
  defp project_day_start(occurrences, day_start) do
    metadata = Tempo.metadata(occurrences)

    if Tempo.bounded?(occurrences),
      do: project_members(IntervalSet.members(occurrences), day_start, metadata),
      else: project_stream(occurrences, day_start, metadata)
  end

  defp project_members(members, day_start, metadata) do
    case DayStart.civil_zone(day_start, sunset_calendar_of(members)) do
      {:ok, zone} ->
        members
        |> Enum.map(&(&1 |> project_occurrence(day_start) |> as_day_in(zone)))
        |> IntervalSet.new(metadata: metadata)

      :none ->
        IntervalSet.new(members, metadata: metadata)
    end
  end

  defp project_stream(_occurrences, day_start, _metadata) when day_start in [:evening, :sunset],
    do: {:error, {:location_required, day_start}}

  defp project_stream(occurrences, day_start, metadata) do
    zone = DayStart.civil_zone(day_start, nil)

    projected =
      occurrences
      |> IntervalSet.walk()
      |> Stream.map(&(&1 |> project_occurrence(day_start) |> as_day_in(zone)))

    {:ok, IntervalSet.from_stream(projected, metadata: metadata)}
  end

  # The first calendar of a holiday whose day begins at sunset, if any.
  defp sunset_calendar_of(members) do
    Enum.find_value(members, fn member ->
      calendar = holiday_calendar(member)
      if sunset_calendar?(calendar), do: calendar
    end)
  end

  # A civil day, one no projection reached, as the day it is in the zone.
  defp as_day_in(occurrence, :none), do: occurrence
  defp as_day_in(occurrence, {:ok, zone}), do: as_day_in(occurrence, zone)

  defp as_day_in(occurrence, zone) when is_binary(zone) do
    if Tempo.zoned?(occurrence) do
      occurrence
    else
      case Tempo.in_zone(occurrence, zone) do
        {:ok, placed} -> placed
        {:error, _} -> occurrence
      end
    end
  end

  defp project_occurrence(interval, day_start) do
    calendar = holiday_calendar(interval)

    with true <- sunset_calendar?(calendar),
         {:ok, projected} <- DayStart.project(interval, calendar, day_start) do
      Tempo.put_metadata(projected, Tempo.metadata(interval))
    else
      _midnight_calendar_or_error -> interval
    end
  end

  # The calendar that says how an occurrence's day begins: the one its
  # holiday's rule is in, which the occurrence carries as `:calendar`, or else
  # the calendar the day itself is in. A set of occurrences is in one calendar,
  # so the day of an Islamic holiday beside Gregorian ones is a Gregorian day.
  defp holiday_calendar(%Tempo{calendar: calendar} = interval) do
    Map.get(Tempo.metadata(interval), :calendar, calendar)
  end

  defp sunset_calendar?(calendar) when is_atom(calendar) do
    Code.ensure_loaded?(calendar) and function_exported?(calendar, :cldr_calendar_type, 0) and
      calendar.cldr_calendar_type() in @sunset_calendar_types
  end

  defp sunset_calendar?(_calendar), do: false
end
