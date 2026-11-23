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

  describe "groups of tags (eg. a category with its subtopics, and a label)" do
    setup %{author: author, me: me} do
      both = fake_post!(author, "public", %{post_content: %{html_body: "about #alpha and #beta"}})
      only_alpha = fake_post!(author, "public", %{post_content: %{html_body: "about #alpha"}})
      only_beta = fake_post!(author, "public", %{post_content: %{html_body: "about #beta"}})

      {:ok, both: both, only_alpha: only_alpha, only_beta: only_beta, me: me}
    end

    test "a list of groups finds what is tagged with one tag from each group, not what matches only one group",
         %{me: me, both: both, only_alpha: only_alpha, only_beta: only_beta} do
      # control: one flat list is an OR, so each of the three is found (and the filter is applied at all)
      flat = FeedLoader.feed(:custom, %{tags: ["alpha", "beta"]}, current_user: me)
      assert FeedLoader.feed_contains?(flat, only_alpha, current_user: me)
      assert FeedLoader.feed_contains?(flat, only_beta, current_user: me)

      feed = FeedLoader.feed(:custom, %{tags: [["alpha"], ["beta"]]}, current_user: me)

      assert FeedLoader.feed_contains?(feed, both, current_user: me)
      refute FeedLoader.feed_contains?(feed, only_alpha, current_user: me)
      refute FeedLoader.feed_contains?(feed, only_beta, current_user: me)
    end

    test "a group matches any one of its tags", %{
      me: me,
      both: both,
      only_alpha: only_alpha,
      only_beta: only_beta
    } do
      feed = FeedLoader.feed(:custom, %{tags: [["alpha", "gamma"], ["beta"]]}, current_user: me)

      assert FeedLoader.feed_contains?(feed, both, current_user: me)
      refute FeedLoader.feed_contains?(feed, only_alpha, current_user: me)
      refute FeedLoader.feed_contains?(feed, only_beta, current_user: me)
    end

    test "something with two of the matching tags is listed once, whether the tags are a flat list or a group",
         %{me: me, both: both} do
      # with and without the feed's own dedup of objects (`show_objects_only_once`, on by default), which would hide a row per tag from the join
      for tags <- [["alpha", "beta"], [["alpha", "beta"]]],
          dedup <- [true, false] do
        %{edges: edges} =
          FeedLoader.feed(:custom, %{tags: tags, show_objects_only_once: dedup}, current_user: me)

        # the feed has it (the filter is applied), and once
        assert Enum.count(edges, &(e(&1, :activity, :object_id, nil) == both.id)) == 1,
               "listed once for tags: #{inspect(tags)}, dedup: #{dedup}"
      end
    end
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
