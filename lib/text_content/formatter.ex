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
    # caller options win, eg. to disable `mention`/`hashtag` parsing while still linkifying URLs
    options = linkify_opts(options)

    # only worth pulling apart when we're actually going to parse the hashtags
    {text, trailing_line} =
      if options[:hashtag] != false, do: extract_trailing_hashtags(text), else: {text, ""}

    {text, %{mentions: mentions, tags: tags, urls: urls}} = do_linkify(text, options)

    # Process trailing hashtags through Linkify for DB creation, wrapped in one invisible block
    {text, tags} =
      if trailing_line != "" do
        {trailing_text, %{tags: trailing_tags}} = do_linkify(trailing_line, options)

        {text <> "<span class=\"invisible\"> " <> trailing_text <> "</span>",
         MapSet.union(tags, trailing_tags)}
      else
        {text, tags}
      end

    {text, MapSet.to_list(mentions), MapSet.to_list(tags), MapSet.to_list(urls)}
  end

  defp do_linkify(text, options) do
    acc = %{mentions: MapSet.new(), tags: MapSet.new(), urls: MapSet.new()}

    with_parse_timeout(
      fn ->
        if options[:safe_mention] && Regex.named_captures(safe_mention_regex(), text) do
          %{"mentions" => mentions, "rest" => rest} =
            Regex.named_captures(safe_mention_regex(), text)

          {text_mentions, %{mentions: mentions}} = Linkify.link_map(mentions, acc, options)
          {text_rest, %{tags: tags, urls: urls}} = Linkify.link_map(rest, acc, options)

          {text_mentions <> text_rest, %{mentions: mentions, tags: tags, urls: urls}}
        else
          Linkify.link_map(text, acc, options)
        end
      end,
      # if parsing has to be abandoned, leave the text as the user typed it
      {text, acc}
    )
  end

  # parsing user-provided text runs in a Task with a budget, so that input which makes
  # the parser misbehave can only lose us the mentions/hashtags/links for that text,
  # rather than tie up the process handling the request (see `Utils.apply_task/3`)
  defp with_parse_timeout(fun, fallback) do
    timeout = Config.get([:bonfire_tag, :linkify_timeout], 10_000)

    case Utils.apply_task(:await, fun, timeout: timeout) do
      {:ok, result} ->
        result

      # NOTE: already logged by `apply_task`
      _ ->
        fallback
    end
  end

  # NOTE: merged rather than concatenated so there's exactly one entry per key. With duplicates the winner depends on who reads them (`Keyword.get` takes the first, Linkify takes the last), which is a good way to have a flag mean two different things at once. Precedence: defaults < config < caller.
  defp linkify_opts(overrides \\ []) do
    [
      url_handler: &url_handler/3,
      hashtag: true,
      hashtag_handler: &tag_handler/4,
      mention: true,
      mention_handler: &tag_handler/4,
      mention_regex: match_mention(),
      email: false,
      strip_prefix: true,
      truncate: 30,
      rel: "nofollow noopener ugc"
    ]
    |> Keyword.merge(Config.get(Bonfire.Tag.TextContent.Formatter, []))
    |> Keyword.merge(overrides)
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
      # use the normalized (stored) name for the canonical link/storage,
      # but keep the original casing the user typed for display
      name = e(hashtag, :named, :name, nil) || tag
      acc = %{acc | tags: MapSet.put(acc.tags, {"##{name}", hashtag})}

      url = "/hashtag/#{name}"
      link = tag_link("#", url, tag, Map.get(opts, :content_type))
      {link, acc}
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

  defp tag_handler("@" = type, nickname, buffer, opts, acc) do
    if :ets.member(:mention_prefetch_inflight, nickname) do
      # warming timed out or errored — skip to avoid a second blocking fetch
      {buffer, acc}
    else
      do_tag_lookup(type, nickname, buffer, opts, acc)
    end
  end

  defp tag_handler(type, nickname, buffer, opts, acc) do
    do_tag_lookup(type, nickname, buffer, opts, acc)
  end

  defp do_tag_lookup(type, nickname, buffer, opts, acc) do
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
    ~s(<a class="hashtag" data-tag="#{tag}" href="#{url}" rel="tag ugc">##{tag}</a>)
  end

  defp tag_link(_type, url, display_name, _html) do
    ~s(<span class="h-card"><a data-user="#{display_name}" class="u-url mention" href="#{url}" rel="ugc">#{display_name}</a></span>)
  end

  defp render_link(display_url, %{href: href}, "text/markdown") do
    "[#{display_url}](#{href})"
  end

  defp render_link(display_url, attrs, _html) do
    Linkify.Builder.format_url(attrs, display_url)
  end

  # Regex pattern for trailing hashtag line defined as a function to comply with Erlang/OTP 28
  defp trailing_hashtags_regex, do: ~r/(?:\n|<br\s*\/?>)\s*((?:#[\w]+\s*)+)\s*$/u

  @doc "Collects all mention nicks from text using Linkify's parser — no DB or HTTP lookups."
  def collect_mentions(text) when is_binary(text) do
    # Drop all handlers: collect_mentions only needs to scan for mention text, not render HTML or hit the DB
    opts =
      linkify_opts(hashtag: false, url: false)
      |> Keyword.drop([:url_handler, :hashtag_handler, :mention_handler])

    with_parse_timeout(fn -> Linkify.collect_mentions(text, opts) end, [])
  end

  def collect_mentions(_), do: []

  @doc "Warms the actor cache for remote mentions in parallel. Skips locals and already in-flight fetches."
  def prefetch_mentions(text) when is_binary(text) do
    mentions =
      collect_mentions(text)
      |> Enum.filter(&String.contains?(&1, "@"))
      |> Enum.filter(&:ets.insert_new(:mention_prefetch_inflight, {&1, true}))

    if mentions != [] do
      debug(mentions, "prefetching remote mentions in parallel")

      Task.async_stream(
        mentions,
        fn mention ->
          result = Tag.maybe_lookup_tag(mention, "@")

          # only clear on success — failures stay as a negative cache so tag_handler skips the lookup
          if match?({:ok, _}, result), do: :ets.delete(:mention_prefetch_inflight, mention)
          result
        end,
        timeout: 5_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Stream.each(fn
        {:ok, {:ok, _}} -> :ok
        {:ok, {:error, reason}} -> warn(reason, "could not prefetch mention")
        {:exit, :timeout} -> warn("mention prefetch timed out")
        _ -> :ok
      end)
      |> Stream.run()
    end
  end

  def prefetch_mentions(_), do: :ok

  @doc "Extracts a trailing line of hashtags, returning `{cleaned_text, hashtag_line}`."
  def extract_trailing_hashtags(text) when is_binary(text) do
    case Regex.run(trailing_hashtags_regex(), text) do
      [full_match, hashtag_line] ->
        cleaned = String.trim_trailing(String.replace(text, full_match, ""))
        {cleaned, hashtag_line}

      _ ->
        {text, ""}
    end
  end

  def extract_trailing_hashtags(text), do: {text, ""}
end
