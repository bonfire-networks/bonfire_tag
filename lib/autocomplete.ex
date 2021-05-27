defmodule Bonfire.Tag.Autocomplete do
  import Bonfire.Common.Utils
  alias Bonfire.Tag.Tags

  # TODO: put in config
  @tag_terminator " "
  @tags_seperator " "
  @prefixes ["@", "&", "+"]
  @taxonomy_prefix "+"
  @taxonomy_index "public"
  @search_index "public"
  @max_length 50

  def tag_lookup(tag_search, "+" = prefix, consumer) do
    # FIXME based on index_types we use
    tag_lookup_public(tag_search, prefix, consumer, ["Collection", "Category", "Tag"])
  end

  def tag_lookup(tag_search, "@" = prefix, consumer) do
    tag_lookup_public(tag_search, prefix, consumer, "User")
  end

  def tag_lookup(tag_search, "&" = prefix, consumer) do
    tag_lookup_public(tag_search, prefix, consumer, "Community")
  end

  def tag_lookup_public(tag_search, prefix, consumer, index_type) do
    hits = maybe_search(tag_search, %{"index_type" => index_type})
    if hits do
      #IO.inspect(search)
      tag_lookup_process(tag_search, hits, prefix, consumer)
    else
      with {:ok, tag} <- Tags.maybe_find_tag(tag_search) do
        tag
      end
    end
  end

  def search_or_lookup(tag_search, index, facets \\ nil) do
    #IO.inspect(searched: tag_search)
    #IO.inspect(facets: facets)

    hits = maybe_search(tag_search, %{index: index}, facets)
    if hits do # use search index if available
      hits
    else
      with {:ok, tag} <- Tags.maybe_find_tag(tag_search) do
        tag
      end
    end
  end

  def maybe_search(tag_search, opts \\ nil, facets \\ nil) do
    #IO.inspect(searched: tag_search)
    #IO.inspect(facets: facets)

    if module_enabled?(Bonfire.Search) do # use search index if available
      search = Bonfire.Search.search(tag_search, opts, false, facets)
      # IO.inspect(searched: search)

      if(is_map(search) and Map.has_key?(search, "hits") and length(search["hits"])) do
        # search["hits"]
        Enum.map(search["hits"], &tag_hit_prepare(&1, tag_search))
        |> Enum.filter(& &1)
      end
    end
  end

  def tag_lookup_process(tag_search, hits, prefix, consumer) do
    #IO.inspect(search["hits"])
    hits
    |> Enum.map(&tag_hit_prepare(&1, tag_search, prefix, consumer))
    |> Enum.filter(& &1)
  end

  def tag_hit_prepare(hit, _tag_search, prefix, consumer) do
    #IO.inspect(consumer)
    #IO.inspect(Map.new(consumer: "test"))

    # FIXME: do this by filtering Meili instead?
    if strlen(hit["username"]) > 0 or (prefix == "+" and strlen(hit["id"]) > 0) do
      hit
      |> Map.merge(%{
        "name" => e(hit, "name_crumbs", e(hit, "name", e(hit, "username", nil)))
      })
      |> Map.merge(%{
        "link" => e(hit, "canonical_url", "#unknown-hit-url")
      })
      |> tag_add_field(consumer, prefix, e(hit, "username", e(hit, "id", "")))
      |> Map.drop(["name_crumbs"])
    end
  end

  def tag_add_field(hit, "tag_as", _prefix, as) do
    Map.merge(hit, %{tag_as: as})
  end

  def tag_add_field(hit, "ck5", prefix, as) do
    if String.at(as, 0) == prefix do
      Map.merge(hit, %{"id" => to_string(as)})
    else
      Map.merge(hit, %{"id" => prefix <> to_string(as)})
    end
  end

  # def tag_suggestion_display(hit, tag_search) do
  #   name = e(hit, "name_crumbs", e(hit, "name", e(hit, "username", nil)))

  #   if !is_nil(name) and name =~ tag_search do
  #     split = String.split(name, tag_search, parts: 2, trim: false)
  #     IO.inspect(split)
  #     [head | tail] = split

  #     List.to_string([head, "<span>", tag_search, "</span>", tail])
  #   else
  #     name
  #   end
  # end

  def find_all_tags(content) do
    #IO.inspect(prefixes: @prefixes)
    # FIXME?
    words = tags_split(content)
    #IO.inspect(tags_split: words)

    if words do
      # tries =
      @prefixes
      |> Enum.map(&try_tag_search(&1, words))
      # |> IO.inspect
      |> Enum.map(&filter_results(&1))
      |> List.flatten()
      |> Enum.filter(& &1)
      # |> IO.inspect

      #IO.inspect(find_all_tags: tries)

    end
  end

  def filter_results(res) when is_list(res) do
    res
    |> Enum.map(&filter_results(&1))
  end
  def filter_results(%{tag_results: tag_results}) when (is_list(tag_results) and length(tag_results)>0) do
    tag_results
  end
  def filter_results(%{tag_results: tag_results}) when is_map(tag_results) do
    [tag_results]
  end
  def filter_results(_) do
    nil
  end

  ## moved from tag_autocomplete_live.ex ##

  def try_prefixes(content) do
    #IO.inspect(prefixes: @prefixes)
    # FIXME?
    tries = Enum.map(@prefixes, &try_tag_search(&1, content))
      |> Enum.filter(& &1)
    #IO.inspect(try_prefixes: tries)

    List.first(tries)
  end

  def try_tag_search(tag_prefix, words) when is_list(words) do
    Enum.map(words, &try_tag_search(tag_prefix, &1))
  end

  def try_tag_search(tag_prefix, content) do
    tag_search = tag_search_from_text(content, tag_prefix)

    if strlen(tag_search) > 0 do
      tag_search(tag_search, tag_prefix)
    end
  end

  def try_tag_search(content) do
    tag_search = tag_search_from_tags(content)

    if strlen(tag_search) > 0 do
      tag_search(tag_search, @taxonomy_prefix)
    end
  end

  def tag_search(tag_search, tag_prefix) do
    tag_results = search_prefix(tag_search, tag_prefix)

    #IO.inspect(tag_prefix: tag_prefix)
    #IO.inspect(tag_results: tag_results)

    if tag_results do
      %{tag_search: tag_search, tag_results: tag_results, tag_prefix: tag_prefix}
    end
  end

  def tag_search_from_text(text, prefix) do
    parts = String.split(text, prefix, parts: 2)

    if length(parts) > 1 do
      #IO.inspect(parts: parts)
      typed = List.last(parts)

      if String.length(typed) > 0 and String.length(typed) < @max_length and !(typed =~ @tag_terminator) do
        typed
      end
    end
  end

  def tags_split(text) do
    parts = String.split(text, @tags_seperator)

    if length(parts) > 0 do
      parts
    end
  end

  def tag_search_from_tags(text) do
    parts = tags_split(text)

    if length(parts) > 0 do
      typed = List.last(parts)

      if String.length(typed) do
        typed
      end
    end
  end

  def search_prefix(tag_search, "+") do
    # search_or_lookup(tag_search, @taxonomy_index, %{"index_type" => ["Category", "Collection"]})
    search_or_lookup(tag_search, @taxonomy_index, %{"index_type" => "Category"})
  end

  def search_prefix(tag_search, "@") do
    search_or_lookup(tag_search, @taxonomy_index, %{"index_type" => "User"})
  end

  def search_prefix(tag_search, "&") do
    search_or_lookup(tag_search, @taxonomy_index, %{"index_type" => "Community"})
  end

  def search_prefix(tag_search, _) do
    search_or_lookup(tag_search, @search_index, %{
      "index_type" => ["User", "Community", "Category", "Collection"]
    })
  end

  def tag_hit_prepare(hit, tag_search) do
    # FIXME: do this by filtering Meili instead?
    if !is_nil(hit["username"]) or !is_nil(hit["id"]) do
      hit
      |> Map.merge(%{display: tag_suggestion_display(hit, tag_search)})
      |> Map.merge(%{tag_as: e(hit, "username", e(hit, "id", ""))})
    end
  end

  def tag_suggestion_display(hit, tag_search) do
    name = e(hit, "name_crumbs", e(hit, "name", e(hit, "username", nil)))

    if !is_nil(name) and name =~ tag_search do
      split = String.split(name, tag_search, parts: 2, trim: false)
      #IO.inspect(split)
      [head | tail] = split

      List.to_string([head, "<span>", tag_search, "</span>", tail])
    else
      name
    end
  end
end
