defmodule Bonfire.Tag.Web.TagFeedLive do
  use Bonfire.UI.Common.Web, :surface_live_view

  alias Bonfire.UI.Me.LivePlugs

  def mount(params, session, socket) do
    live_plug(params, session, socket, [
      LivePlugs.LoadCurrentAccount,
      LivePlugs.LoadCurrentUser,
      # LivePlugs.LoadCurrentUserCircles,
      Bonfire.UI.Common.LivePlugs.StaticChanged,
      Bonfire.UI.Common.LivePlugs.Csrf,
      Bonfire.UI.Common.LivePlugs.Locale,
      &mounted/3
    ])
  end

  defp mounted(%{"id" => id}, _session, socket) do
    # debug(id, "id")

    with {:ok, tag} <- Bonfire.Tag.Tags.get(id) do
      ok_assigns(
        socket,
        tag,
        e(tag, :profile, :name, nil) || e(tag, :post_content, :name, nil) || e(tag, :name, nil) ||
          e(tag, :named, :name, nil) || l("404")
      )
    else
      {:error, :not_found} -> mounted(%{"hashtag" => id}, nil, socket)
    end
  end

  defp mounted(%{"hashtag" => hashtag}, _session, socket) do
    debug(hashtag, "hashtag")

    with {:ok, tag} <-
           Bonfire.Tag.Tags.one([name: hashtag], pointable: Bonfire.Tag.Hashtag) do
      ok_assigns(socket, tag, "#{e(tag, :name, hashtag)}")
    end
  end

  def ok_assigns(socket, tag, name) do
    {:ok,
     assign(
       socket,
       page: "tag",
       page_title: name,
       object_type: nil,
       feed: [],
       hide_tabs: true,
       selected_tab: :timeline,
       smart_input_opts: %{text: name},
       tag: tag,
       canonical_url: canonical_url(tag),
       name: name,
       page_title: name,
       nav_items: Bonfire.Common.ExtensionModule.default_nav(:bonfire_ui_social),
       sidebar_widgets: [
         users: [
           secondary: [
             {Bonfire.Tag.Web.WidgetTagsLive, []}
           ]
         ]
       ]
     )}
  end

  def tab(selected_tab) do
    case maybe_to_atom(selected_tab) do
      tab when is_atom(tab) -> tab
      _ -> :timeline
    end

    # |> debug
  end

  def do_handle_params(%{"tab" => tab} = _params, _url, socket)
      when tab in ["posts", "timeline"] do
    {:noreply,
     socket
     |> assign(
       Bonfire.Social.Feeds.LiveHandler.feed_assigns_maybe_async(
         {"feed:profile:timeline",
          Bonfire.Tag.Tagged.q_with_tag(ulid(e(socket.assigns, :tag, nil)))},
         socket
       )
       |> debug("feed_assigns_maybe_async")
     )
     |> assign(
       selected_tab: tab(tab),
       page_title: e(socket.assigns, :name, nil),
       #  page_title: "#{e(socket.assigns, :name, nil)} #{tab(tab)}")
       page_header_icon: "mingcute:hashtag-fill"
     )}
  end

  def do_handle_params(params, _url, socket) do
    # default tab
    do_handle_params(
      Map.merge(params || %{}, %{"tab" => "timeline"}),
      nil,
      socket
    )
  end

  def handle_params(params, uri, socket),
    do:
      Bonfire.UI.Common.LiveHandlers.handle_params(
        params,
        uri,
        socket,
        __MODULE__,
        &do_handle_params/3
      )

  def handle_info(info, socket),
    do: Bonfire.UI.Common.LiveHandlers.handle_info(info, socket, __MODULE__)

  def handle_event(
        action,
        attrs,
        socket
      ),
      do:
        Bonfire.UI.Common.LiveHandlers.handle_event(
          action,
          attrs,
          socket,
          __MODULE__
          # &do_handle_event/3
        )
end
