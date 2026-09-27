defmodule Tempo.Holidays.Holiday do
  @moduledoc """
  A single holiday as the compiled data holds it: its name, its type, and the
  rule that places it in any year.

  This is the loader's record (`Tempo.Holidays.Data`), not what the public API
  returns: `Tempo.Holidays.recurrences/2` gives each holiday as a member of a
  `t:Tempo.RecurrenceSet.t/0` — its rule's recurrence, tagged with the holiday's
  `:id` (the rule), `:name` and `:type` — and `Tempo.Holidays.materialise/3` its
  occurrences, tagged the same way.

  """

  alias Tempo.Holidays.Rule

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
          rule: Rule.t()
        }

  @enforce_keys [:name, :rule]
  defstruct [:name, :rule, type: :public]
end
