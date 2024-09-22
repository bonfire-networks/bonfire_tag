defmodule Bonfire.Tag.PostsTest do
  use Bonfire.Tag.DataCase, async: true
  alias Bonfire.Tag.TextContent.Formatter
  alias Bonfire.Me.Fake

  describe "linkify should" do
    test "return an empty string on an empty string" do
      assert {"", [], [], []} = Formatter.linkify("")
    end

    for prefix <- ["@", "+", "&"] do
      test "using #{prefix}, find mention if the user exists and linkify it" do
        user = Fake.fake_user!()
        username = user.character.username
        content_with_mention = "hi #{unquote(prefix)}#{username}"

        assert {linkified_content, [{returned_display_name, %{id: returned_user_id}}], [], []} =
                 Formatter.linkify(content_with_mention,
                   safe_mention: false,
                   content_type: "text/markdown"
                 )

        assert linkified_content =~ "hi [#{returned_display_name}]("
        assert returned_display_name == "#{unquote(prefix)}#{username}"
        assert returned_user_id == user.id
      end

      test "using #{prefix}, find no mention if the user doesn't exist" do
        content_with_mention = "hi #{unquote(prefix)}missing_user"

        assert {found_content, [], [], []} =
                 Formatter.linkify(content_with_mention,
                   safe_mention: false,
                   content_type: "text/markdown"
                 )

        assert found_content == content_with_mention
      end
    end
  end
end
