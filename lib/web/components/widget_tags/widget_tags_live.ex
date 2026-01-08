defmodule Bonfire.Tag.Web.WidgetTagsLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Tag
  prop widget_title, :string, default: nil
  prop wrapper_class, :string, default: nil
  prop always_show_reset_btn, :boolean, default: false

  def handle_event(
        "reset_trending",
        %{"for_last_x_days" => for_last_x_days, "limit" => limit},
        socket
      ) do
    Tag.trending_links_reset(String.to_integer(for_last_x_days), String.to_integer(limit))

    debug("")

    {:noreply,
     socket
     #  TODO: how to update them without reloading or making this a stateful component
     |> assign_flash(
       :info,
       l("Trending tags have been reset.") <> l(" You need to reload to see updates, if any.")
     )}
  end
end
