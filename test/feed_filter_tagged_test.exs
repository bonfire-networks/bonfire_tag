defmodule Bonfire.Tag.FeedFilterTaggedTest do
  @moduledoc """
  The `tags` feed filter takes what a thing is tagged *with*, by id or by hashtag name, and both halves matter to more than tagging.

  A mention is an ordinary `:create` carrying a Tagged row from the post to the person named, so nothing about the activity says "mention" and only the tag does. That makes "mentions of me" this filter with the reader's id in it, which is what the notifications Mentions chip and the unsolicited-mention audience rows both need.

  Characterised here before the filter moves out of `bonfire_social`: a Tagged row is this extension's, so the query that reads one belongs here too, and these tests are what says the move changed nothing.
  """
  use Bonfire.Tag.DataCase, async: true
  use Bonfire.Common.Utils

  doctest Bonfire.Tag.FeedFilters, import: true

  alias Bonfire.Social.FeedLoader
  alias Bonfire.Me.Fake
  import Bonfire.Posts.Fake

  # both halves, each on its own: a key with no field is dropped by the cast, and a field with no module validates and filters nothing, and either way every test below just sees an unfiltered feed
  test "the filter's key is a field on FeedFilters, declared from this extension's config" do
    fields = Bonfire.Social.FeedFilters.__schema__(:fields)

    # what the config holds now against what the schema was compiled with, so a failure says which one lacks the field: the config (where it is declared) or the build (which reads it when `bonfire_social` compiles)
    seen =
      "config: #{inspect(Application.get_env(:bonfire_social, Bonfire.Social.FeedFilters)[:field])}, schema fields: #{inspect(fields)}"

    assert :tags in fields, seen
    assert :exclude_tags in fields, seen
  end

  test "the module that applies it is registered with the feed loader" do
    assert Bonfire.Tag.FeedFilters in Bonfire.Common.FeedFilterModule.modules()
  end

  setup do
    # tests paginate at 2 by default, and the control below wants all three fixtures on one page: without this the oldest falls off and reads as "the filter excluded it"
    Process.put([:bonfire, :default_pagination_limit], 10)

    me = Fake.fake_user!()
    author = Fake.fake_user!()

    mentioning =
      fake_post!(author, "public", %{
        post_content: %{html_body: "hey @#{me.character.username} look at this"}
      })

    hashtagged =
      fake_post!(author, "public", %{post_content: %{html_body: "about #noctilucent things"}})

    plain = fake_post!(author, "public", %{post_content: %{html_body: "to nobody in particular"}})

    {:ok, me: me, author: author, mentioning: mentioning, hashtagged: hashtagged, plain: plain}
  end

  test "an id finds the post that names that person, and only that post", %{
    me: me,
    mentioning: mentioning,
    hashtagged: hashtagged,
    plain: plain
  } do
    feed = FeedLoader.feed(:custom, %{tags: [id(me)]}, current_user: me)

    assert FeedLoader.feed_contains?(feed, mentioning, current_user: me)
    refute FeedLoader.feed_contains?(feed, plain, current_user: me)
    refute FeedLoader.feed_contains?(feed, hashtagged, current_user: me)
  end

  test "a hashtag name finds the post carrying it, and not the one naming a person", %{
    me: me,
    mentioning: mentioning,
    hashtagged: hashtagged
  } do
    feed = FeedLoader.feed(:custom, %{tags: ["noctilucent"]}, current_user: me)

    assert FeedLoader.feed_contains?(feed, hashtagged, current_user: me)
    refute FeedLoader.feed_contains?(feed, mentioning, current_user: me)
  end

  test "an id and a name together find either, since a mixed list is an OR", %{
    me: me,
    mentioning: mentioning,
    hashtagged: hashtagged,
    plain: plain
  } do
    feed = FeedLoader.feed(:custom, %{tags: [id(me), "noctilucent"]}, current_user: me)

    assert FeedLoader.feed_contains?(feed, mentioning, current_user: me)
    assert FeedLoader.feed_contains?(feed, hashtagged, current_user: me)
    refute FeedLoader.feed_contains?(feed, plain, current_user: me)
  end

  test "excluding an id leaves out the post that names that person, and keeps the rest", %{
    me: me,
    mentioning: mentioning,
    hashtagged: hashtagged,
    plain: plain
  } do
    # "replies that don't name me" is this with the reader in it, so what matters as much as the exclusion is that nothing else goes with it
    feed =
      FeedLoader.feed(:custom, %{object_types: [:post], exclude_tags: [id(me)]}, current_user: me)

    refute FeedLoader.feed_contains?(feed, mentioning, current_user: me)
    assert FeedLoader.feed_contains?(feed, hashtagged, current_user: me)
    assert FeedLoader.feed_contains?(feed, plain, current_user: me)
  end

  test "excluding a hashtag name leaves out the post carrying it, and keeps the rest", %{
    me: me,
    mentioning: mentioning,
    hashtagged: hashtagged,
    plain: plain
  } do
    feed =
      FeedLoader.feed(:custom, %{object_types: [:post], exclude_tags: ["noctilucent"]},
        current_user: me
      )

    refute FeedLoader.feed_contains?(feed, hashtagged, current_user: me)
    assert FeedLoader.feed_contains?(feed, mentioning, current_user: me)
    assert FeedLoader.feed_contains?(feed, plain, current_user: me)
  end

  test "all three are in the same feed without the tag filter, so the filter is what excludes them",
       %{
         me: me,
         mentioning: mentioning,
         hashtagged: hashtagged,
         plain: plain
       } do
    # a filter that admits all three rather than no filter at all: a custom feed with an empty filter map resolves to no feed ids, which would make an empty feed look like a working control
    feed = FeedLoader.feed(:custom, %{object_types: [:post]}, current_user: me)

    assert FeedLoader.feed_contains?(feed, mentioning, current_user: me)
    assert FeedLoader.feed_contains?(feed, hashtagged, current_user: me)
    assert FeedLoader.feed_contains?(feed, plain, current_user: me)
  end
end
