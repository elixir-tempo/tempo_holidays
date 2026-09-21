defmodule Tempo.Holidays.Locale do
  @moduledoc """
  Resolve a holiday request's target territory from a locale.

  A request may name its target as a CLDR territory code (`:US`, `"US"`), a
  BCP 47 locale identifier (`"en-US"`, `"en-US-u-sd-usca"`, or the same as an
  atom), or a `t:Localize.LanguageTag.t/0` struct. `resolve/2` turns any of
  these into the three levels date-holidays keys its data by — matching its
  `country → state → region` shape:

  * `:territory` — the country (`"US"`).

  * `:division` — the state/province (`"CA"`), derived from the locale's
    subdivision (`u-sd`, e.g. `usca`).

  * `:subdivision` — a region within a state (`"LA"`), rarely present in a
    locale and usually given explicitly.

  A locale string or atom is **validated** through `Localize.validate_locale/1`,
  so a grammatically valid but unrecognised tag is rejected rather than
  atomised — untrusted input cannot exhaust the atom table. Each level can be
  overridden with a `:territory`, `:division`, or `:subdivision` option.

  """

  @type resolved :: %{
          territory: String.t(),
          division: String.t() | nil,
          subdivision: String.t() | nil
        }

  @doc """
  Resolve a locale, LanguageTag, or territory code to `{:ok, t:resolved/0}`.

  ### Arguments

  * `locale` is a CLDR territory code (atom or string), a BCP 47 locale
    identifier (atom or string), or a `t:Localize.LanguageTag.t/0`.

  ### Options

  * `:territory`, `:division`, `:subdivision` — override the value derived
    from the locale, each a CLDR code as an atom or string.

  ### Returns

  * `{:ok, t:resolved/0}` with upper-cased string codes, `nil` where a level
    is absent.

  * `{:error, {:invalid_locale, locale}}` when a locale string/atom does not
    validate and is not a plausible territory code.

  ### Examples

      iex> Tempo.Holidays.Locale.resolve("en-US-u-sd-usca")
      {:ok, %{territory: "US", division: "CA", subdivision: nil}}

      iex> Tempo.Holidays.Locale.resolve(:AU)
      {:ok, %{territory: "AU", division: nil, subdivision: nil}}

      iex> Tempo.Holidays.Locale.resolve("en-GB", division: "SCT")
      {:ok, %{territory: "GB", division: "SCT", subdivision: nil}}

  """
  @spec resolve(Localize.LanguageTag.t() | atom() | String.t(), keyword()) ::
          {:ok, resolved()} | {:error, {:invalid_locale, term()}}
  def resolve(locale, options \\ [])

  def resolve(%Localize.LanguageTag{} = tag, options) do
    {:ok, apply_overrides(from_tag(tag), options)}
  end

  def resolve(locale, options) when is_atom(locale) or is_binary(locale) do
    case Localize.validate_locale(locale) do
      {:ok, tag} -> {:ok, apply_overrides(from_tag(tag), options)}
      {:error, _} -> from_territory_code(locale, options)
    end
  end

  def resolve(other, _options), do: {:error, {:invalid_locale, other}}

  # ── from a validated LanguageTag ────────────────────────────────────

  defp from_tag(tag) do
    territory = territory_of(tag)

    %{
      territory: territory,
      division: division_of(tag, territory),
      subdivision: nil
    }
  end

  defp territory_of(tag) do
    case Localize.Territory.territory_from_locale(tag) do
      {:ok, territory} -> upcase(territory)
      {:error, _} -> nil
    end
  end

  # The `u-sd` subdivision encodes its region then the state suffix
  # (`usca` = US + CA); strip the territory prefix to get date-holidays' state
  # key.
  defp division_of(_tag, nil), do: nil

  defp division_of(tag, territory) do
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

  # ── from a bare territory code (not a valid locale) ─────────────────

  defp from_territory_code(code, options) do
    case upcase(code) do
      "" ->
        {:error, {:invalid_locale, code}}

      territory ->
        {:ok, apply_overrides(%{territory: territory, division: nil, subdivision: nil}, options)}
    end
  end

  # ── overrides ───────────────────────────────────────────────────────

  defp apply_overrides(resolved, options) do
    %{
      territory: override(options, :territory, resolved.territory),
      division: override(options, :division, resolved.division),
      subdivision: override(options, :subdivision, resolved.subdivision)
    }
  end

  defp override(options, key, default) do
    case Keyword.get(options, key) do
      nil -> default
      value -> upcase(value)
    end
  end

  defp upcase(nil), do: nil
  defp upcase(value), do: value |> to_string() |> String.upcase()
end
