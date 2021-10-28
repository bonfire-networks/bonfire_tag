# Based on code from Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Tag.TextContent.Formatter do
  # alias Bonfire.Tag.TextContent.Scrubber
  alias Bonfire.Common.Config
  alias Bonfire.Common.Utils
  alias Bonfire.Tag.Autocomplete
  require Logger

  @safe_mention_regex ~r/^(\s*(?<mentions>([@|&amp;|\+].+?\s+){1,})+)(?<rest>.*)/s
  @link_regex ~r"((?:http(s)?:\/\/)?[\w.-]+(?:\.[\w\.-]+)+[\w\-\._~%:/?#[\]@!\$&'\(\)\*\+,;=.]+)|[0-9a-z+\-\.]+:[0-9a-z$-_.+!*'(),]+"ui
  @markdown_characters_regex ~r/(`|\*|_|{|}|[|]|\(|\)|#|\+|-|\.|!)/

  defp linkify_opts do
    Config.get(Bonfire.Tag.TextContent.Formatter, []) ++
      [
        hashtag: true,
        hashtag_handler: &Bonfire.Tag.TextContent.Formatter.tag_handler/4,
        mention: true,
        mention_handler: &Bonfire.Tag.TextContent.Formatter.tag_handler/4
      ]
  end

  def escape_mention_handler("@" <> nickname = mention, buffer, _, _) do
    case Autocomplete.search_prefix(nickname, "@") do
      %{id: _} ->
        # escape markdown characters with `\\`
        # (we don't want something like @user__name to be parsed by markdown)
        String.replace(mention, @markdown_characters_regex, "\\\\\\1")

      _ ->
        buffer
    end
  end

  def escape_mention_handler("&" <> _nickname = mention, _buffer, _, _) do
    String.replace(mention, @markdown_characters_regex, "\\\\\\1")
  end

  def escape_mention_handler("+" <> _nickname = mention, _buffer, _, _) do
    String.replace(mention, @markdown_characters_regex, "\\\\\\1")
  end

  def tag_handler("#" <> tag = tag_text, _buffer, opts, acc) do
    url = Bonfire.Common.URIs.base_url()<>"/tag/#{tag}"

    # TODO? save hashtag as a Category

    link = tag_link("#", url, tag_text, Map.get(opts, :content_type))

    {link, %{acc | tags: MapSet.put(acc.tags, {tag_text, tag})}}
  end

  def tag_handler("@" <> nickname, buffer, opts, acc) do
    case Autocomplete.search_prefix(nickname, "@") do
      u when is_map(u) or ( is_list(u) and length(u)>0 ) ->
        mention_process(opts, only_or_first(u), acc, Map.get(opts, :content_type))

      no ->
        Logger.warn("Tag.tag_handler: could not process mention for #{nickname}, expected a map or list, got #{inspect no}")
        {buffer, acc}
    end
  end

  def tag_handler("&" <> nickname, buffer, opts, acc) do
    case Autocomplete.search_prefix(nickname, "&")  do
      u when is_map(u) or is_list(u) and length(u)>0 ->
        mention_process(opts, only_or_first(u), acc, Map.get(opts, :content_type))

      _ ->
        {buffer, acc}
    end
  end

  def tag_handler("+" <> nickname, buffer, opts, acc) do

    case Autocomplete.search_prefix(nickname, "+") do
      u when is_map(u) or is_list(u) and length(u)>0 ->
        mention_process(opts, only_or_first(u), acc, Map.get(opts, :content_type))

      _ ->
        {buffer, acc}
    end
  end

  defp only_or_first(u) do
    if is_list(u), do: List.first(u), else: u
  end

  defp mention_process(_opts, obj, acc, content_type) do

    url = if Bonfire.Common.Extend.extension_enabled?(Bonfire.Me.Characters), do: Bonfire.Me.Characters.character_url(obj)
    display_name = if Bonfire.Common.Extend.extension_enabled?(Bonfire.Me.Characters), do: Bonfire.Me.Characters.display_username(obj)

    link = tag_link(nil, url, display_name, content_type)

    {link, %{acc | mentions: MapSet.put(acc.mentions, {display_name, obj})}}
  end

  defp tag_link(type, url, display_name, content_type \\ "text/html")

  defp tag_link(type, url, display_name, nil),
    do: tag_link(type, url, display_name, "text/html")

  defp tag_link(_type, url, display_name, "text/markdown") do
    "[#{display_name}](#{url})"
  end

  defp tag_link("#", url, tag, "text/html") do
    Phoenix.HTML.Tag.content_tag(:a, "#{tag}",
      class: "hashtag",
      "data-tag": tag,
      href: url,
      rel: "tag ugc"
    )
    |> Phoenix.HTML.safe_to_string()
  end

  defp tag_link(_type, url, display_name, "text/html") do
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

  @doc """
  Parses a text and replace plain text links with HTML. Returns a tuple with a result text, mentions, and hashtags.

  If the 'safe_mention' option is given, only consecutive mentions at the start the post are actually mentioned.
  """
  @spec linkify(String.t(), keyword()) ::
          {String.t(), [{String.t(), User.t()}], [{String.t(), String.t()}]}
  def linkify(text, options \\ []) do
    options = linkify_opts() ++ options

    if options[:safe_mention] && Regex.named_captures(@safe_mention_regex, text) do
      %{"mentions" => mentions, "rest" => rest} = Regex.named_captures(@safe_mention_regex, text)
      acc = %{mentions: MapSet.new(), tags: MapSet.new()}

      {text_mentions, %{mentions: mentions}} = Linkify.link_map(mentions, acc, options)
      {text_rest, %{tags: tags}} = Linkify.link_map(rest, acc, options)

      {text_mentions <> text_rest, MapSet.to_list(mentions), MapSet.to_list(tags)}
    else
      acc = %{mentions: MapSet.new(), tags: MapSet.new()}
      {text, %{mentions: mentions, tags: tags}} = Linkify.link_map(text, acc, options)

      {text, MapSet.to_list(mentions), MapSet.to_list(tags)}
    end
  end

  @doc """
  Escapes a special characters in mention names.
  """
  def mentions_escape(text, options \\ []) do
    options =
      Keyword.merge(options,
        mention: true,
        url: false,
        mention_handler: &Bonfire.Tag.TextContent.Formatter.escape_mention_handler/4
      )

    if options[:safe_mention] && Regex.named_captures(@safe_mention_regex, text) do
      %{"mentions" => mentions, "rest" => rest} = Regex.named_captures(@safe_mention_regex, text)
      Linkify.link(mentions, options) <> Linkify.link(rest, options)
    else
      Linkify.link(text, options)
    end
  end

  def html_escape({text, mentions, hashtags}, type) do
    {html_escape(text, type), mentions, hashtags}
  end

  def html_escape(text, "text/html") do
    if Utils.module_enabled?(Scrubber), do: Scrubber.filter_tags(text),
    else: text
  end

  def html_escape(text, "text/plain") do
    Regex.split(@link_regex, text, include_captures: true)
    |> Enum.map_every(2, fn chunk ->
      {:safe, part} = Phoenix.HTML.html_escape(chunk)
      part
    end)
    |> Enum.join("")
  end
end
