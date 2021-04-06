defmodule Bonfire.Tag.Pages.Autocomplete do
  use Bonfire.Web, :controller

  import Bonfire.Tag.Autocomplete

  def get(conn, %{"prefix" => prefix, "search" => search, "consumer" => consumer}) do
    tags = tag_lookup(search, prefix, consumer)

    json(conn, tags)
  end

  def get(conn, %{"prefix" => prefix, "search" => search}) do
    tags = tag_lookup(search, prefix, "tag_as")

    json(conn, tags)
  end

end
