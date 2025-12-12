if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.Tag.Web.MastoTagController do
    @moduledoc """
    Mastodon-compatible Tags API controller.

    Endpoints:
    - GET /api/v1/tags/:name - Get a hashtag
    - POST /api/v1/tags/:name/follow - Follow a hashtag
    - POST /api/v1/tags/:name/unfollow - Unfollow a hashtag
    - GET /api/v1/followed_tags - List followed hashtags
    """
    use Bonfire.UI.Common.Web, :controller

    alias Bonfire.Tag.API.GraphQLMasto.Adapter

    def show(conn, params), do: Adapter.show_tag(params, conn)
    def follow(conn, params), do: Adapter.follow_tag(params, conn)
    def unfollow(conn, params), do: Adapter.unfollow_tag(params, conn)
    def followed(conn, params), do: Adapter.followed_tags(params, conn)
  end
end
