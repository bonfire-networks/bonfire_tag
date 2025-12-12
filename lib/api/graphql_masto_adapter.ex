if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.Tag.API.GraphQLMasto.Adapter do
    @moduledoc """
    Mastodon-compatible Tag API endpoints powered by the GraphQL API.

    Handles follow/unfollow hashtags and listing followed hashtags.
    """

    use Bonfire.Common.Utils
    use Bonfire.Common.Repo

    use AbsintheClient,
      schema: Bonfire.API.GraphQL.Schema,
      action: [mode: :internal]

    alias Bonfire.API.GraphQL.RestAdapter
    alias Bonfire.API.MastoCompat.Mappers
    alias Bonfire.API.MastoCompat.PaginationHelpers
    alias Bonfire.Social.Graph.Follows

    def absinthe_pipeline(schema, opts) do
      context = Keyword.get(opts, :context, %{})

      context_with_loader =
        if Map.has_key?(context, :loader) do
          context
        else
          schema.context(context)
        end

      AbsintheClient.default_pipeline(schema, Keyword.put(opts, :context, context_with_loader))
    end

    @graphql "mutation ($name: String!) { follow_tag(name: $name) { id name } }"
    def do_follow_tag(conn, name), do: graphql(conn, :do_follow_tag, %{"name" => name})

    @graphql "mutation ($name: String!) { unfollow_tag(name: $name) { id name } }"
    def do_unfollow_tag(conn, name), do: graphql(conn, :do_unfollow_tag, %{"name" => name})

    @doc "Follow a hashtag"
    def follow_tag(%{"name" => name}, conn) do
      RestAdapter.with_current_user(conn, fn _user ->
        case do_follow_tag(conn, name) do
          %{data: %{follow_tag: hashtag}} when not is_nil(hashtag) ->
            RestAdapter.json(conn, Mappers.Tag.from_hashtag(hashtag, following: true))

          %{errors: errors} ->
            RestAdapter.error_fn({:error, errors}, conn)

          _ ->
            RestAdapter.error_fn({:error, :unexpected_response}, conn)
        end
      end)
    end

    @doc "Unfollow a hashtag"
    def unfollow_tag(%{"name" => name}, conn) do
      RestAdapter.with_current_user(conn, fn _user ->
        case do_unfollow_tag(conn, name) do
          %{data: %{unfollow_tag: hashtag}} when not is_nil(hashtag) ->
            RestAdapter.json(conn, Mappers.Tag.from_hashtag(hashtag, following: false))

          %{data: %{unfollow_tag: nil}} ->
            RestAdapter.error_fn({:error, :not_found}, conn)

          %{errors: errors} ->
            RestAdapter.error_fn({:error, errors}, conn)

          _ ->
            RestAdapter.error_fn({:error, :unexpected_response}, conn)
        end
      end)
    end

    @doc "Get a hashtag by name"
    def show_tag(%{"name" => name}, conn) do
      current_user = conn.assigns[:current_user]

      case Bonfire.Tag.get_hashtag(name) do
        {:ok, hashtag} ->
          following = current_user && Follows.following?(current_user, hashtag)
          RestAdapter.json(conn, Mappers.Tag.from_hashtag(hashtag, following: !!following))

        _ ->
          RestAdapter.error_fn({:error, :not_found}, conn)
      end
    end

    @doc "List followed hashtags for current user with pagination"
    def followed_tags(params, conn) do
      RestAdapter.with_current_user(conn, fn current_user ->
        # Mastodon spec: default 100, max 200
        limit = PaginationHelpers.validate_limit(params["limit"], default: 100, max: 200)
        pagination_opts = PaginationHelpers.build_pagination_opts(params, limit)

        result =
          Follows.list_followed(current_user, [type: Bonfire.Tag.Hashtag] ++ pagination_opts)

        {edges, page_info} = extract_edges_and_page_info(result)

        tags =
          edges
          |> Enum.map(&hashtag_from_follow/1)
          |> Enum.reject(&is_nil/1)

        conn
        |> PaginationHelpers.add_simple_link_headers(params, page_info, tags)
        |> RestAdapter.json(tags)
      end)
    end

    defp extract_edges_and_page_info(result) do
      case result do
        %{edges: edges, page_info: page_info} when is_list(edges) ->
          {edges, page_info}

        {:ok, %{edges: edges, page_info: page_info}} when is_list(edges) ->
          {edges, page_info}

        %{edges: edges} when is_list(edges) ->
          {edges, %{}}

        {:ok, %{edges: edges}} when is_list(edges) ->
          {edges, %{}}

        edges when is_list(edges) ->
          {edges, %{}}

        _ ->
          {[], %{}}
      end
    end

    defp hashtag_from_follow(follow) do
      follow
      |> e(:edge, :object, nil)
      |> repo().maybe_preload(:named)
      |> Mappers.Tag.from_hashtag(following: true)
    end
  end
end
