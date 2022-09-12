defmodule Bonfire.Tag.Autocomplete do
  use Bonfire.Common.Utils
  alias Bonfire.Common.URIs
  alias Bonfire.Tag.Tags
  import Untangle

  # TODO: put in config
  @tag_terminator " "
  @tags_seperator " "
  @prefixes ["@", "&", "+"]
  @taxonomy_prefix "+"
  @search_index "public"
  @max_length 50

  def prefix_index("+" = prefix) do
    [Bonfire.Classify.Category, Bonfire.Tag]
  end

  def prefix_index("@" = prefix) do
    Bonfire.Data.Identity.User
  end

  # def prefix_index(tag_search, "&" = prefix, consumer) do
  #   "Community"
  # end

  def prefix_index(_) do
    [Bonfire.Data.Identity.User, Bonfire.Classify.Category, Bonfire.Tag]
  end

  # FIXME combine the following functions

  def api_tag_lookup(tag_search, prefix, consumer) do
    api_tag_lookup_public(tag_search, prefix, consumer, prefix_index(prefix))
  end

  def search_prefix(tag_search, prefix) do
    search_or_lookup(tag_search, @search_index, prefix_index(prefix))
  end

  def search_type(tag_search, type) do
    search_or_lookup(tag_search, @search_index, type)
  end

  def api_tag_lookup_public(tag_search, prefix, consumer, index_type) do
    tag_lookup_public(tag_search, index_type)
    |> tag_lookup_process(tag_search, ..., prefix, consumer)
  end

  def tag_lookup_public(tag_search, index_type) do
    maybe_search(tag_search, index_type) ||
      maybe_find_tags(tag_search, index_type)
  end

  def maybe_find_tags(tag_search, index_type) do
    with {:ok, tags} <- Tags.maybe_find_tags(nil, tag_search, index_type) do
      tags
    end
  end

  def search_or_lookup(tag_search, index, facets \\ nil)

  # dirty workaround
  def search_or_lookup("lt", _, _), do: nil

  def search_or_lookup(tag_search, index, facets) do
    # debug("Search.search_or_lookup: #{tag_search} with facets #{inspect facets}")

    hits = maybe_search(tag_search, facets)
    # uses search index if available
    if hits do
      hits
    else
      maybe_find_tags(tag_search, facets)
    end
  end

  def maybe_search(tag_search, facets \\ nil) do
    # debug(searched: tag_search)
    # debug(facets: facets)

    # use search index if available
    if module_enabled?(Bonfire.Search) do
      debug(
        "Bonfire.Tag.Autocomplete: searching #{inspect(tag_search)} with facets #{inspect(facets)}"
      )

      # search = Bonfire.Search.search(tag_search, opts, false, facets) |> e("hits")
      search =
        Bonfire.Search.search_by_type(tag_search, facets)
        |> debug()

      if(is_list(search) and length(search) > 0) do
        # search["hits"]
        Enum.map(search, &tag_hit_prepare(&1, tag_search))
        |> Utils.filter_empty([])
        |> input_to_atoms()

        # |> debug("maybe_search results")
      end
    end
  end

  def tag_lookup_process(tag_search, hits, prefix, consumer) do
    # debug(search["hits"])
    hits
    |> Enum.map(&tag_hit_prepare(&1, tag_search, prefix, consumer))
    |> Utils.filter_empty([])
  end

  def tag_hit_prepare(hit, tag_search) do
    # FIXME: do this by filtering Meili instead?
    if !is_nil(hit["username"]) or !is_nil(hit["id"]) do
      hit
      |> Map.merge(%{display: tag_suggestion_display(hit, tag_search)})
      |> Map.merge(%{tag_as: e(hit, "username", e(hit, "id", ""))})
    end
  end

  def tag_hit_prepare(object, _tag_search, prefix, consumer) do
    # debug(hit)

    hit =
      stringify_keys(object)
      |> debug()

    username = hit["username"] || hit["character"]["username"]

    # FIXME: do this by filtering Meili instead?
    if strlen(username) do
      # "link" => e(hit, "canonical_url", URIs.canonical_url(object))
      tag_add_field(
        %{
          "name" =>
            e(
              hit,
              "name_crumbs",
              e(hit, "profile", "name", e(hit, "name", e(hit, "username", nil)))
            )
        },
        consumer,
        prefix,
        username || e(hit, "id", "")
      )
    end
  end

  def tag_add_field(hit, "tag_as", _prefix, as) do
    Map.merge(hit, %{tag_as: as})
  end

  def tag_add_field(hit, consumer, prefix, as)
      when consumer in ["ck5", "quill"] do
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
  #     debug(split)
  #     [head | tail] = split

  #     List.to_string([head, "<span>", tag_search, "</span>", tail])
  #   else
  #     name
  #   end
  # end

  def find_all_tags(content) do
    # debug(prefixes: @prefixes)

    # FIXME?
    words =
      content
      |> HtmlEntities.decode()
      |> tags_split()
      |> debug("words")

    if words do
      # tries =
      words
      |> try_all_prefixes()
      # |> debug
      |> Enum.map(&filter_results(&1))
      |> List.flatten()
      |> Utils.filter_empty([])

      # |> IO.inspect

      # debug(find_all_tags: tries)
    end
  end

  def filter_results(res) when is_list(res) do
    Enum.map(res, &filter_results(&1))
  end

  def filter_results(%{tag_results: tag_results})
      when is_list(tag_results) and length(tag_results) > 0 do
    tag_results
  end

  def filter_results(%{tag_results: tag_results}) when is_map(tag_results) do
    [tag_results]
  end

  def filter_results(_) do
    []
  end

  def try_all_prefixes(content) do
    if is_ulid?(content) do
      [Tags.maybe_find_tag(nil, content)]
    else
      # FIXME! optimise this
      Enum.map(@prefixes, &try_tag_search(&1, content))
      |> Utils.filter_empty([])
    end
  end

  def try_prefixes(content) do
    try_all_prefixes(content)
    |> List.first()
  end

  def try_tag_search(tag_prefix, words) when is_list(words) do
    Enum.map(words, &try_tag_search(tag_prefix, &1))
  end

  def try_tag_search(tag_prefix, content) do
    case tag_search_from_text(content, tag_prefix) do
      search when is_binary(search) and byte_size(search) > 0 ->
        tag_search(search, tag_prefix)

      _ ->
        nil
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

    # debug(tag_prefix: tag_prefix)
    # debug(tag_results: tag_results)

    if tag_results do
      %{
        tag_search: tag_search,
        tag_results: tag_results,
        tag_prefix: tag_prefix
      }
    end
  end

  def tag_search_from_text(text, prefix) do
    parts = String.split(text, prefix, parts: 2)

    if length(parts) > 1 do
      # debug(tag_search_from_text: parts)
      typed = List.last(parts)

      if String.length(typed) > 0 and String.length(typed) < @max_length and
           !(typed =~ @tag_terminator) do
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

  def tag_suggestion_display(hit, tag_search) do
    name = e(hit, "name_crumbs", e(hit, "name", e(hit, "username", nil)))

    if !is_nil(name) and name =~ tag_search do
      split = String.split(name, tag_search, parts: 2, trim: false)
      # debug(split)
      [head | tail] = split

      List.to_string([head, "<span>", tag_search, "</span>", tail])
    else
      name
    end
  end
end
