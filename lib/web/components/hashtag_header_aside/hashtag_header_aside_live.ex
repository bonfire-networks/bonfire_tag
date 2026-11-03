defmodule Bonfire.Tag.Web.HashtagHeaderAsideLive do
  @moduledoc """
  A ⋯ menu in the hashtag page's header with the hashtag's actions: follow, and notifications. Shown to signed-in users only. Its bell asks for its state only when the menu first opens, so the page runs no notification query up front.
  """
  use Bonfire.UI.Common.Web, :stateless_component

  prop object_id, :string, required: true
  prop object, :any, default: nil
  prop path, :string, default: nil
end
