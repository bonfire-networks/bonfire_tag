defmodule Bonfire.Tag.Web.FollowHashtagButtonLive do
  use Bonfire.UI.Common.Web, :stateless_component

  prop object_id, :string, required: true
  prop path, :string, default: nil
  prop class, :css_class, default: "btn btn-sm btn-primary"
  prop container_class, :css_class, default: "flex items-center gap-2"
end
