defmodule Bonfire.Tag.Web.API.Autocomplete do
  use Bonfire.UI.Common.Web, :controller

  alias Bonfire.Tag.Autocomplete

  def get(conn, %{"prefix" => prefix, "search" => search, "consumer" => consumer}) do
    tags = Autocomplete.api_tag_lookup(search, prefix, consumer)

    json(conn, prepare(tags))
  end

  def get(conn, %{"prefix" => prefix, "search" => search}) do
    tags = Autocomplete.api_tag_lookup(search, prefix, "tag_as")

    json(conn, prepare(tags))
  end

  def prepare({key, val} = tags) when is_tuple(tags) do
    %{key => val}
  end
  def prepare(tags) do
    tags
  end

end
