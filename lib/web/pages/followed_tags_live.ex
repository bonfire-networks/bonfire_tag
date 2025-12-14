defmodule Bonfire.Tag.Web.FollowedTagsLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias Bonfire.Social.Graph.Follows

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(_params, _session, socket) do
    current_user = current_user(socket.assigns)

    followed_tags =
      if current_user do
        Follows.list_followed(current_user, type: Bonfire.Tag.Hashtag)
        |> e(:edges, [])
        |> Enum.map(&e(&1, :edge, :object, nil))
        |> Enum.reject(&is_nil/1)
        |> repo().maybe_preload(:named)
      else
        []
      end

    {:ok,
     assign(socket,
       page_title: l("Followed Hashtags"),
       followed_tags: followed_tags,
       back: true,
       nav_items: Bonfire.Common.ExtensionModule.default_nav()
     )}
  end
end
