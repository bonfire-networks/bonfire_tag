# Based on code from Pleroma: A lightweight social networking server
# Copyright © 2017-2020 Pleroma Authors <https://pleroma.social/>
# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Tag.TextContent.Process do
  alias Bonfire.Common.Config

  alias Bonfire.Tag.TextContent.Formatter

  @doc """
  For use for things like a bio, where we want links but not to actually trigger mentions.
  """

  def process(
        user \\ nil,
        text,
        content_type \\ "text/plain"
      )

  def process(
        user,
        text,
        content_type
      )
      do
    options = [mentions_format: :full, user: user]
    content_type = get_content_type(content_type)

    text
    |> IO.inspect
    |> object_text_content()
    |> format_input(content_type, options)
    # |> maybe_add_attachments(attachments, attachment_links)
    # |> maybe_add_nsfw_tag(data)
    # |> elem(0)
  end


  defp get_content_type(content_type) do
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
      "text/plain"
    end
  end

  @doc """
  Formatting text to plain text, HTML, or markdown
  """
  def format_input(text, format \\ "text/plain", options \\ [])

  #doc """ Formatting text to plain text. """
  def format_input(text, "text/plain" = content_type, options) do
    text
    |> Formatter.html_escape(content_type)
    |> String.replace("&amp;", "&")
    |> Formatter.linkify(options)
    |> (fn {text, mentions, tags} ->
          {String.replace(text, ~r/\r?\n/, "<br>"), mentions, tags}
        end).()
  end

  #doc """ Formatting text to html. """
  def format_input(text, "text/html" = content_type, options) do
    text
    |> Formatter.html_escape(content_type)
    |> String.replace("&amp;", "&")
    |> Formatter.linkify(options)
  end

  #doc """ Formatting text to markdown. FIXME """
  def format_input(text, "text/markdown" = content_type, options) do
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

  def object_text_content(text) when is_binary(text) and bit_size(text) > 1, do: text
  def object_text_content(%{post_content: p}), do: object_text_content(p)
  def object_text_content(%{post: p}), do: object_text_content(p)
  def object_text_content(%{profile: p}), do: object_text_content(p)
  def object_text_content(%{html_body: text} = _thing)  when is_binary(text) and bit_size(text) > 1, do: text
  def object_text_content(%{summary: text} = _thing) when is_binary(text) and bit_size(text) > 1, do: text
  def object_text_content(%{note: text} = _thing) when is_binary(text) and bit_size(text) > 1, do: text
  def object_text_content(%{name: text} = _thing) when is_binary(text) and bit_size(text) > 1, do: text
  def object_text_content(_), do: ""

end
