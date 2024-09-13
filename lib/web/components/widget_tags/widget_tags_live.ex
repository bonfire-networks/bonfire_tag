defmodule Bonfire.Tag.Web.WidgetTagsLive do
  use Bonfire.UI.Common.Web, :stateless_component
  alias Bonfire.Tag
  prop widget_title, :string, default: nil
  prop wrapper_class, :string, default: nil
  prop only_admin, :boolean, default: false

  def handle_event(
        "reset_trending",
        %{"for_last_x_days" => for_last_x_days, "limit" => limit},
        socket
      ) do
    Tag.list_trending_reset(String.to_integer(for_last_x_days), String.to_integer(limit))

    debug("reset trending tags")
    socket
  end
end
