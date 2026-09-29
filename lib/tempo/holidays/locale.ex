defmodule Tempo.Holidays.Locale do
  @moduledoc """
  Resolve a holiday request's target territory.

  A request names its target as a positional CLDR territory code (`:US`, `"US"`)
  or `t:Localize.LanguageTag.t/0`, or through a `:territory` or `:locale` option.
  `resolve/2` turns any of these into the territory and the subdivision within
  it:

  * `:territory` — the country (`"US"`).

  * `:subdivision` — a subdivision code (`"CA"`), from a locale's `u-sd`
    subdivision (`usca`) or the `:subdivision` option, which
    `Tempo.Holidays.Data.subdivision/2` finds at whichever level the data holds
    it.

  A **positional** code and the `:territory` option are validated as territories
  through `Localize.validate_territory/1`, so `:SA` is Saudi Arabia — never parsed
  as the Sanskrit *language*. A `:locale` (or a `LanguageTag`) derives its
  territory through `Localize.Territory.territory_from_locale/1`, validated via
  `Localize.validate_locale/1` so untrusted input cannot exhaust the atom table.

  """

  @type resolved :: %{territory: String.t() | nil, subdivision: term()}

  @doc """
  Resolve a target to `{:ok, t:resolved/0}`.

  ### Arguments

  * `target` is a positional CLDR territory code (atom or string) or a
    `t:Localize.LanguageTag.t/0`; `nil` when the target is given by option.

  ### Options

  * `:territory` — an explicit CLDR territory code (atom or string), validated.

  * `:locale` — a BCP 47 locale identifier (atom or string) or a
    `t:Localize.LanguageTag.t/0`, whose territory is derived.

  * `:subdivision` — a subdivision code, in place of a locale's own.

  ### Returns

  * `{:ok, t:resolved/0}` with the territory upper-cased, and the subdivision
    as a locale names it or as the option gives it, `nil` for none.

  * `{:error, {:unknown_territory, code}}` for an unrecognised territory,
    `{:error, {:invalid_locale, target}}` for a target that is neither, or
    `{:error, {:invalid_option, options}}` when `options` is not a list.

  ### Examples

      iex> Tempo.Holidays.Locale.resolve(:AU)
      {:ok, %{territory: "AU", subdivision: nil}}

      iex> Tempo.Holidays.Locale.resolve(nil, locale: "en-US-u-sd-usca")
      {:ok, %{territory: "US", subdivision: "CA"}}

      iex> Tempo.Holidays.Locale.resolve(nil, territory: :SA)
      {:ok, %{territory: "SA", subdivision: nil}}

  """
  @spec resolve(Localize.LanguageTag.t() | atom() | String.t() | nil, keyword()) ::
          {:ok, resolved()} | {:error, {atom(), term()}}
  def resolve(target, options \\ [])

  def resolve(target, options) when is_list(options) do
    cond do
      Keyword.has_key?(options, :territory) ->
        from_territory(Keyword.get(options, :territory), options)

      Keyword.has_key?(options, :locale) ->
        from_locale(Keyword.get(options, :locale), options)

      true ->
        from_positional(target, options)
    end
  end

  def resolve(_target, options), do: {:error, {:invalid_option, options}}

  # A bare positional target is a territory (a `LanguageTag` is a locale); this is
  # the sugar for `holidays(:AU)` / `materialise(:AU, year)`. A territory code
  # is never parsed as a language, so `:SA` is Saudi Arabia, not Sanskrit.
  defp from_positional(%Localize.LanguageTag{} = tag, options) do
    {:ok, apply_overrides(from_tag(tag), options)}
  end

  defp from_positional(code, options) when is_atom(code) or is_binary(code) do
    from_territory(code, options)
  end

  defp from_positional(other, _options), do: {:error, {:invalid_locale, other}}

  # ── from a validated LanguageTag ────────────────────────────────────

  defp from_tag(tag) do
    territory = territory_of(tag)

    %{territory: territory, subdivision: subdivision_of(tag, territory)}
  end

  defp territory_of(tag) do
    case Localize.Territory.territory_from_locale(tag) do
      {:ok, territory} -> upcase(territory)
      {:error, _} -> nil
    end
  end

  # The `u-sd` subdivision encodes its territory then the subdivision's own code
  # (`usca` = US + CA); strip the territory prefix to get the subdivision code.
  defp subdivision_of(_tag, nil), do: nil

  defp subdivision_of(tag, territory) do
    case Map.get(tag.locale, :sd) do
      nil ->
        nil

      subdivision ->
        prefix = String.downcase(territory)

        subdivision
        |> to_string()
        |> String.replace_prefix(prefix, "")
        |> upcase()
    end
  end

  # ── from an explicit `:territory` code ──────────────────────────────

  # The `:territory` option, and a positional territory, are validated through
  # `Localize.validate_territory/1` — an unknown code is a clean error, not a
  # holiday-less territory.
  defp from_territory(code, options) do
    case Localize.validate_territory(code) do
      {:ok, territory} ->
        {:ok, apply_overrides(%{territory: upcase(territory), subdivision: nil}, options)}

      {:error, _} ->
        {:error, {:unknown_territory, to_string(code)}}
    end
  end

  # ── from a `:locale` (BCP 47 id, atom, or LanguageTag) ──────────────

  # The `:locale` option derives the intended territory via
  # `Localize.Territory.territory_from_locale/1` (through `from_tag/1`), and
  # carries any `u-sd` subdivision.
  defp from_locale(%Localize.LanguageTag{} = tag, options) do
    {:ok, apply_overrides(from_tag(tag), options)}
  end

  defp from_locale(locale, options) do
    case Localize.validate_locale(locale) do
      {:ok, tag} -> {:ok, apply_overrides(from_tag(tag), options)}
      {:error, _} -> {:error, {:invalid_locale, locale}}
    end
  end

  # ── overrides ───────────────────────────────────────────────────────

  # `:territory` and `:locale` select the territory (see `resolve/2`); only the
  # `:subdivision` override is applied here, as given, for
  # `Tempo.Holidays.Data.subdivision/2` to find or refuse.
  defp apply_overrides(resolved, options) do
    case Keyword.get(options, :subdivision) do
      nil -> resolved
      subdivision -> %{resolved | subdivision: subdivision}
    end
  end

  defp upcase(nil), do: nil
  defp upcase(value), do: value |> to_string() |> String.upcase()
end
