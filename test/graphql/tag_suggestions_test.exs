if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.Tag.GraphQL.TagSuggestionsTest do
    use Bonfire.Tag.DataCase, async: false

    alias Bonfire.API.GraphQL.Schema

    @moduletag :graphql

    @query """
    query($query: String!, $prefix: String) {
      tag_suggestions(query: $query, prefix: $prefix) {
        id
        name
        icon
      }
    }
    """

    test "tag suggestions returns an empty list rather than null when there are no matches" do
      {:ok, result} =
        Absinthe.run(@query, Schema,
          variables: %{"query" => "unlikely-tag-suggestion-no-match", "prefix" => "#"}
        )

      refute result[:errors]
      assert get_in(result, [:data, "tag_suggestions"]) == []
    end

    test "tagSuggestions is exposed through the public GraphQL schema" do
      {:ok, result} =
        Absinthe.run(
          ~S|{ __schema { queryType { fields { name } } } }|,
          Schema
        )

      field_names =
        result
        |> get_in([:data, "__schema", "queryType", "fields"])
        |> Enum.map(& &1["name"])

      assert "tagSuggestions" in field_names
      refute result[:errors]
    end
  end
end
