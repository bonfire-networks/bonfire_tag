defmodule Bonfire.Tag.Web.TagFeedLive do
  use Bonfire.UI.Common.Web, :surface_live_view
  alias Bonfire.UI.Social.FeedController

  on_mount {LivePlugs, [Bonfire.UI.Me.LivePlugs.LoadCurrentUser]}

  def mount(%{"id" => id} = _params, _session, socket) do
    # debug(id, "id")

    with {:ok, tag} <- Bonfire.Tag.get(id) do
      ok_assigns(
        socket,
        tag,
        e(tag, :profile, :name, nil) || e(tag, :post_content, :name, nil) || e(tag, :name, nil) ||
          e(tag, :named, :name, nil) || l("Tag")
      )
    else
      {:error, :not_found} -> mount(%{"hashtag" => id}, nil, socket)
    end
  end

  def mount(%{"hashtag" => hashtag}, _session, socket) do
    debug(hashtag, "hashtag")

    cond do
      not extension_enabled?(:bonfire_tag, socket) ->
        {:ok,
         socket
         |> redirect_to("/search?s=#{hashtag}")}

      is_uid?(hashtag) ->
        mount(%{"id" => hashtag}, nil, socket)

      true ->
        with {:ok, tag} <- Bonfire.Tag.get_hashtag(hashtag) do
          #  Bonfire.Tag.one([name: hashtag], pointable: Bonfire.Data.Identity.Named) do
          #  |> repo().maybe_preload(:named) do
          ok_assigns(socket, tag, "#{e(tag, :name, hashtag)}")
        end
    end
  end

  def ok_assigns(socket, tag, name) do
    {:ok,
     assign(
       socket,
       feed_name: :hashtag,
       feed_title: "#" <> name,
       page_title: "#" <> name,
       feed_filters: %{tags: id(tag)},
       page: "tag",
       back: true,
       object_type: nil,
       feed: [],
       hide_filters: true,
       #  smart_input_opts: %{text_suggestion: name}, # TODO: new post with tag button instead
       tag: tag,
       canonical_url: canonical_url(tag),
       name: name,
       nav_items: Bonfire.Common.ExtensionModule.default_nav(),
       sidebar_widgets: [
         users: [
           secondary: [
             {Bonfire.Tag.Web.WidgetTagsLive, []}
           ]
         ]
       ]
     )}
  end
end
