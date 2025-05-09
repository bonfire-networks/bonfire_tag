if Code.ensure_loaded?(Bonfire.Posts) do
  defmodule Bonfire.Tag.PostsTest do
    use Bonfire.Tag.DataCase, async: true
    use Bonfire.Common.Utils

    alias Bonfire.Tag
    alias Bonfire.Posts
    use Bonfire.Common.Config
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

    test "post with hashtag gets tagged at creation" do
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

    test "post with mention gets tagged at creation" do
      user = Fake.fake_user!()
      name = user.character.username

      post =
        fake_post!(user, "public", %{
          post_content: %{
            summary: "summary",
            name: "name",
            html_body: "epic html @#{name}"
          }
        })
        |> repo().maybe_preload(tagged: [tag: [:character]])

      assert [%{tag: %{character: %{username: tagged_username}}}] = post.tagged
      assert name == tagged_username
      assert post.post_content.html_body =~ "[@#{name}](/character/#{name})"
    end

    test "Tag.cast should add a Tagged entry to the changeset" do
      user = Fake.fake_user!()

      {:ok, %{id: _} = tag} = Tag.get_or_create_hashtag("test")

      changeset =
        Tag.cast(Posts.changeset(:create, %{}), %{tags: [tag]}, user)

      assert [%{action: :insert, valid?: true, params: %{"tag_id" => _}}] =
               changeset.changes.tagged
    end
  end
end
