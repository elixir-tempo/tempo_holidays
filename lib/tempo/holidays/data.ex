defmodule Tempo.Holidays.Data do
  @moduledoc """
  Load the compiled holiday data, keyed by CLDR territory.

  The data is the real [date-holidays](https://github.com/commenthol/date-holidays)
  dataset, compiled to `priv/holidays/<CC>.etf` at build time by the `:holidays`
  Mix compiler (see `Tempo.Holidays.Build`) and shipped in the package. Loading
  it needs no JSON at runtime, so it works on every supported OTP.

  `for_territory/1` reads one territory's file; `territories/0` lists those that
  carry data.

  """

  alias Tempo.Holidays.Holiday

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
  @spec for_territory(atom() | String.t()) ::
          {:ok, [Holiday.t()]} | {:error, {:unknown_territory, term()}}
  def for_territory(territory) when is_atom(territory) or is_binary(territory) do
    case load(String.upcase(to_string(territory))) do
      {:ok, holidays} -> {:ok, holidays}
      :error -> {:error, {:unknown_territory, territory}}
    end
  end

  def for_territory(other), do: {:error, {:unknown_territory, other}}

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
