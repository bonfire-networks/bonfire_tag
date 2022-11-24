defmodule Bonfire.Tag.Web.Component.TagAutocomplete do
  use Bonfire.UI.Common.Web, :live_component

  import Bonfire.Tag.Autocomplete

  # TODO: put in config
  @tags_seperator " "

  def mount(socket) do
    {:ok,
     assign(
       socket,
       meili_host: System.get_env("SEARCH_MEILI_INSTANCE", "http://localhost:7700"),
       tag_search: nil,
       tag_results: []
     )}
  end

  # # need to alias some form posting events here to workaround having two events but one target on a form
  # def do_handle_event("publish_ad", data, socket) do
  #   ValueFlows.Web.My.PublishAdLive.publish_ad(data, socket)
  # end

  # # need to alias some form posting events here to workaround having two events but one target on a form
  # def do_handle_event("form_changes" = event, data, socket) do
  #   Bonfire.Web.My.ShareLinkLive.handle_event(event, data, socket)
  # end

  # def do_handle_event("share_link" = event, data, socket) do
  #   Bonfire.Web.My.ShareLinkLive.handle_event(event, data, socket)
  # end

  def do_handle_event("tag_suggest", data, socket) do
    tag_suggest(data, socket)
  end

  def tag_suggest(%{"tags" => tags}, socket) when byte_size(tags) >= 1 do
    debug(tag_suggest_tags: tags)

    found = try_tag_search(tags)

    # debug(found: found)

    if(
      is_map(found) and Map.has_key?(found, :tag_results) and
        length(found.tag_results) > 0
    ) do
      {:noreply,
       assign(socket,
         tag_search: found.tag_search,
         tag_prefix: @tags_seperator,
         tag_results: found.tag_results
       )}
    else
      {:noreply, socket}
    end
  end

  def tag_suggest(%{"content" => content}, socket)
      when byte_size(content) >= 1 do
    debug(tag_suggest_content: content)

    found = try_prefixes(content)

    if(found) do
      {:noreply,
       assign(socket,
         tag_search: found.tag_search,
         tag_prefix: found.tag_prefix,
         tag_results: found.tag_results
       )}
    else
      {:noreply, socket}
    end
  end

  def tag_suggest(data, socket) do
    debug(ignore_tag_suggest: data)

    {:noreply,
     assign(socket,
       tag_search: "",
       tag_results: []
     )}
  end
end
