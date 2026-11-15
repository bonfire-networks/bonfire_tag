defmodule Bonfire.Tag.TagEventPermissionsTest do
  @moduledoc """
  The tag event names the object by id, so it can be sent for any object the sender can see. Someone who can't edit the object can't change its tags with it.
  """
  use Bonfire.Tag.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Posts

  defp tagged_ids(post_id) do
    Bonfire.Data.Social.Post
    |> Bonfire.Common.Repo.get(post_id)
    |> Bonfire.Common.Repo.preload(:tagged, force: true)
    |> Map.get(:tagged)
    |> Enum.map(& &1.tag_id)
  end

  test "someone who doesn't own a post can't add tags to it" do
    owner = fake_user!(fake_account!())
    account = fake_account!()
    stranger = fake_user!(account)

    {:ok, post} =
      Posts.publish(
        current_user: owner,
        post_attrs: %{post_content: %{html_body: "A post with #ownertag"}},
        boundary: "public"
      )

    {:ok, other} =
      Posts.publish(
        current_user: stranger,
        post_attrs: %{post_content: %{html_body: "Another post with #strangertag"}},
        boundary: "public"
      )

    [owner_tag] = tagged_ids(post.id)
    [stranger_tag] = tagged_ids(other.id)
    refute owner_tag == stranger_tag

    {:ok, view, _html} = live(conn(user: stranger, account: account), "/feed/local")

    render_hook(view, "Bonfire.Tag:tag", %{"tag_id" => post.id, "tags" => stranger_tag})

    assert tagged_ids(post.id) == [owner_tag],
           "a user who doesn't own the post changed its tags"
  end
end
