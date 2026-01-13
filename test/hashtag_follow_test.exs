if Code.ensure_loaded?(Bonfire.Posts) and Code.ensure_loaded?(Bonfire.Social.Graph.Follows) do
  defmodule Bonfire.Tag.HashtagFollowTest do
    use Bonfire.Tag.DataCase, async: true
    use Bonfire.Common.Utils

    alias Bonfire.Tag
    alias Bonfire.Posts
    use Bonfire.Common.Config
    alias Bonfire.Me.Fake
    import Bonfire.Posts.Fake

    def repo, do: Config.repo()

    test "following a hashtag adds tagged posts to my feed" do
      user = Fake.fake_user!()
      other = Fake.fake_user!()

      {:ok, hashtag} =
        Tag.get_or_create_hashtag("my_tag")
        |> debug("the hashtag")

      # User follows the hashtag
      {:ok, _follow} =
        Bonfire.Social.Graph.Follows.follow(user, hashtag)
        |> debug("the follow")

      # Another user creates a post with the hashtag
      post =
        fake_post!(other, "public", %{
          post_content: %{
            summary: "summary",
            name: "name",
            html_body: "hello #my_tag"
          }
        })
        |> debug("the post")

      # Give time for triggers/async to complete if needed
      Process.sleep(500)

      # Check FeedPublish for correct entry
      # assert feed_publish_entry =
      #          Bonfire.Data.Social.FeedPublish
      #          |> repo().get_by(id: post.id, feed_id: hashtag.id)
      #          |> debug("feed_publish_entry")

      # Bonfire.Social.Feeds.my_home_feed_ids(user)
      # |> debug("fetching my feed ids")

      # Fetch the user's :my feed
      feed = Bonfire.Social.FeedLoader.my_feed(current_user: user)

      # Assert the post appears in the feed
      assert Bonfire.Social.FeedLoader.feed_contains?(feed, post)
    end
  end
end
