defmodule Bonfire.Tag.PostsTest do
  use Bonfire.Tag.DataCase, async: true
  use Bonfire.Common.Utils

  alias Bonfire.Common.Config
  alias Bonfire.Me.Fake
  import Bonfire.Posts.Fake

  def repo, do: Config.repo()

  test "post without hashtags contains no tags" do
    user = Fake.fake_user!()

    post =
      fake_post!(user, "public", %{
        post_content: %{
          summary: "summary",
          name: "name",
          html_body: "epic html"
        }
      })
      |> repo().maybe_preload(tagged: :tag)

    assert post.tagged == []
  end

  test "post gets tagged at creation" do
    user = Fake.fake_user!()

    post =
      fake_post!(user, "public", %{
        post_content: %{
          summary: "summary",
          name: "name",
          html_body: "epic html #my_tag"
        }
      })
      |> repo().maybe_preload(tagged: [tag: :named])

    assert [%{tag: %{named: %{name: "my_tag"}}}] = post.tagged
    assert post.post_content.html_body =~ "[#my_tag](/hashtag/my_tag)"
  end
end
