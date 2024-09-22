defmodule Bonfire.Tag.PostsTest do
  use Bonfire.Tag.DataCase, async: true
  alias Bonfire.Tag.TextContent.Formatter
  alias Bonfire.Me.Fake

  describe "linkify should" do
    test "return an empty string on an empty string" do
      assert {"", [], [], []} = Formatter.linkify("")
    end

    test "find mention if the user exists and linkify it" do
      user = Fake.fake_user!()
      username = user.character.username
      content_with_mention = "hi @#{username}"

      assert {linkified_content, [{returned_display_name, %{id: returned_user_id}}], [], []} =
               Formatter.linkify(content_with_mention,
                 safe_mention: false,
                 content_type: "text/markdown"
               )

      assert linkified_content =~ "hi [#{returned_display_name}]("
      assert returned_display_name == "@#{username}"
      assert returned_user_id == user.id
    end

    test "find no mention if the user doesn't exist" do
      content_with_mention = "hi @missing_user"

      assert {content_with_mention, [], [], []} =
               Formatter.linkify(content_with_mention,
                 safe_mention: false,
                 content_type: "text/markdown"
               )
    end
  end
end
