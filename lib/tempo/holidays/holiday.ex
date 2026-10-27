defmodule Tempo.Holidays.Holiday do
  @moduledoc """
  A single holiday as the compiled data holds it: its name, its type, the
  rule that places it in any year, and the dataset's dates around the rule.

  This is the loader's record (`Tempo.Holidays.Data`), not what the public API
  returns: `Tempo.Holidays.holidays/2` reads each rule with `Tempo.DateRule`
  and gives the holiday as a member of a recurrence set (a `t:Tempo.t/0`) —
  its rule's recurrence, tagged with the holiday's `:id` (the rule), `:name`
  and `:type` — and `Tempo.to_interval/2` converts that set to occurrences
  tagged the same way.

  The fields are the holiday's `:name` and `:type`; its `:rule`, as
  date-holidays writes it; the `:active` windows, `:disable`d and `:enable`d
  dates the dataset gives beside the rule, which `Tempo.DateRule.parse/2`
  takes as options; and whether it is a `:substitute` entry, a rule that
  begins `substitutes` and stands in for the holiday of its type on the
  weekdays it names.

  """

  @typedoc """
  The category a holiday falls under, following
  [date-holidays](https://github.com/commenthol/date-holidays): a `:public`
  holiday is a statutory day off, `:bank` a banking holiday, `:school` a
  school holiday, `:optional` a day observed at the holder's discretion, and
  `:observance` a marked but non-statutory day.
  """
  @type type :: :public | :bank | :school | :optional | :observance

  @type t :: %__MODULE__{
          name: String.t(),
          type: type(),
          rule: String.t(),
          active: [{Date.t() | nil, Date.t() | nil}],
          disable: [Date.t()],
          enable: [Date.t()],
          substitute: boolean()
        }

  @enforce_keys [:name, :rule]
  defstruct [:name, :rule, type: :public, active: [], disable: [], enable: [], substitute: false]
end
