defmodule Tempo.HolidaysTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.Holidays
  alias Tempo.Holidays.{Compiler, Holiday}

  defp date_of(holidays, name) do
    holidays
    |> Map.new(fn {holiday, interval} -> {holiday.name, Tempo.Interval.from(interval)} end)
    |> Map.fetch!(name)
  end

  doctest Tempo.Holidays
  doctest Tempo.Holidays.Data
  doctest Tempo.Holidays.Compiler
  doctest Tempo.Holidays.Rule

  describe "recurrences/1" do
    test "returns the AU public holidays as recurrences" do
      assert {:ok, holidays} = Holidays.recurrences(:AU)
      assert length(holidays) == 8
      assert Enum.all?(holidays, &match?(%Holiday{type: :public}, &1))
    end

    test "an unknown territory is an error, not a crash" do
      assert {:error, {:unknown_territory, :ZZ}} = Holidays.recurrences(:ZZ)
    end

    test "a non-atom territory is an error, not a crash" do
      assert {:error, {:unknown_territory, "AU"}} = Holidays.recurrences("AU")
    end
  end

  describe "materialise/2" do
    test "projects every AU holiday onto 2026" do
      expected = %{
        "New Year's Day" => ~o"2026Y1M1D",
        "Australia Day" => ~o"2026Y1M26D",
        "Good Friday" => ~o"2026Y4M3D",
        "Easter Monday" => ~o"2026Y4M6D",
        "Anzac Day" => ~o"2026Y4M25D",
        "King's Birthday" => ~o"2026Y6M8D",
        "Christmas Day" => ~o"2026Y12M25D",
        "Boxing Day" => ~o"2026Y12M26D"
      }

      assert {:ok, holidays} = Holidays.materialise(:AU, ~o"2026")
      assert length(holidays) == 8

      for {holiday, interval} <- holidays do
        assert Tempo.Interval.from(interval) == Map.fetch!(expected, holiday.name)
      end
    end

    test "returns the holidays earliest first" do
      {:ok, holidays} = Holidays.materialise(:AU, ~o"2026")
      names = Enum.map(holidays, fn {holiday, _interval} -> holiday.name end)

      assert hd(names) == "New Year's Day"
      assert List.last(names) == "Boxing Day"
    end

    test "the recurrence re-projects onto a different year" do
      # 2027: Easter Sunday is 28 March, so Good Friday is the 26th; the
      # King's Birthday is the second Monday of June, the 14th.
      {:ok, holidays} = Holidays.materialise(:AU, ~o"2027")

      dates =
        Map.new(holidays, fn {holiday, interval} ->
          {holiday.name, Tempo.Interval.from(interval)}
        end)

      assert dates["Good Friday"] == ~o"2027Y3M26D"
      assert dates["Easter Monday"] == ~o"2027Y3M29D"
      assert dates["King's Birthday"] == ~o"2027Y6M14D"
      assert dates["Christmas Day"] == ~o"2027Y12M25D"
    end

    test "an unknown territory is an error, not a crash" do
      assert {:error, {:unknown_territory, :ZZ}} = Holidays.materialise(:ZZ, ~o"2026")
    end
  end

  describe "coalescing back-to-back entries" do
    test "two same-name abutting entries merge into one period" do
      # date-holidays splits a period it cannot express across a year
      # boundary into two entries under one name. Materialised, the two
      # abutting days are coalesced into the single span they describe.
      {:ok, part_1} = Compiler.compile("12-25")
      {:ok, part_2} = Compiler.compile("12-26")

      holidays = [
        %Holiday{name: "Festival", type: :school, rule: part_1},
        %Holiday{name: "Festival", type: :school, rule: part_2}
      ]

      assert {:ok, [{holiday, interval}]} = Holidays.materialise(holidays, ~o"2026")
      assert holiday.name == "Festival"
      assert Tempo.Interval.from(interval) == ~o"2026Y12M25D"
      assert Tempo.Interval.to(interval) == ~o"2026Y12M27D"
    end

    test "adjacent holidays with different names stay separate" do
      # Christmas (the 25th) and Boxing Day (the 26th) abut, but they are
      # different holidays, so coalescing leaves them apart.
      {:ok, holidays} = Holidays.materialise(:AU, ~o"2026")
      names = Enum.map(holidays, fn {holiday, _interval} -> holiday.name end)

      assert "Christmas Day" in names
      assert "Boxing Day" in names
      assert length(holidays) == 8
    end
  end

  describe "observed-date substitution" do
    test "a holiday on a Sunday is observed the following Monday" do
      # Australia Day 2025 falls on Sunday the 26th, so it is observed on
      # Monday the 27th.
      {:ok, holidays} = Holidays.materialise(:AU, ~o"2025")
      assert date_of(holidays, "Australia Day") == ~o"2025Y1M27D"
    end

    test "a holiday on a Saturday is observed the following Monday" do
      # New Year's Day 2028 falls on Saturday the 1st, observed Monday the 3rd.
      {:ok, holidays} = Holidays.materialise(:AU, ~o"2028")
      assert date_of(holidays, "New Year's Day") == ~o"2028Y1M3D"
    end

    test "a weekday holiday is not shifted" do
      # 26 January 2026 is a Monday — no substitution.
      {:ok, holidays} = Holidays.materialise(:AU, ~o"2026")
      assert date_of(holidays, "Australia Day") == ~o"2026Y1M26D"
    end

    test "a holiday carrying no substitution rule keeps its own date" do
      {:ok, anzac} = Compiler.compile("04-25")
      assert anzac.substitute == nil
    end
  end
end
