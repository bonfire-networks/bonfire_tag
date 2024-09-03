defmodule Bonfire.Tag.Autocomplete do
  @moduledoc "Functions to lookup and autocomplete tag names"

  use Bonfire.Common.Utils
  # alias Bonfire.Common.URIs
  alias Bonfire.Tag
  import Untangle
  alias Enums
  import Bonfire.Common.Config, only: [repo: 0]

  # TODO: put in config
  @tag_terminator " "
  @tags_seperator " "
  @prefixes ["@", "&", "+"]
  @taxonomy_prefix "+"
  @search_index "public"
  @max_length 50

  def prefix_index("+" = _prefix) do
    [Bonfire.Classify.Category, Bonfire.Tag]
  end

  def prefix_index("@" = _prefix) do
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
    tag_lookup_public(tag_search, index_type, prefix, consumer)
  end

  def tag_lookup_public(tag_search, index_type, prefix \\ nil, consumer \\ nil) do
    maybe_search(tag_search, index_type, prefix, consumer) ||
      maybe_find_tags(tag_search, index_type)
      |> repo().maybe_preload(profile: [:icon])
      |> Enum.map(&tag_hit_prepare(&1, tag_search, prefix, consumer))
      |> Enums.filter_empty([])
  end

  def maybe_find_tags(tag_search, index_type) do
    with {:ok, tags} <- Tag.maybe_find_tags(nil, tag_search, index_type) do
      tags
    end
  end

  def search_or_lookup(tag_search, index, facets \\ nil)

  # dirty workaround
  def search_or_lookup("lt", _, _), do: nil

  def search_or_lookup(tag_search, _index, facets) do
    # debug("Search.search_or_lookup: #{tag_search} with facets #{inspect facets}")

    hits = maybe_search(tag_search, facets)
    # uses search index if available
    if hits do
      hits
    else
      maybe_find_tags(tag_search, facets)
    end
  end

  def maybe_search(tag_search, facets \\ nil, prefix \\ nil, consumer \\ nil) do
    # debug(searched: tag_search)
    # debug(facets: facets)

    # use search index if available
    if module_enabled?(Bonfire.Search) do
      debug(
        "Bonfire.Tag.Autocomplete: searching #{inspect(tag_search)} with facets #{inspect(facets)}"
      )

      # search = Bonfire.Search.search(tag_search, opts, false, facets) |> e("hits")
      # TODO: pass current_user in opts for boundaries
      search =
        Bonfire.Common.Utils.maybe_apply(Bonfire.Search, :search_by_type, [tag_search, facets])
        |> debug()

      if(is_list(search) and length(search) > 0) do
        # search["hits"]
        Enum.map(search, &tag_hit_prepare(&1, tag_search, prefix, consumer))
        |> Enums.filter_empty([])
        |> input_to_atoms()

        # |> debug("maybe_search results")
      end
    end
  end

  # def tag_hit_prepare(hit, tag_search) do
  #   debug(hit)
  #   # FIXME: exclude empties by filtering Meili instead?
  #   case e(hit, "username", nil) || e(hit, "id", "") || e(hit, :character, :username, nil) do
  #     nil -> nil
  #     username ->
  #     hit
  #     |> Map.merge(%{display: tag_suggestion_display(hit, tag_search, username)})
  #     |> Map.merge(%{icon: Media.avatar_url(hit) || e(hit, "icon", nil)})
  #     |> Map.merge(%{tag_as: username})
  #   end
  # end

  # def tag_suggestion_display(hit, tag_search, username \\ nil) do
  #   name = e(hit, "name_crumbs", nil) || e(hit, "name", nil) || username || e(hit, "username", nil)

  #   if not is_nil(name) and name =~ tag_search do
  #     split = String.split(name, tag_search, parts: 2, trim: false)
  #     # debug(split)
  #     [head | tail] = split

  #     List.to_string([head, "<span>", tag_search, "</span>", tail])
  #   else
  #     name
  #   end
  # end

  def tag_hit_prepare(hit, _tag_search, prefix, consumer) do
    debug(hit)

    username = e(hit, "username", nil) || e(hit, :character, :username, nil) || e(hit, "id", nil)

    # FIXME: do this by filtering Meili instead?
    if not is_nil(username) and username != "" do
      # "link" => e(hit, "canonical_url", URIs.canonical_url(object))
      tag_add_field(
        %{
          name:
            e(
              hit,
              "name_crumbs",
              nil
            ) || e(hit, :profile, :name, nil) || e(hit, "name", nil) || username,
          icon: Media.avatar_url(hit) || e(hit, "icon", nil)
        },
        consumer,
        prefix,
        username
      )
    end
  end

  def tag_add_field(hit, "tag_as", _prefix, username) do
    Map.merge(hit, %{tag_as: username})
  end

  def tag_add_field(hit, consumer, prefix, username)
      when consumer in ["ck5", "quill"] do
    if String.at(username, 0) == prefix do
      Map.merge(hit, %{id: username})
    else
      Map.merge(hit, %{id: "#{prefix}#{username}"})
    end
  end

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
      |> Enums.filter_empty([])

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
    if is_uid?(content) do
      [Tag.maybe_find_tag(nil, content)]
    else
      # FIXME! optimise this
      Enum.map(@prefixes, &try_tag_search(&1, content))
      |> Enums.filter_empty([])
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

    if Text.strlen(tag_search) > 0 do
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
end
