defmodule Tempo.Holidays.Data do
  @moduledoc """
  Load the compiled holiday data, keyed by CLDR territory.

  The data is the real [date-holidays](https://github.com/commenthol/date-holidays)
  dataset, compiled to `priv/holidays/<CC>.etf` at build time by the `:holidays`
  Mix compiler (see `Tempo.Holidays.Build`) and shipped in the package. Loading
  it needs no JSON at runtime, so it works on every supported OTP.

  `for_territory/1` reads one territory's file; `territories/0` lists those that
  carry data. A territory is loaded once and kept, its rules prepared
  (`Tempo.Holidays.Rule.prepare/1`) so that every later projection evaluates
  their already-built recurrences.

  """

  alias Tempo.Holidays.{Holiday, Rule}

  @doc """
  Return the compiled holidays for a territory.

  ### Arguments

  * `territory` is a CLDR territory code as an atom or string, such as `:AU`
    or `"AU"` (case-insensitive).

  ### Returns

  * `{:ok, [t:Tempo.Holidays.Holiday.t/0]}` for a territory that carries data.

  * `{:error, {:unknown_territory, territory}}` for any other value —
    including a non-atom, non-string — so the function never raises on caller
    input.

  ### Examples

      iex> {:ok, holidays} = Tempo.Holidays.Data.for_territory(:AU)
      iex> Enum.any?(holidays, &(&1.name == "New Year's Day"))
      true

      iex> Tempo.Holidays.Data.for_territory(:ZZ)
      {:error, {:unknown_territory, :ZZ}}

  """
  @spec for_territory(atom() | String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, [Holiday.t()]} | {:error, {:unknown_territory, term()}}
  def for_territory(territory, division \\ nil, subdivision \\ nil)

  def for_territory(territory, division, subdivision)
      when is_atom(territory) or is_binary(territory) do
    case prepared(upcase(territory)) do
      {:ok, country} -> {:ok, effective(country, upcase(division), upcase(subdivision))}
      :error -> {:error, {:unknown_territory, territory}}
    end
  end

  def for_territory(other, _division, _subdivision), do: {:error, {:unknown_territory, other}}

  # A state's holidays are the country's overridden by its own; each state
  # stores only its own holidays and the rule keys it defines, so the country's
  # holidays with those keys are dropped and the state's added. An unknown state
  # or region falls back to the level above, so a bad subdivision still yields
  # the national set.
  defp effective(%{country: country}, nil, _subdivision), do: country

  defp effective(%{country: country, states: states}, division, subdivision) do
    case Map.get(states, division) do
      nil -> country
      state -> country |> merge(state) |> merge(Map.get(state.regions, subdivision))
    end
  end

  defp merge(base, nil), do: base

  defp merge(base, %{holidays: additions, keys: keys}) do
    overridden = MapSet.new(keys)
    Enum.reject(base, &(&1.rule.source in overridden)) ++ additions
  end

  defp upcase(nil), do: nil
  defp upcase(value), do: value |> to_string() |> String.upcase()

  @doc """
  The territories that carry data, as sorted CLDR codes.

  ### Returns

  * A list of CLDR territory codes as strings, such as `["AD", "AE", …]`.

  ### Examples

      iex> "US" in Tempo.Holidays.Data.territories()
      true

  """
  @spec territories() :: [String.t()]
  def territories do
    with directory when is_binary(directory) <- holidays_dir(),
         {:ok, files} <- File.ls(directory) do
      files
      |> Enum.filter(&String.ends_with?(&1, ".etf"))
      |> Enum.map(&Path.basename(&1, ".etf"))
      |> Enum.sort()
    else
      _ -> []
    end
  end

  # A territory's data, loaded and prepared once — every rule's recurrence built
  # (`Rule.prepare/1`) — and kept for the life of the VM, so projecting its
  # holidays again builds and parses nothing. Each territory is a single
  # `:persistent_term` entry written once, which costs no global GC.
  defp prepared(code) do
    key = {__MODULE__, code}

    case :persistent_term.get(key, nil) do
      nil -> load_and_prepare(key, code)
      territory -> {:ok, territory}
    end
  end

  defp load_and_prepare(key, code) do
    with {:ok, territory} <- load(code) do
      prepared = prepare_territory(territory)
      :persistent_term.put(key, prepared)
      {:ok, prepared}
    end
  end

  defp prepare_territory(%{country: country, states: states} = territory) do
    %{territory | country: prepare_holidays(country), states: Map.new(states, &prepare_state/1)}
  end

  defp prepare_state({code, %{holidays: holidays, regions: regions} = state})
       when is_map(regions) do
    regions =
      Map.new(regions, fn {region_code, region} -> prepare_region(region_code, region) end)

    {code, %{state | holidays: prepare_holidays(holidays), regions: regions}}
  end

  defp prepare_state({code, %{holidays: holidays} = state}),
    do: {code, %{state | holidays: prepare_holidays(holidays)}}

  defp prepare_region(code, %{holidays: holidays} = region),
    do: {code, %{region | holidays: prepare_holidays(holidays)}}

  defp prepare_holidays(holidays), do: Enum.map(holidays, &prepare_holiday/1)

  defp prepare_holiday(%Holiday{rule: rule} = holiday), do: %{holiday | rule: Rule.prepare(rule)}

  # `File.read/1` returns a tagged tuple, so a missing territory file never
  # raises — it is simply an unknown territory.
  defp load(code) do
    with directory when is_binary(directory) <- holidays_dir(),
         path = Path.join(directory, "#{code}.etf"),
         {:ok, binary} <- File.read(path) do
      {:ok, deserialize(binary)}
    else
      _ -> :error
    end
  end

  defp holidays_dir do
    case :code.priv_dir(:tempo_holidays) do
      priv when is_list(priv) -> Path.join(priv, "holidays")
      _error -> nil
    end
  end

  # The etf is our own build output with a bounded, already-interned atom set
  # (struct and field names, and the kind/type/direction atoms compiled into
  # this library), so plain `binary_to_term` is correct here. `[:safe]` is not:
  # its rejection raises, and this library does not rescue.
  defp deserialize(binary), do: :erlang.binary_to_term(binary)
end
