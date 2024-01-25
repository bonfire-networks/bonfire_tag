defmodule Bonfire.Tag.Web.TagModalLive do
  use Bonfire.UI.Common.Web, :stateless_component

  slot default
  prop parent_id, :string, default: nil
end
