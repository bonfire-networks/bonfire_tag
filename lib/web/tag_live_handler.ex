defmodule Bonfire.Tag.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler
  use Bonfire.Common.Repo

  declare_extension("Tag",
    icon: "ci:label",
    emoji: "🏷️",
    description:
      l(
        "Tag content, whether that's with simple hashtags or with other extensions such as Classify, Topics, Groups..."
      )
  )

  # def handle_event("new", attrs, socket) do
  #   new(attrs, socket)
  # end

  def maybe_tag(creator, object, tags, mentions_are_private? \\ false) do
    # if module_enabled?(Bonfire.Tag.Tags, creator) do
    boost_category_tags? = !mentions_are_private?

    Bonfire.Tag.Tags.maybe_tag(creator, object, tags, boost_category_tags?)
    |> debug()

    # ~> maybe_boostable_categories(creator, e(..., :tags, [])) # done in Bonfire.Tag.Tags instead
    # ~> auto_boost(..., object)
    # else
    #   error("No tagging extension enabled.")
    # end
  end

  def handle_event("tag", %{"tags" => tags} = params, socket) do
    with {:ok, _} <-
           maybe_tag(
             current_user_required!(socket),
             e(params, "tag_id", nil) || e(socket.assigns, :object, nil),
             tags
           ) do
      Bonfire.UI.Common.OpenModalLive.close()

      {:noreply,
       socket
       |> assign_flash(:info, l("Tagged!"))}
    end
  end

  def handle_event("autocomplete", %{"input" => input} = params, socket) do
    suggestions =
      Bonfire.Tag.Autocomplete.tag_lookup_public(
        input,
        maybe_to_module(params["type"])
      )
      |> debug()

    {:noreply,
     assign(socket,
       autocomplete: (e(socket.assigns, :autocomplete, []) ++ suggestions) |> Enum.uniq()
     )}
  end
end
