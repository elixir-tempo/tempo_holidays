defmodule Tempo.Holidays.GrammarTest do
  use ExUnit.Case, async: true

  alias Tempo.Holidays.Grammar

  doctest Grammar

  # date-holidays-parser's own fixture: each rule with the tokens its parser
  # makes of it (v3.4.7, converted to JSON; see NOTICE).
  @fixture Path.expand("../fixtures/date_holidays_parser_tokens.json", __DIR__)
  @external_resource @fixture
  @rules @fixture |> File.read!() |> :json.decode() |> Map.fetch!("rules")

  # A token as the parser writes it: its keys camel-cased, as in the fixture.
  defp parser_shape(tokens) when is_list(tokens) do
    Enum.map(tokens, &parser_shape/1)
  end

  defp parser_shape(%{} = token) do
    Map.new(token, fn {key, value} -> {camel(key), parser_value(value)} end)
  end

  defp parser_value([%{} | _] = tokens) do
    parser_shape(tokens)
  end

  defp parser_value(value) do
    value
  end

  defp camel(key) do
    [first | rest] = key |> Atom.to_string() |> String.split("_")
    Enum.join([first | Enum.map(rest, &String.capitalize/1)])
  end

  test "every rule of the parser's fixture reads to the parser's tokens" do
    mismatched =
      for {rule, expected} <- @rules,
          {tokens, _rest} = Grammar.tokenize(rule),
          parser_shape(tokens) != expected do
        {rule, expected, parser_shape(tokens)}
      end

    assert map_size(@rules) == 119
    assert mismatched == []
  end

  test "a rule the grammar reads to its end is read whole" do
    assert {:ok, [%{fn: "gregorian", month: 12, day: 25}]} = Grammar.tokens("12-25")
  end

  test "a rule with text the grammar cannot read is an error that says where" do
    assert Grammar.tokens("12-25 on a full moon") == {:error, {:unread, "a full moon"}}
    assert Grammar.tokens("next blue moon") == {:error, {:unread, "next blue moon"}}
  end

  test "Dhu al-Qidah is the eleventh Islamic month, as the grammar spells it" do
    assert {:ok, [%{fn: "islamic", month: 11, day: 4}]} = Grammar.tokens("4 Dhu al-Qidah")
  end
end
