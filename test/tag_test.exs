defmodule Bonfire.Tag.TagTest do
  use Bonfire.Tag.DataCase, async: true
  use Bonfire.Common.Utils
  alias Bonfire.Tag
  def repo, do: Config.repo()

  test "tag creation" do
    assert {:error, _} = Tag.get("test")
    {:ok, tag_1} = Tag.get_or_create_hashtag("test")
    assert tag_1.named.name == "test"

    {:ok, tag_2} = Tag.get_or_create_hashtag("test")
    assert tag_1.id == tag_2.id
  end

  # eg. the Mastodon API's search asks for `limit: 20`
  test "search_hashtag returns no more than the limit" do
    for name <- ["quokkafirst", "quokkasecond", "quokkathird"],
        do: {:ok, _} = Tag.get_or_create_hashtag(name)

    assert length(Tag.search_hashtag("quokka")) == 3, "control: all three match"
    assert length(Tag.search_hashtag("quokka", limit: 2)) == 2
  end
end
