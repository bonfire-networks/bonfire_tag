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
