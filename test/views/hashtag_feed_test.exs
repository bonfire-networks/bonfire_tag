defmodule Bonfire.Tag.HashtagFeed.Test do
  use Bonfire.Tag.ConnCase, async: System.get_env("TEST_UI_ASYNC") != "no"
  alias Bonfire.Social.Fake
  alias Bonfire.Posts

  setup do
    account = fake_account!()
    me = fake_user!(account)
    alice = fake_user!(account)

    # Create my post with a hashtag
    my_hashtag = "testhashtag"
    my_post_content = "This is my post with a hashtag ##{my_hashtag}"
    my_post_attrs = %{post_content: %{html_body: my_post_content}}

    {:ok, my_post} =
      Posts.publish(current_user: me, post_attrs: my_post_attrs, boundary: "public")

    # Create Alice's post with a different hashtag
    alice_hashtag = "differenthashtag"
    alice_post_content = "This is Alice's post with another hashtag ##{alice_hashtag}"
    alice_post_attrs = %{post_content: %{html_body: alice_post_content}}

    {:ok, alice_post} =
      Posts.publish(current_user: alice, post_attrs: alice_post_attrs, boundary: "public")

    # Create Alice's second post with the same hashtag as mine
    alice_second_post_content = "Alice's second post also has"

    alice_second_post_attrs = %{
      post_content: %{html_body: "Alice's second post also has ##{my_hashtag}"}
    }

    {:ok, alice_second_post} =
      Posts.publish(current_user: alice, post_attrs: alice_second_post_attrs, boundary: "public")

    conn = conn(user: me, account: account)

    {:ok,
     conn: conn,
     account: account,
     alice: alice,
     me: me,
     my_post: my_post,
     alice_post: alice_post,
     alice_second_post: alice_second_post,
     my_hashtag: my_hashtag,
     alice_hashtag: alice_hashtag,
     my_post_content: my_post_content,
     alice_post_content: alice_post_content,
     alice_second_post_content: alice_second_post_content}
  end

  test "Post with hashtag gets properly tagged and linked", %{
    conn: conn,
    me: me,
    my_post: my_post,
    my_hashtag: my_hashtag
  } do
    # Reload the post with its tags
    tagged_post = my_post |> repo().maybe_preload(tagged: [tag: :named])

    # Verify the post has been properly tagged
    assert Enum.any?(tagged_post.tagged, fn tag_relation ->
             tag_relation.tag.named.name == my_hashtag
           end)

    # Verify the hashtag in the post content has been linked
    assert tagged_post.post_content.html_body =~ "[##{my_hashtag}](/hashtag/#{my_hashtag})"
  end

  test "Hashtag feed shows all posts with the specific hashtag", %{
    conn: conn,
    me: me,
    my_hashtag: my_hashtag,
    alice_hashtag: alice_hashtag,
    my_post_content: my_post_content,
    alice_post_content: alice_post_content,
    alice_second_post_content: alice_second_post_content
  } do
    # Visit the hashtag feed for my hashtag
    conn
    |> visit("/hashtag/#{my_hashtag}")

    # My post with the hashtag should appear
    |> assert_has("[data-id=feed] article")
    # |> PhoenixTest.open_browser()
    |> assert_has("[data-id=object_body]", text: my_hashtag)

    # Alice's second post with the same hashtag should appear
    |> assert_has("[data-id=object_body]", text: alice_second_post_content)

    # Alice's post with a different hashtag should not appear
    |> refute_has_or_open_browser("[data-id=object_body]", text: alice_hashtag)

    # Now visit Alice's hashtag feed
    conn
    |> visit("/hashtag/#{alice_hashtag}")
    # |> PhoenixTest.open_browser()

    # Alice's post with her hashtag should appear
    |> assert_has("[data-id=feed] article")
    |> assert_has("[data-id=object_body]", text: alice_hashtag)

    # My post and Alice's second post should not appear in this hashtag feed
    |> refute_has("[data-id=object_body]", text: my_hashtag)
    |> refute_has("[data-id=object_body]", text: alice_second_post_content)
  end

  test "Hashtag feed shows hashtag title correctly", %{
    conn: conn,
    my_hashtag: my_hashtag
  } do
    # Visit the hashtag feed
    conn
    |> visit("/hashtag/#{my_hashtag}")

    # Assert that the page contains the hashtag in the title or header
    |> assert_has("[role=banner]", text: "##{my_hashtag}")
  end

  test "Clicking on a hashtag link navigates to the hashtag feed", %{
    conn: conn,
    me: me,
    my_hashtag: my_hashtag,
    my_post_content: my_post_content
  } do
    # First visit my profile or the main feed to see the post
    conn
    |> visit("/user")
    |> assert_has_or_open_browser("[data-id=object_body]", text: my_hashtag)

    # Now click on the hashtag link within the post
    |> click_link(
      "[data-id=feed_activity_list]>div:first-child [data-id=object_body] a",
      "##{my_hashtag}"
    )

    # Verify we're on the hashtag page
    |> assert_path("/hashtag/#{my_hashtag}")

    # Assert the feed contains posts with that hashtag
    |> assert_has("[data-id=feed] article")
    |> assert_has("[data-id=object_body]", text: my_hashtag)
  end
end
