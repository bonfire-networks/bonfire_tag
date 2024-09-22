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

      test "using #{prefix}, find only first mention if safe_mention: true, but linkify all" do
        user_1 = Fake.fake_user!()
        display_name_1 = "#{unquote(prefix)}#{user_1.character.username}"
        user_2 = Fake.fake_user!()
        display_name_2 = "#{unquote(prefix)}#{user_2.character.username}"

        content_with_mentions = "#{display_name_1} say hi to #{display_name_2} "

        assert {linkified_content, [{returned_display_name, %{id: returned_user_id}}], [], []} =
                 Formatter.linkify(content_with_mentions,
                   safe_mention: true,
                   content_type: "text/markdown"
                 )

        assert linkified_content =~
                 ~r/^\[#{String.replace(returned_display_name, "+", "\\+")}\]\(.*\) say hi to \[#{String.replace(display_name_2, "+", "\\+")}\]\(.*\)/

        assert returned_display_name == display_name_1
        assert returned_user_id == user_1.id
      end
    end

    test "find tag and linkify it" do
      {linkified_text, [], [{"#taggie", tag}], []} =
        Formatter.linkify("what a nice #taggie",
          content_type: "text/markdown"
        )

      assert linkified_text =~ "what a nice [#taggie]("
      assert tag.named.name == "taggie"
    end
  end
end
