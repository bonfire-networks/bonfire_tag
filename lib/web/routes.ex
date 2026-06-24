defmodule Bonfire.Tag.Web.Routes do
  @behaviour Bonfire.UI.Common.RoutesModule

  defmacro __using__(_) do
    quote do
      # pages you need an account to view
      scope "/", Bonfire.Tag.Web do
        pipe_through(:browser)
        pipe_through(:account_required)
      end

      # pages you need to view as a user
      scope "/", Bonfire.Tag.Web do
        pipe_through(:browser)
        pipe_through(:user_required)
        live("/tag/:id", TagFeedLive, as: Bonfire.Tag)
        live("/hashtag/:hashtag", TagFeedLive, as: Bonfire.Tag.Hashtag)
        live("/hashtags/followed", FollowedTagsLive, as: Bonfire.Tag.FollowedTags)
      end

      # hot autocomplete endpoint (hit on every keystroke): a read-only JSON GET that only needs an
      # authenticated session (NOT a full user load, and no CSRF/flash/layout) — the
      # :user_session_required plug fetches the session itself, so we skip the :browser pipeline
      scope "/", Bonfire.Tag.Web do
        pipe_through(:user_session_required)

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
