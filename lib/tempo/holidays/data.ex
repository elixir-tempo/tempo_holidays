defmodule Tempo.Holidays.Data do
  @moduledoc """
  Built-in holiday definitions, keyed by CLDR territory.

  This is the seed slice — Australia's national public holidays as
  [date-holidays](https://github.com/commenthol/date-holidays) rule strings,
  compiled to `t:Tempo.Holidays.Holiday.t/0` on demand. A later
  `mix tempo.holidays.update` task will replace it with the full dataset
  compiled under `priv/holidays/`.

  """

  alias Tempo.Holidays.{Compiler, Holiday}

  # {name, date-holidays rule string}. Every Australian national day is a
  # `:public` holiday, so the type is left to the struct default. New Year
  # and Australia Day carry the standard "observed the following Monday when
  # they land on a weekend" substitution; Good Friday and Easter Monday are
  # always weekdays, and Anzac Day is commemorated on its own date. Christmas
  # and Boxing Day also substitute, but their weekend cascade (Boxing Day
  # steps past Christmas' observed Monday) needs collision resolution across
  # holidays — deferred to that pass.
  @territories %{
    AU: [
      {"New Year's Day", "01-01 if weekend then next monday"},
      {"Australia Day", "01-26 if weekend then next monday"},
      {"Good Friday", "easter -2"},
      {"Easter Monday", "easter 1"},
      {"Anzac Day", "04-25"},
      {"King's Birthday", "2nd Monday in June"},
      {"Christmas Day", "12-25"},
      {"Boxing Day", "12-26"}
    ]
  }

  @doc """
  Return the compiled holiday definitions for a territory.

  ### Arguments

  * `territory` is a CLDR territory code as an atom, such as `:AU`.

  ### Returns

  * `{:ok, [t:Tempo.Holidays.Holiday.t/0]}` for a territory with built-in
    data.

  * `{:error, {:unknown_territory, territory}}` for any other value,
    including a non-atom, so the function never raises on caller input.

  ### Examples

      iex> {:ok, holidays} = Tempo.Holidays.Data.for_territory(:AU)
      iex> length(holidays)
      8

      iex> Tempo.Holidays.Data.for_territory(:ZZ)
      {:error, {:unknown_territory, :ZZ}}

  """
  @spec for_territory(term()) :: {:ok, [Holiday.t()]} | {:error, {:unknown_territory, term()}}
  def for_territory(territory) when is_atom(territory) do
    case Map.fetch(@territories, territory) do
      {:ok, definitions} -> {:ok, Enum.flat_map(definitions, &compile_definition/1)}
      :error -> {:error, {:unknown_territory, territory}}
    end
  end

  def for_territory(other), do: {:error, {:unknown_territory, other}}

  @doc """
  The territories that carry built-in data.

  ### Returns

  * A list of CLDR territory atoms.

  ### Examples

      iex> Tempo.Holidays.Data.territories()
      [:AU]

  """
  @spec territories() :: [atom()]
  def territories, do: Map.keys(@territories)

  # A rule string this slice cannot yet compile is dropped rather than
  # failing the whole territory — partial support is correct for partial
  # data. The seed rules all compile; the guard matters once the full,
  # unfiltered dataset arrives.
  defp compile_definition({name, rule_string}) do
    case Compiler.compile(rule_string) do
      {:ok, rule} -> [%Holiday{name: name, rule: rule}]
      {:error, _} -> []
    end
  end
end
