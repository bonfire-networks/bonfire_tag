defmodule Bonfire.Tag.Web.Component.TagAutocompleteMeiliDirect do
  @moduledoc """
  Alternative approach to tagging, using JS to directly use Meili's API, rather than passing through Elixir
  """
  use Bonfire.UI.Common.Web, :live_component

  #

  def mount(socket) do
    {:ok,
     assign(
       socket,
       meili_host: System.get_env("SEARCH_MEILI_INSTANCE", "http://localhost:7700"),
       tag_target: ""
     )}
  end
end
