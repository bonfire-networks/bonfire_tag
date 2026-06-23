defmodule Bonfire.Tag.Web.API.Autocomplete do
  use Bonfire.UI.Common.Web, :controller

  alias Bonfire.Tag.Autocomplete
  import Untangle

  def get(conn, %{
        "prefix" => prefix,
        "search" => search,
        "consumer" => consumer
      }) do
    tags = Autocomplete.api_tag_search(search, prefix, consumer, current_user_or_id(conn))
    json(conn, prepare(tags))
  end

  def get(conn, %{"prefix" => prefix, "search" => search}) do
    tags = Autocomplete.api_tag_search(search, prefix, "tag_as", current_user_or_id(conn))
    json(conn, prepare(tags))
  end

  def prepare({key, val} = tags) when is_tuple(tags) do
    %{key => val}
  end

  def prepare(tags) do
    tags
  end
end
