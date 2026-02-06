defmodule Bonfire.Tag.Web.FollowedTagsLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias Bonfire.Social.Graph.Follows

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(_params, _session, socket) do
    current_user = current_user(socket.assigns)

    {followed_tags, page_info} = list_followed_tags(current_user, %{})

    {:ok,
     assign(socket,
       page_title: l("Followed Hashtags"),
       followed_tags: followed_tags,
       page_info: page_info,
       back: true
     )}
  end

  def handle_event("load_more", attrs, socket) do
    current_user = current_user(socket.assigns)
    {new_tags, page_info} = list_followed_tags(current_user, attrs)

    {:noreply,
     assign(socket,
       followed_tags: e(socket.assigns, :followed_tags, []) ++ new_tags,
       page_info: page_info
     )}
  end

  defp list_followed_tags(nil, _attrs), do: {[], nil}

  defp list_followed_tags(current_user, attrs) do
    result =
      Follows.list_followed(current_user,
        type: Bonfire.Tag.Hashtag,
        preload: :object,
        paginate: input_to_atoms(attrs)
      )

    tags =
      result
      |> e(:edges, [])
      |> Enum.map(&e(&1, :edge, :object, nil))
      |> Enum.reject(&is_nil/1)
      |> repo().maybe_preload(:named)

    {tags, e(result, :page_info, nil)}
  end
end
