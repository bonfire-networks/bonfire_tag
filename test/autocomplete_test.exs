defmodule Bonfire.Tag.AutocompleteTest do
  use Bonfire.Tag.DataCase, async: false
  alias Bonfire.Tag.Autocomplete
  alias Bonfire.Me.Fake

  setup do
    me = Fake.fake_user!()
    {:ok, me: me}
  end

  test "@ mentions fall back to a local lookup when the search index has no hits", %{me: me} do
    _ = Fake.fake_user!(%{}, %{username: "zanzibarquokka"})

    Repatch.patch(Bonfire.Search, :adapter, [mode: :shared], fn -> Bonfire.Search.Sonic end)
    Repatch.patch(Bonfire.Search.Sonic, :search_by_type, [mode: :shared], fn _, _, _ -> [] end)

    ids = Autocomplete.api_tag_search("zanzibarq", "@", "ck5", me) |> Enum.map(& &1[:id])

    assert "@zanzibarquokka" in ids
  end

  describe "each prefix suggests its own types" do
    # a person, a group and a topic in that group, all matching the same text, so each prefix shows what it leaves out as well as what it finds
    setup %{me: me} do
      Repatch.patch(Bonfire.Search, :adapter, [mode: :shared], fn -> Bonfire.Search.Sonic end)
      Repatch.patch(Bonfire.Search.Sonic, :search_by_type, [mode: :shared], fn _, _, _ -> [] end)

      person = Fake.fake_user!(%{}, %{username: "zanzibarquokka"})
      group = Bonfire.Classify.Simulate.fake_group!(me, %{name: "Zanzibarquokka cooks"})

      topic =
        Bonfire.Classify.Simulate.fake_category!(me, group, %{
          type: :topic,
          name: "Zanzibarquokka recipes"
        })

      handle =
        &(&1
          |> Bonfire.Common.Repo.maybe_preload(:character)
          |> Map.get(:character)
          |> Map.get(:username))

      {:ok, person: handle.(person), group: handle.(group), topic: handle.(topic)}
    end

    test "@ suggests people only", %{me: me, person: person, group: group, topic: topic} do
      ids = Autocomplete.api_tag_search("zanzibarq", "@", "ck5", me) |> Enum.map(& &1[:id])

      assert "@#{person}" in ids, "control: the person is found"
      refute "@#{group}" in ids
      refute "@#{topic}" in ids
    end

    # `!` is the threadiverse's way of naming a group, so it suggests what `&` does
    for prefix <- ["&", "!"] do
      test "#{prefix} suggests groups and topics, not people", %{
        me: me,
        person: person,
        group: group,
        topic: topic
      } do
        prefix = unquote(prefix)
        ids = Autocomplete.api_tag_search("zanzibarq", prefix, "ck5", me) |> Enum.map(& &1[:id])

        assert "#{prefix}#{group}" in ids
        assert "#{prefix}#{topic}" in ids
        refute "#{prefix}#{person}" in ids
      end

      # `&` is the positive control for `!`: both reach the same lookup, so a miss on `!` means the prefix is not tried at all
      test "a #{prefix} handle typed in text is looked up" do
        assert Enum.any?(
                 Autocomplete.try_all_prefixes("#{unquote(prefix)}zanzibarq"),
                 &(&1[:tag_prefix] == unquote(prefix))
               )
      end
    end
  end

  test "@ mentions never fetch remote actors while a handle is being typed", %{me: me} do
    # guard: a remote fetch per keystroke of a half-typed domain would block the request
    Repatch.patch(ActivityPub.Actor, :get_cached_or_fetch, [mode: :shared], fn _, _ ->
      raise "autocomplete must not fetch remote actors"
    end)

    # positive control: the stub is active
    assert_raise RuntimeError, fn ->
      ActivityPub.Actor.get_cached_or_fetch([username: "x"], [])
    end

    for partial <- ["nobody@mastodon.s", "nobody@mastodon.so", "https://mastodon.so"] do
      assert Autocomplete.api_tag_search(partial, "@", "ck5", me) == []
    end
  end
end
