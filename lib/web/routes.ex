defmodule Bonfire.Tag.Web.Routes do
  @behaviour Bonfire.UI.Common.RoutesModule

  defmacro __using__(_) do
    quote do
      # pages anyone can view
      scope "/", Bonfire.Tag.Web do
        pipe_through(:browser)

        live("/tags/autocomplete", API.Autocomplete)

        live("/tag/:id", TagFeedLive, as: Bonfire.Tag)
        live("/hashtag/:hashtag", TagFeedLive, as: Bonfire.Tag.Hashtag)
      end

      # pages you need an account to view
      scope "/", Bonfire.Tag.Web do
        pipe_through(:browser)
        pipe_through(:account_required)
      end

      # pages you need to view as a user
      scope "/", Bonfire.Tag.Web do
        pipe_through(:browser)
        pipe_through(:user_required)

        live("/hashtags/followed", FollowedTagsLive, as: Bonfire.Tag.FollowedTags)

        get("/api/tag/autocomplete/:prefix/:search", API.Autocomplete, :get)

        get(
          "/api/tag/autocomplete/:consumer/:prefix/:search",
          API.Autocomplete,
          :get
        )
      end
    end
  end
end
