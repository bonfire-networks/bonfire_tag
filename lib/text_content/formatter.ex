# Based on code from Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# Copyright © 2021 Bonfire contributors <https://bonfirenetworks.org/>
# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Tag.TextContent.Formatter do
  use Bonfire.Common.Config
  alias Bonfire.Common.Utils
  alias Bonfire.Tag
  import Untangle
  use Bonfire.Common.E

  # should support:
  # @user
  # @user@example.com
  # @user@example.com:4000
  # @user@localhost:4000
  # &Community
  # &Community@instance.tld
  # +CategoryTag
  # +CategoryTag@instance.tld
  defp match_mention, do: ~r/^(?<prefix>[@&\+])(?<user>[a-zA-Z\d_-]+)(@(?<host>[^@]+))?$/

  # defp match_mention, do: ~r"^[@&\+][a-zA-Z\d_-]+@[a-zA-Z0-9_-](?:[a-zA-Z0-9-:]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-:]{0,61}[a-zA-Z0-9])?)*|[@&\+][a-zA-Z\d_-]+"u
  # defp match_mention, do: ~r"([@&\+][a-zA-Z\d_-]+@[a-zA-Z0-9:._-]+)*|([@&\+][a-zA-Z\d_-]+)*"u
  defp safe_mention_regex, do: ~r/^(\s*(?<mentions>([@|&amp;|\+].+?\s+){1,})+)(?<rest>.*)/s
  defp markdown_characters_regex, do: ~r/(`|\*|_|{|}|[|]|\(|\)|#|\+|-|\.|!)/

  @doc """
  Parses a text and replace plain text links with HTML. Returns a tuple with a result text, mentions, and hashtags.

  If the 'safe_mention' option is given, only consecutive mentions at the start the post are actually mentioned.

  """
  @spec linkify(String.t(), keyword()) ::
          {String.t(), [{String.t(), User.t()}], [{String.t(), String.t()}]}
  def linkify(text, options \\ []) do
    options = linkify_opts() ++ options

    if options[:safe_mention] && Regex.named_captures(safe_mention_regex(), text) do
      %{"mentions" => mentions, "rest" => rest} = Regex.named_captures(safe_mention_regex(), text)

      acc = %{mentions: MapSet.new(), tags: MapSet.new(), urls: MapSet.new()}

      {text_mentions, %{mentions: mentions}} = Linkify.link_map(mentions, acc, options)

      {text_rest, %{tags: tags, urls: urls}} = Linkify.link_map(rest, acc, options)

      {text_mentions <> text_rest, MapSet.to_list(mentions), MapSet.to_list(tags),
       MapSet.to_list(urls)}
    else
      acc = %{mentions: MapSet.new(), tags: MapSet.new(), urls: MapSet.new()}

      {text, %{mentions: mentions, tags: tags, urls: urls}} = Linkify.link_map(text, acc, options)

      {text, MapSet.to_list(mentions), MapSet.to_list(tags), MapSet.to_list(urls)}
    end
  end

  defp linkify_opts() do
    Config.get(Bonfire.Tag.TextContent.Formatter, []) ++
      [
        url_handler: &url_handler/3,
        hashtag: true,
        hashtag_handler: &tag_handler/4,
        mention: true,
        mention_handler: &tag_handler/4,
        mention_regex: match_mention(),
        email: true,
        strip_prefix: true,
        truncate: 30
      ]
  end

  def nothing_handler(text, _opts, acc) do
    {text, acc}
  end

  def url_handler(url, opts, acc) do
    {display_url, attrs} =
      Linkify.Builder.prepare_link(url, opts)
      |> debug("prepared")

    link =
      render_link(display_url, Map.new(attrs), Map.get(opts, :content_type))
      |> debug("render")

    {link, %{acc | urls: MapSet.put(acc.urls, {url, url})}}
  end

  def tag_handler("#" <> tag = tag_text, buffer, opts, acc) do
    with {:ok, hashtag} <- Bonfire.Tag.get_or_create_hashtag(tag) do
      tag = e(hashtag, :named, :name, nil) || tag
      url = Bonfire.Common.URIs.base_url() <> "/hashtag/#{tag}"
      link = tag_link("#", url, tag, Map.get(opts, :content_type))

      {link, %{acc | tags: MapSet.put(acc.tags, {"##{tag}", hashtag})}}
    else
      none ->
        warn("could not create Hashtag for #{tag_text}, got #{inspect(none)}")
        {buffer, acc}
    end
  end

  def tag_handler("@" <> nickname, buffer, opts, acc) do
    tag_handler("@", nickname, buffer, opts, acc)
  end

  def tag_handler("&" <> nickname, buffer, opts, acc) do
    tag_handler("&", nickname, buffer, opts, acc)
  end

  def tag_handler("+" <> nickname, buffer, opts, acc) do
    tag_handler("+", nickname, buffer, opts, acc)
  end

  def tag_handler("!" <> nickname, buffer, opts, acc) do
    tag_handler("!", nickname, buffer, opts, acc)
  end

  defp tag_handler(type, nickname, buffer, opts, acc) do
    case Tag.maybe_lookup_tag(nickname, type) do
      {:ok, tag_object} ->
        mention_process(
          type,
          tag_object,
          acc,
          Map.get(opts, :content_type),
          opts
        )

      none ->
        warn("could not process #{type} mention for #{nickname}, got #{inspect(none)}")

        {buffer, acc}
    end
  end

  defp mention_process(prefix, tag_object, acc, content_type, _opts) do
    url =
      if Bonfire.Common.Extend.extension_enabled?(Bonfire.Me.Characters),
        do: Bonfire.Common.Utils.maybe_apply(Bonfire.Me.Characters, :character_url, [tag_object])

    display_name =
      if Bonfire.Common.Extend.extension_enabled?(Bonfire.Me.Characters),
        do:
          Bonfire.Common.Utils.maybe_apply(Bonfire.Me.Characters, :display_username, [
            tag_object,
            false,
            nil,
            prefix
          ])

    link = tag_link(prefix, url, display_name, content_type)

    {link, %{acc | mentions: MapSet.put(acc.mentions, {display_name, tag_object})}}
  end

  defp tag_link(type, url, display_name, "text/markdown") do
    if String.starts_with?(display_name, type),
      do: "[#{display_name}](#{url})",
      else: "[#{type}#{display_name}](#{url})"
  end

  defp tag_link("#", url, tag, _html) do
    Phoenix.HTML.Tag.content_tag(:a, "##{tag}",
      class: "hashtag",
      "data-tag": tag,
      href: url,
      rel: "tag ugc"
    )
    |> Phoenix.HTML.safe_to_string()
  end

  defp tag_link(type, url, display_name, _html) do
    debug(type, "type")
    debug(display_name, "display_name")
    # possibly bugged, is it actually used anywhere?
    Phoenix.HTML.Tag.content_tag(
      :span,
      Phoenix.HTML.Tag.content_tag(
        :a,
        display_name,
        "data-user": display_name,
        class: "u-url mention",
        href: url,
        rel: "ugc"
      ),
      class: "h-card"
    )
    |> Phoenix.HTML.safe_to_string()
  end

  defp render_link(display_url, %{href: href}, "text/markdown") do
    "[#{display_url}](#{href})"
  end

  defp render_link(display_url, attrs, _html) do
    Linkify.Builder.format_url(attrs, display_url)
  end
end
