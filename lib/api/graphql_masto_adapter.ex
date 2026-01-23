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

        # Use :object preload instead of default :object_profile since Hashtags
        # don't have :profile/:character associations, only :named
        result =
          Follows.list_followed(
            current_user,
            [type: Bonfire.Tag.Hashtag, preload: :object] ++ pagination_opts
          )

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

    # Featured Tags Endpoints

    @doc "Get user's featured/pinned hashtags"
    def featured_tags(_params, conn) do
      RestAdapter.with_current_user(conn, fn user ->
        RestAdapter.json(conn, get_featured_hashtags(user))
      end)
    end

    @doc """
    Get featured/pinned hashtags for a specific account.
    Mastodon API: GET /api/v1/accounts/:id/featured_tags

    This is a public endpoint that doesn't require authentication.
    """
    def account_featured_tags(%{"id" => user_id}, conn) do
      case Bonfire.Me.Users.by_id(user_id) do
        {:ok, target_user} -> RestAdapter.json(conn, get_featured_hashtags(target_user))
        _ -> RestAdapter.error_fn({:error, :not_found}, conn)
      end
    end

    # TODO: Feature/unfeature hashtag endpoints are disabled until Pins.pin supports
    # skip_federation option. Currently Pins.pin always tries to federate but there's
    # no federation handler for pins, causing errors. Options to fix:
    # 1. Add skip_federation support to maybe_federate_and_gift_wrap_activity in integration.ex
    # 2. Create a dedicated FeaturedHashtag schema that doesn't use Pins
    # See: https://docs.joinmastodon.org/methods/featured_tags/

    # @doc "Feature/pin a hashtag"
    # def feature_tag(%{"name" => name}, conn) do
    #   RestAdapter.with_current_user(conn, fn user ->
    #     with {:ok, hashtag} <- Bonfire.Tag.get_or_create_hashtag(name),
    #          {:ok, _pin} <-
    #            Bonfire.Social.Pins.pin(user, hashtag, nil,
    #              skip_boundary_check: true,
    #              skip_federation: true
    #            ) do
    #       hashtag = repo().maybe_preload(hashtag, :named)
    #       RestAdapter.json(conn, Mappers.Tag.from_featured_hashtag(hashtag))
    #     else
    #       {:error, reason} -> RestAdapter.error_fn({:error, reason}, conn)
    #     end
    #   end)
    # end

    # @doc "Unfeature/unpin a hashtag"
    # def unfeature_tag(%{"id" => id}, conn) do
    #   RestAdapter.with_current_user(conn, fn user ->
    #     case Bonfire.Common.Needles.get(id, skip_boundary_check: true) do
    #       {:ok, hashtag} when not is_nil(hashtag) ->
    #         Bonfire.Social.Pins.unpin(user, hashtag)
    #         Plug.Conn.send_resp(conn, 200, "")

    #       _ ->
    #         RestAdapter.error_fn({:error, :not_found}, conn)
    #     end
    #   end)
    # end

    def feature_tag(_params, conn) do
      RestAdapter.error_fn({:error, "Feature tags endpoint is not yet implemented"}, conn)
    end

    def unfeature_tag(_params, conn) do
      RestAdapter.error_fn({:error, "Unfeature tags endpoint is not yet implemented"}, conn)
    end

    # Helper to get featured hashtags for a user
    defp get_featured_hashtags(user) do
      Bonfire.Social.Pins.list_my(current_user: user, skip_boundary_check: true)
      |> e(:edges, [])
      |> Enum.map(fn pin -> e(pin, :edge, :object, nil) end)
      |> Enum.filter(&is_hashtag?/1)
      |> Enum.map(fn hashtag ->
        hashtag = repo().maybe_preload(hashtag, :named)
        Mappers.Tag.from_featured_hashtag(hashtag)
      end)
      |> Enum.reject(&is_nil/1)
    end

    defp is_hashtag?(%{__struct__: Bonfire.Tag.Hashtag}), do: true
    defp is_hashtag?(%{table_id: "7HASHTAG1SPART0FF01KS0N0MY"}), do: true
    defp is_hashtag?(_), do: false
  end
end
