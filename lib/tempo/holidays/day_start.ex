defmodule Tempo.Holidays.DayStart do
  @moduledoc """
  Projects a sunset-starting calendar day onto the Gregorian timeline.

  A day in Tempo is just a day: an Islamic or Hebrew holiday materialises to an
  in-calendar day value — `~o"1447Y1M1D[u-ca=islamic-umalqura]"` — that carries no
  day-start convention. The midnight-versus-sunset question only arises when that
  day is *projected* onto the Gregorian civil timeline, and then the honest answer
  is a datetime interval that begins when the day begins — sunset, or an 18:00
  proxy, the evening before — and ends at the next such boundary. A single day
  becomes `[sunset(D − 1), sunset(D))`; a multi-day holiday keeps its half-open
  span, `[sunset of the first evening, sunset that starts the day after the last)`.

  `project/3` performs that projection. It is deliberately self-contained — the
  day-start-aware projection of a calendar day belongs in Tempo, and this module
  is written to lift there with little change.

  ## The two axes

  The `day_start` argument selects a boundary and, optionally, where it is taken:

  * `:midnight` — no projection; the in-calendar day value is returned unchanged.

  * `:evening` / `:sunset` — the 18:00 proxy, or true sunset, at the calendar's
    canonical reference (Mecca for Islamic dates, Jerusalem for Hebrew).

  * `{:evening, anchor}` / `{:sunset, anchor}` — the same, at an explicit anchor:
    an IANA zone id (`"Asia/Kuala_Lumpur"`) or a `{longitude, latitude}` location
    (also a `t:Geo.Point.t/0` / `t:Geo.PointZ.t/0`). A location resolves to a zone
    through `tz_world` (an optional dependency) for the evening proxy; `:sunset`
    computes from the location directly and returns a UTC instant, so it needs no
    zone database.

  """

  alias Tempo.Interval

  # The canonical references: Islamic dates are anchored where Umm al-Qura is
  # defined (Mecca), Hebrew dates at Jerusalem. `{longitude, latitude}`.
  @mecca {39.8262, 21.4225}
  @riyadh_zone "Asia/Riyadh"
  @jerusalem {35.2137, 31.7683}
  @jerusalem_zone "Asia/Jerusalem"

  @evening_time ~T[18:00:00]

  @typedoc "An anchor for a day-start boundary: a zone id or a location."
  @type anchor :: String.t() | {number(), number()} | struct()

  @typedoc "How a calendar day begins when projected onto the Gregorian timeline."
  @type t :: :midnight | :evening | :sunset | {:evening | :sunset, anchor()}

  @doc """
  Project an in-calendar day interval onto the Gregorian timeline per `day_start`.

  ### Arguments

  * `interval` is a materialised occurrence, an in-calendar `t:Tempo.Interval.t/0`
    (an Islamic or Hebrew day, possibly spanning several days).

  * `calendar` is the occurrence's Calendrical calendar module, used to choose the
    canonical reference when no anchor is given.

  * `day_start` is a `t:t/0` — `:midnight` (the default, returns `interval`
    unchanged), `:evening`/`:sunset`, or a `{boundary, anchor}` pair.

  ### Returns

  * `{:ok, interval}` — the projected Gregorian datetime interval, or `interval`
    unchanged for `:midnight`.

  * `{:error, reason}` — a location was given for an evening projection but no
    zone could be resolved (`tz_world` absent or the point is over open water), or
    the sunset/boundary could not be computed.

  ### Examples

      iex> import Tempo.Sigils
      iex> {:ok, rule} = Tempo.Holidays.Compiler.compile("1 Shawwal")
      iex> {:ok, [day]} = Tempo.Holidays.Rule.materialise(rule, ~o"2025")
      iex> # :midnight leaves the in-calendar day untouched
      iex> {:ok, same} = Tempo.Holidays.DayStart.project(day, Calendrical.Islamic.UmmAlQura, :midnight)
      iex> same == day
      true
      iex> # projected onto Gregorian, the day begins at sunset the evening before
      iex> {:ok, projected} = Tempo.Holidays.DayStart.project(day, Calendrical.Islamic.UmmAlQura, :sunset)
      iex> {:ok, start} = Tempo.to_elixir(Tempo.Interval.from(projected))
      iex> DateTime.to_date(start)
      ~D[2025-03-29]

  """
  @spec project(Interval.t(), module(), t()) :: {:ok, Interval.t()} | {:error, term()}
  def project(interval, _calendar, :midnight), do: {:ok, interval}

  def project(interval, calendar, day_start) do
    {boundary, anchor} = normalise(day_start)

    with {:ok, from_date} <- gregorian_date(Interval.from(interval)),
         {:ok, to_date} <- gregorian_date(Interval.to(interval)),
         {:ok, from_instant} <- instant(boundary, Date.add(from_date, -1), anchor, calendar),
         {:ok, to_instant} <- instant(boundary, Date.add(to_date, -1), anchor, calendar) do
      Interval.new(Tempo.from_elixir(from_instant), Tempo.from_elixir(to_instant))
    end
  end

  # `:evening` / `:sunset` use the canonical anchor; a pair names its own.
  defp normalise(boundary) when boundary in [:evening, :sunset], do: {boundary, :canonical}
  defp normalise({boundary, anchor}) when boundary in [:evening, :sunset], do: {boundary, anchor}

  # True sunset is a location fact, returned as a UTC instant — it resolves only a
  # location, never a zone, so it needs neither a zone database nor tz_world.
  defp instant(:sunset, %Date{} = date, anchor, calendar) do
    Astro.sunset(location_for(anchor, calendar), date, time_zone: :utc)
  end

  # The 18:00 proxy is a wall-clock time in a zone, so it resolves a zone (a zone
  # id directly, a location through tz_world, or the calendar's canonical zone); a
  # location whose zone cannot be resolved is refused rather than guessed.
  defp instant(:evening, %Date{} = date, anchor, calendar) do
    case zone_for(anchor, calendar) do
      nil -> {:error, :zone_unresolved}
      zone -> evening_instant(date, zone)
    end
  end

  defp evening_instant(date, zone) do
    case DateTime.new(date, @evening_time, zone, Tz.TimeZoneDatabase) do
      {:ok, datetime} -> {:ok, datetime}
      {:ambiguous, _first, second} -> {:ok, second}
      {:gap, _just_before, just_after} -> {:ok, just_after}
      {:error, reason} -> {:error, reason}
    end
  end

  # A `{longitude, latitude}` for sunset: the anchor's own location, or the
  # calendar's canonical one when the anchor is a zone id or `:canonical`.
  defp location_for(:canonical, calendar), do: elem(canonical(calendar), 0)
  defp location_for(zone, calendar) when is_binary(zone), do: elem(canonical(calendar), 0)
  defp location_for(location, _calendar), do: coordinates(location)

  # A zone for the evening proxy: the zone id itself, the zone tz_world resolves
  # for a location, or the calendar's canonical zone.
  defp zone_for(:canonical, calendar), do: elem(canonical(calendar), 1)
  defp zone_for(zone, _calendar) when is_binary(zone), do: zone
  defp zone_for(location, _calendar), do: zone_of(location)

  defp canonical(Calendrical.Hebrew), do: {@jerusalem, @jerusalem_zone}
  defp canonical(_islamic), do: {@mecca, @riyadh_zone}

  # Astro takes a `{longitude, latitude}` tuple; unwrap a Geo point to one.
  defp coordinates({_longitude, _latitude} = tuple), do: tuple
  defp coordinates(%{coordinates: {longitude, latitude, _elevation}}), do: {longitude, latitude}
  defp coordinates(%{coordinates: {longitude, latitude}}), do: {longitude, latitude}

  # Resolve a location's IANA zone via tz_world when it is available *and* a
  # backend is running; without it (or over open water) there is no zone, so an
  # evening projection from a bare location is refused rather than guessed. The
  # backend check keeps tz_world's "no backend" from raising into the caller.
  defp zone_of(location) do
    if tz_world_ready?() do
      # A variable module is dispatched at runtime, so tz_world is not resolved
      # at compile time — the module stays a genuinely optional dependency.
      resolver = TzWorld

      case resolver.timezone_at(geo_point(location)) do
        {:ok, zone} -> zone
        _ -> nil
      end
    end
  end

  @tz_world_backends [
    TzWorld.Backend.SpatialIndex,
    TzWorld.Backend.EtsWithIndexCache,
    TzWorld.Backend.DetsWithIndexCache,
    TzWorld.Backend.Ets,
    TzWorld.Backend.Dets,
    TzWorld.Backend.Memory
  ]

  defp tz_world_ready? do
    Code.ensure_loaded?(TzWorld) and function_exported?(TzWorld, :timezone_at, 1) and
      Enum.any?(@tz_world_backends, &Process.whereis/1)
  end

  defp geo_point({longitude, latitude}), do: %Geo.Point{coordinates: {longitude, latitude}}
  defp geo_point(%{coordinates: _} = point), do: point

  # An interval boundary as a proleptic-Gregorian `t:Date.t/0`, from whatever
  # calendar the day is held in.
  defp gregorian_date(tempo) do
    with {:ok, date} <- Tempo.to_date(tempo) do
      Date.convert(date, Calendar.ISO)
    end
  end
end
