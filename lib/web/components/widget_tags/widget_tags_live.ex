defmodule Bonfire.Tag.Web.WidgetTagsLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop widget_title, :string, default: nil
  prop wrapper_class, :string, default: nil
end
