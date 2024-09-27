defmodule Bonfire.Tag.FormatterTest do
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

    for codeblock_delimiter <- ["`", "\n```\n"] do
      test "using #{codeblock_delimiter}, not linkify a URL inside a code block" do
        del = unquote(codeblock_delimiter)

        {linkified_text, [], [], []} =
          Formatter.linkify("#{del}https://google.com#{del} some text",
            content_type: "text/markdown"
          )

        assert linkified_text == "#{del}https://google.com#{del} some text"

        {linkified_text, [], [], []} =
          Formatter.linkify("#{del}before https://google.com after#{del} some text",
            content_type: "text/markdown"
          )

        assert linkified_text == "#{del}before https://google.com after#{del} some text"
      end

      test "using #{codeblock_delimiter}, linkify a URL outside a code block" do
        del = unquote(codeblock_delimiter)

        {linkified_text, [], [], [{"https://google.com", "https://google.com"}]} =
          Formatter.linkify(
            "#{del}some code#{del} https://google.com #{del}some other code#{del}",
            content_type: "text/markdown"
          )

        assert linkified_text ==
                 "#{del}some code#{del} [google.com](https://google.com) #{del}some other code#{del}"
      end
    end
  end
end
