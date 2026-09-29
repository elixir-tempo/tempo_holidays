defmodule Tempo.Holidays.Data do
  @moduledoc """
  Load the compiled holiday data, keyed by CLDR territory.

  The data is the real [date-holidays](https://github.com/commenthol/date-holidays)
  dataset, compiled to `priv/holidays/<CC>.etf` at build time by the `:holidays`
  Mix compiler (see `Tempo.Holidays.Build`) and shipped in the package. Loading
  it needs no JSON at runtime, so it works on every supported OTP.

  `for_territory/2` reads a territory's holidays, or a subdivision's;
  `subdivision/2` resolves a subdivision code to the level the data holds it
  at; `territories/0` lists the territories that carry data. A territory is loaded once and kept, its rules prepared
  (`Tempo.Holidays.Rule.prepare/1`) so that every later projection evaluates
  their already-built recurrences.

  """

  alias Tempo.Holidays.{Holiday, Rule}

  @doc """
  Return the compiled holidays for a territory, or one of its subdivisions.

  ### Arguments

  * `territory` is a CLDR territory code as an atom or string, such as `:AU`
    or `"AU"` (case-insensitive).

  * `subdivision` is a subdivision code, as `subdivision/2` resolves it, or
    `nil` for the territory's own holidays. The default is `nil`.

  ### Returns

  * `{:ok, [t:Tempo.Holidays.Holiday.t/0]}` — the territory's holidays, with a
    subdivision's own in place of the ones it redefines.

  * `{:error, {:unknown_territory, territory}}` for a territory without data
    — including a non-atom, non-string — or an error `subdivision/2` returns,
    so the function never raises on caller input.

  ### Examples

      iex> {:ok, holidays} = Tempo.Holidays.Data.for_territory(:AU)
      iex> Enum.any?(holidays, &(&1.name == "New Year's Day"))
      true

      iex> Tempo.Holidays.Data.for_territory(:ZZ)
      {:error, {:unknown_territory, :ZZ}}

  """
  @spec for_territory(atom() | String.t(), atom() | String.t() | nil) ::
          {:ok, [Holiday.t()]} | {:error, {atom(), term()}}
  def for_territory(territory, subdivision \\ nil) do
    with {:ok, data, path} <- locate(territory, subdivision) do
      {:ok, effective(data, path)}
    end
  end

  @doc """
  Resolve a subdivision code to the subdivision the territory's data holds.

  date-holidays keys a territory's data by state and, within a state, by
  region. A code names a subdivision at whichever level the data holds it: a
  state by its code (`"ENG"`, `"CA"`), a region by its own code when no state
  and no other region has it, or by its path from its state (`"CA-LA"`, Los
  Angeles, where `"LA"` alone is Louisiana). A leading territory code, as an
  ISO 3166-2 code has it (`"GB-ENG"`), is the same subdivision. Codes are
  case-insensitive.

  ### Arguments

  * `territory` is a CLDR territory code as an atom or string.

  * `subdivision` is a subdivision code as an atom or string, or `nil`.

  ### Returns

  * `{:ok, subdivision}` — the subdivision as the data names it, a state's code
    or a region's path from its state, or `nil` when none was given.

  * `{:error, {:unknown_territory, territory}}`,
    `{:error, {:unknown_subdivision, subdivision}}` for a code the data does
    not hold, or `{:error, {:ambiguous_subdivision, subdivision}}` for a region
    code two states share.

  ### Examples

      iex> Tempo.Holidays.Data.subdivision(:GB, "eng")
      {:ok, "ENG"}

      iex> Tempo.Holidays.Data.subdivision(:US, "CA-LA")
      {:ok, "CA-LA"}

      iex> Tempo.Holidays.Data.subdivision(:US, "LA")
      {:ok, "LA"}

      iex> Tempo.Holidays.Data.subdivision(:GB, "XYZ")
      {:error, {:unknown_subdivision, "XYZ"}}

  """
  @spec subdivision(atom() | String.t(), atom() | String.t() | nil) ::
          {:ok, String.t() | nil} | {:error, {atom(), term()}}
  def subdivision(territory, subdivision) do
    with {:ok, _data, path} <- locate(territory, subdivision) do
      {:ok, subdivision_name(path)}
    end
  end

  defp subdivision_name({nil, nil}), do: nil
  defp subdivision_name({state, nil}), do: state
  defp subdivision_name({state, region}), do: state <> "-" <> region

  # A territory's data and the `{state, region}` path of a subdivision in it.
  defp locate(territory, subdivision) when is_atom(territory) or is_binary(territory) do
    code = upcase(territory)

    case prepared(code) do
      {:ok, data} -> locate_in(data, code, subdivision)
      :error -> {:error, {:unknown_territory, territory}}
    end
  end

  defp locate(other, _subdivision), do: {:error, {:unknown_territory, other}}

  defp locate_in(data, _territory, nil), do: {:ok, data, {nil, nil}}

  defp locate_in(%{states: states} = data, territory, subdivision)
       when is_atom(subdivision) or is_binary(subdivision) do
    path =
      subdivision
      |> to_string()
      |> String.upcase()
      |> String.replace_prefix(territory <> "-", "")

    case String.split(path, "-", parts: 2) do
      [state, region] -> state_region(data, states, state, region, subdivision)
      [code] -> state_or_region(data, states, code, subdivision)
    end
  end

  defp locate_in(_data, _territory, subdivision),
    do: {:error, {:unknown_subdivision, subdivision}}

  defp state_region(data, states, state, region, subdivision) do
    with {:ok, state_key} <- find_key(states, state),
         {:ok, region_key} <- find_key(regions_of(Map.get(states, state_key)), region) do
      {:ok, data, {state_key, region_key}}
    else
      _unknown -> {:error, {:unknown_subdivision, subdivision}}
    end
  end

  defp state_or_region(data, states, code, subdivision) do
    case find_key(states, code) do
      {:ok, state_key} -> {:ok, data, {state_key, nil}}
      nil -> region_anywhere(data, states, code, subdivision)
    end
  end

  defp region_anywhere(data, states, code, subdivision) do
    matches =
      for {state_key, state} <- states,
          {:ok, region_key} <- [find_key(regions_of(state), code)],
          do: {state_key, region_key}

    case matches do
      [path] -> {:ok, data, path}
      [] -> {:error, {:unknown_subdivision, subdivision}}
      _several -> {:error, {:ambiguous_subdivision, subdivision}}
    end
  end

  defp regions_of(%{regions: regions}) when is_map(regions), do: regions
  defp regions_of(_state), do: %{}

  # A key matched without regard to case: the data spells a few regions in
  # mixed case (New Zealand's `Timaru`).
  defp find_key(map, code) do
    Enum.find_value(Map.keys(map), fn key -> if String.upcase(key) == code, do: {:ok, key} end)
  end

  # A state's holidays are the country's overridden by its own; each state
  # stores only its own holidays and the rule keys it defines, so the country's
  # holidays with those keys are dropped and the state's added, and a region's
  # the same over its state's.
  defp effective(%{country: country}, {nil, nil}), do: country

  defp effective(%{country: country, states: states}, {state, region}) do
    state_data = Map.get(states, state)

    country
    |> merge(state_data)
    |> merge(Map.get(regions_of(state_data), region))
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
