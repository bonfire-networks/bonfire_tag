# Based on code from Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# Copyright © 2021 Bonfire contributors <https://bonfirenetworks.org/>
# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Tag.TextContent.Process do
  import Untangle
  alias Bonfire.Common.Config
  alias Bonfire.Tag.TextContent.Formatter

  @default_content_type "text/markdown"
  @link_regex ~r"((?:http(s)?:\/\/)?[\w.-]+(?:\.[\w\.-]+)+[\w\-\._~%:/?#[\]@!\$&'\(\)\*\+,;=.]+)|[0-9a-z+\-\.]+:[0-9a-z$-_.+!*'(),]+"ui

  @doc """
  For use for things like a bio, where we want links but not to actually trigger mentions.
  """
  # TODO: batch lookups
  def process(
        user \\ nil,
        text,
        content_type \\ nil
      )

  def process(
        user,
        text,
        content_type
      )
      when is_binary(text) do
    # Config.get(:env) == :prod
    validate_domains =
      System.get_env("SKIP_LINK_DOMAINS_VALIDATION") not in ["1", "true"] and
        System.get_env("TEST_INSTANCE") != "yes"

    options = [
      mentions_format: :full,
      user: user,
      validate_hostname: validate_domains,
      validate_tld: validate_domains
    ]

    content_type =
      content_type(content_type)
      |> info("content_type")

    format_input(text, content_type, options)
    |> debug("ran through Linkify")

    # |> maybe_add_attachments(attachments, attachment_links)
    # |> maybe_add_nsfw_tag(data)
    # |> elem(0)
  end

  defp content_type(:markdown), do: content_type("text/markdown")
  defp content_type(:html), do: content_type("text/html")
  defp content_type(:plain), do: content_type("text/plain")

  defp content_type(content_type) do
    if Enum.member?(
         Config.get([:instance, :allowed_post_formats], [
           "text/plain",
           "text/markdown",
           "text/html"
         ]),
         content_type
       ) do
      content_type
    else
      @default_content_type
    end
  end

  @doc """
  Formatting text to plain text, HTML, or markdown
  """
  defp format_input(text, format \\ "text/plain", options \\ [])

  # doc """ Formatting text to plain text. """
  defp format_input(text, "text/plain" = content_type, options) do
    text
    |> html_escape(content_type)
    |> String.replace("&amp;", "&")
    |> String.replace(~r/\r?\n/, "<br>")
    |> Formatter.linkify(options ++ [content_type: content_type])
  end

  # doc """ Formatting text to html. """
  defp format_input(text, "text/html" = content_type, options) do
    text
    |> html_escape(content_type)
    |> String.replace("&amp;", "&")
    |> Formatter.linkify(options ++ [content_type: content_type])
  end

  # doc """ Formatting text to markdown. FIXME """
  defp format_input(text, "text/markdown" = content_type, options) do
    text
    # |> Formatter.mentions_escape(options)
    # |> Earmark.as_html()
    # |> elem(1)
    |> String.replace("&amp;", "&")
    |> Formatter.linkify(options ++ [content_type: content_type])
  end

  # defp maybe_add_nsfw_tag({text, mentions, tags}, %{"sensitive" => sensitive})
  #      when sensitive in [true, "True", "true", "1"] do
  #   {text, mentions, [{"#nsfw", "nsfw"} | tags]}
  # end
  # defp maybe_add_nsfw_tag(data, _), do: data

  def html_escape({text, mentions, hashtags}, type) do
    {html_escape(text, type), mentions, hashtags}
  end

  # def html_escape(text, "text/html") do
  #   if Bonfire.Common.Extend.module_enabled?(Scrubber), do: Scrubber.filter_tags(text),
  #   else: text
  # end

  def html_escape(text, "text/plain") do
    Regex.split(@link_regex, text, include_captures: true)
    |> Enum.map_every(2, fn chunk ->
      {:safe, part} = Phoenix.HTML.html_escape(chunk)
      part
    end)
    |> Enum.join("")
  end

  def html_escape(text, _) do
    text
  end
end
