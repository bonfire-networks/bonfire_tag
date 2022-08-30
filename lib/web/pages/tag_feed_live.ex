defmodule Bonfire.Tag.Web.TagFeedLive do
  use Bonfire.UI.Common.Web, :surface_live_view

  alias Bonfire.UI.Me.LivePlugs

  def mount(params, session, socket) do
    live_plug params, session, socket, [
      LivePlugs.LoadCurrentAccount,
      LivePlugs.LoadCurrentUser,
      # LivePlugs.LoadCurrentUserCircles,
      Bonfire.UI.Common.LivePlugs.StaticChanged,
      Bonfire.UI.Common.LivePlugs.Csrf,
      Bonfire.UI.Common.LivePlugs.Locale,
      &mounted/3
    ]
  end

  defp mounted(%{"id"=>id}, _session, socket) do
    debug(id, "id")

    with {:ok, tag} <- Bonfire.Tag.Tags.get(id) do
      ok_assigns(socket, tag, "#{e(tag, :profile, :name, nil) || e(tag, :post_content, :name, nil) || e(tag, :name, nil) || e(tag, :named, :name, nil) || l "404"}")
    else
      {:error, :not_found} -> mounted(%{"hashtag"=>id}, nil, socket)
    end
  end

  defp mounted(%{"hashtag"=>hashtag}, _session, socket) do
    debug(hashtag, "hashtag")

    with {:ok, tag} <- Bonfire.Tag.Tags.one([name: hashtag], pointable: Bonfire.Tag.Hashtag) do
      ok_assigns(socket, tag, "##{e(tag, :name, hashtag)}")
    end
  end

  def ok_assigns(socket, tag, name) do
    {:ok,
    socket
    |> assign(
      page: "tag",
      object_type: nil,
      feed: [],
      selected_tab: :timeline,
      layout_mode: "full",
      without_header: false,
      smart_input_text: name,
      tag: tag,
      canonical_url: canonical_url(tag),
      name: name,
      page_title: name,

      # sidebar_widgets: [
      #   users: [
      #     main: [],
      #     secondary: [
      #       {Bonfire.Classify.Web.WidgetSubtopicsLive, [widget_title: l("Sub-topics of %{topic}", topic: e(tag, :character, :username, nil)), subcategories: subcategories.edges]},
      #       {Bonfire.UI.Common.WidgetFeedbackLive, []}
      #     ]
      #   ]
      # ]
    )}
  end

  def tab(selected_tab) do
    case maybe_to_atom(selected_tab) do
      tab when is_atom(tab) -> tab
      _ -> :timeline
    end
    # |> debug
  end

  def do_handle_params(%{"tab" => tab} = params, _url, socket) when tab in ["posts", "timeline"] do
    id = ulid(e(socket.assigns, :tag, nil))

    {:noreply, socket
    |> assign(selected_tab: tab)
    |> assign(
      Bonfire.Social.Feeds.LiveHandler.feed_assigns_maybe_async({"feed:profile:timeline", Bonfire.Tag.Tagged.q_with_tag(id)}, socket)
      |> debug("feed_assigns_maybe_async")
    )}
  end

  def do_handle_params(params, _url, socket) do
    # default tab
    do_handle_params(Map.merge(params || %{}, %{"tab" => "timeline"}), nil, socket)
  end

  def handle_params(params, uri, socket) do
    # poor man's hook I guess
    with {_, socket} <- Bonfire.UI.Common.LiveHandlers.handle_params(params, uri, socket) do
      undead_params(socket, fn ->
        do_handle_params(params, uri, socket)
      end)
    end
  end

  def handle_event(action, attrs, socket), do: Bonfire.UI.Common.LiveHandlers.handle_event(action, attrs, socket, __MODULE__)

end
