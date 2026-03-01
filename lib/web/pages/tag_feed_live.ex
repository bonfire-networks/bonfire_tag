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
        with {:ok, tag} <- Bonfire.Tag.get(hashtag) do
          ok_assigns(
            socket,
            tag,
            e(tag, :profile, :name, nil) || e(tag, :post_content, :name, nil) ||
              e(tag, :name, nil) ||
              e(tag, :named, :name, nil) || l("Tag")
          )
        end

      true ->
        with {:ok, tag} <- Bonfire.Tag.get_hashtag(hashtag) do
          #  Bonfire.Tag.one([name: hashtag], pointable: Bonfire.Data.Identity.Named) do
          #  |> repo().maybe_preload(:named) do
          ok_assigns(socket, tag, "#{e(tag, :name, hashtag)}")
        end
    end
  end

  def ok_assigns(socket, tag, name, feed_name \\ :hashtag) do
    {:ok,
     assign(
       socket,
       feed_name: feed_name,
       feed_title: "#" <> name,
       page_title: "#" <> name,
       feed_filters: %{tags: id(tag)},
       page: "tag",
       back: true,
       object_type: nil,
       feed: [],
       hide_filters: false,
       #  smart_input_opts: %{text_suggestion: name}, # TODO: new post with tag button instead
       tag: tag,
       canonical_url: canonical_url(tag),
       name: name,
       page_header_aside:
         if feed_name == :hashtag do
           [
             {Bonfire.Tag.Web.FollowHashtagButtonLive,
              [
                object_id: id(tag),
                path: path(tag),
                class: "btn btn-sm btn-primary",
                container_class: "flex items-center gap-2"
              ]}
           ]
         else
           []
         end,
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
