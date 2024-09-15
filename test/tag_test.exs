defmodule Bonfire.Tag.TagTest do
  use Bonfire.Tag.DataCase, async: true
  use Bonfire.Common.Utils
  alias Bonfire.Tag

  def repo, do: Config.repo()

  test "hashtag creation" do
    assert {:error, _} = Tag.get("test")
    {:ok, tag} = Tag.get_or_create_hashtag("test")
    assert tag.named.name == "test"
  end
end
