defmodule Bonfire.Tag.Web.WidgetFollowHashtagLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop object_id, :string, required: true
  prop path, :string, default: nil
  prop widget_title, :string, default: nil
  prop class, :css_class, default: "btn btn-sm btn-primary w-full"
  prop container_class, :css_class, default: "w-full"
end
