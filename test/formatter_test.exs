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

    test "does not crash on markdown doc links with trailing parens" do
      text = """
      # **mix gettext.merge**

      Merges PO/POT files with PO files.

      This task is used when messages in the source code change: when they do, [`mix gettext.extract`](https://hexdocs.pm/gettext/Mix.Tasks.Gettext.Extract.html) is usually used to extract the new messages to POT files. At this point, developers or translators can use this task to "sync" the newly-updated POT files with the existing locale-specific PO files. All the metadata for each message (like position in the source code, comments, and so on) is taken from the newly-updated POT file; the only things taken from the PO file are the actual translated strings.

      #### **Fuzzy Matching**

      Messages in the updated PO/POT file that have an exact match (a message with the same `msgid`) in the old PO file are merged as described above. When a message in the updated PO/POT files has no match in the old PO file, Gettext attemps a **fuzzy match** for that message. For example, imagine we have this POT file:

      ```
      msgid "hello, world!"
      msgstr ""
      ```

      and we merge it with this PO file:

      ```
      # No exclamation point here in the msgid
      msgid "hello, world"
      msgstr "ciao, mondo"
      ```

      Since the two messages are similar, Gettext takes the `msgstr` from the existing message over to the new message, which it however marks as *fuzzy*:

      ```
      #, fuzzy
      msgid "hello, world!"
      msgstr "ciao, mondo"
      ```

      Generally, a `fuzzy` flag calls for review from a translator.

      Fuzzy matching can be configured (for example, the threshold for message similarity can be tweaked) or disabled entirely. Look at the ["Options" section](https://hexdocs.pm/gettext/Mix.Tasks.Gettext.Merge.html#module-options).

      ## **Usage**

      ```
      mix gettext.merge OLD_FILE UPDATED_FILE [OPTIONS]
      mix gettext.merge DIR [OPTIONS]
      ```

      If two files are given as arguments, `OLD_FILE` must be a `.po` file and `UPDATE_FILE` must be a `.po`/`.pot` file. The first one is the old PO file, while the second one is the last generated one. They are merged and written over the first file. For example:

      ```
      mix gettext.merge priv/gettext/en/LC_MESSAGES/default.po priv/gettext/default.pot
      ```

      If only one argument is given, then that argument must be a directory containing Gettext messages (with `.pot` files at the root level alongside locale directories - this is usually a "backend" directory used by a Gettext backend, see [`Gettext.Backend`](https://hexdocs.pm/gettext/Gettext.Backend.html)). For example:

      ```
      mix gettext.merge priv/gettext
      ```

      If the `--locale LOCALE` option is given, then only the PO files in `<DIR>/<LOCALE>/LC_MESSAGES` will be merged with the POT files in `DIR`. If no options are given, then all the PO files for all locales under `DIR` are merged with the POT files in `DIR`.

      ## **Plural Forms**

      By default, Gettext will determine the number of plural forms for newly-generated messages by checking the value of `nplurals` in the `Plural-Forms` header in the existing `.po` file. If a `.po` file doesn't already exist and Gettext is creating a new one or if the `Plural-Forms` header is not in the `.po` file, Gettext will use the number of plural forms that the plural module (see [`Gettext.Plural`](https://hexdocs.pm/gettext/Gettext.Plural.html)) returns for the locale of the file being created. The content of the `Plural-Forms` header can be forced through the `--plural-forms-header` option (see below).

      ## **Options**

      * `--locale` - a string representing a locale. If this is provided, then only the PO files in `<DIR>/<LOCALE>/LC_MESSAGES` will be merged with the POT files in `DIR`. This option can only be given when a single argument is passed to the task (a directory).
      * `--no-fuzzy` - don't perform fuzzy matching when merging files.
      * `--fuzzy-threshold` - a float between `0` and `1` which represents the minimum Jaro distance needed for two messages to be considered a fuzzy match. Overrides the global `:fuzzy_threshold` option (see the docs for[`Gettext`](https://hexdocs.pm/gettext/Gettext.html) for more information on this option).
      * `--plural-forms` - (**deprecated in v0.22.0**) an integer strictly greater than `0`. If this is passed, new messages in the target PO files will have this number of empty plural forms. This is deprecated in favor of passing the `--plural-forms-header`, which contains the whole plural-forms specification. See the "Plural forms" section above.
      * `--plural-forms-header` - the content of the `Plural-Forms` header as a string. If this is passed, new messages in the target PO files will use this content to determine the number of plurals. See the ["Plural Forms" section](https://hexdocs.pm/gettext/Mix.Tasks.Gettext.Merge.html#module-plural-forms).
      * `--on-obsolete` - controls what happens when **obsolete** messages are found. If `mark_as_obsolete`, messages are kept and marked as obsolete. If `delete`, obsolete messages are deleted. Defaults to `delete`.
      * `--store-previous-message-on-fuzzy-match` - controls if the previous messages are recorded on fuzzy matches. Is off by default.

      # **Summary**

      ## **[Functions](https://hexdocs.pm/gettext/Mix.Tasks.Gettext.Merge.html#functions)**

      **[locale_dir(pot_dir, locale)](https://hexdocs.pm/gettext/Mix.Tasks.Gettext.Merge.html#locale_dir/2)**

      # **Functions**

      [Link to this function](https://hexdocs.pm/gettext/Mix.Tasks.Gettext.Merge.html#locale_dir/2 "Link to this function")

      # **locale_dir(pot_dir, locale)**

      [View Source](https://github.com/elixir-gettext/gettext/blob/v0.26.2/lib/mix/tasks/gettext.merge.ex#L199 "View Source")
      """

      # Just assert it returns a tuple and does not raise
      assert {_, _, _, _} = Formatter.linkify(text, content_type: "text/markdown")
    end
  end
end
