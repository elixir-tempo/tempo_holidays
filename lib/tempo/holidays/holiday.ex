defmodule Tempo.Holidays.Holiday do
  @moduledoc """
  A single holiday: its name, its kind, and the recurrence rule that places
  it in any year.

  A holiday is a *definition* — a name paired with a
  `t:Tempo.Holidays.Rule.t/0` recurrence, not a date. `Tempo.Holidays.materialise/2`
  projects the rule onto a concrete year to obtain the interval it occupies
  there.

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
