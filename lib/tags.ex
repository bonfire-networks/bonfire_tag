# Bonfire.Common.Config.require_extension_config!(:bonfire_tag)
defmodule Bonfire.Tag.Tags do
  use Arrows
  use Bonfire.Common.Utils
  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Common.Types

  # warning: do not move after we alias Pointers
  alias Pointers.Pointer
  # warning: do not move before we alias Pointer
  alias Bonfire.Common.Pointers
  alias Bonfire.Me.Characters
  alias Bonfire.Tag.Queries
  alias Bonfire.Tag.TextContent.Process

  alias Bonfire.Tag.Tagged

  @doc """
  Retrieves a single tag by arbitrary filters.
  Used by:
  * GraphQL Item queries
  * ActivityPub integration
  * Various parts of the codebase that need to query for tags (inc. tests)
  """
  def one(filters, opts \\ []),
    do: repo().single(Queries.query(e(opts, :pointable, Pointer), filters))

  @doc """
  Retrieves a list of tags by arbitrary filters.
  Used by:
  * Various parts of the codebase that need to query for tags (inc. tests)
  """
  def many(filters \\ [], opts \\ []),
    do: {:ok, repo().many(Queries.query(e(opts, :pointable, Pointer), filters))}

  def get(id, opts \\ []) do
    if is_ulid?(id),
      do: one([id: id], opts),
      else: one([username: id], opts)

    # else: maybe_apply(Characters, :by_username, id) <~> one(username: id)
    # TODO: lookup Peered with canonical_uri if id is a URL
  end

  def find(id, types \\ nil) do
    if is_ulid?(id),
      do: one(id: id, type: types),
      # TODO: lookup Peered with canonical_uri if id is a URL
      else: many(autocomplete: id, type: types)
  end

  # 1 hour # TODO: configurable
  @default_cache_ttl 1_000 * 60 * 60

  def list_trending(in_last_x_days \\ 30, limit \\ 10) do
    Cache.maybe_apply_cached(&query_list_trending/2, [in_last_x_days, limit],
      ttl: @default_cache_ttl
    )

    # Cache.maybe_apply_cached({__MODULE__, :query_list_trending}, [in_last_x_days, limit], ttl: @default_cache_ttl)
  end

  def list_trending_reset(in_last_x_days \\ 30, limit \\ 10) do
    Cache.reset(&query_list_trending/2, [in_last_x_days, limit])
  end

  defp query_list_trending(in_last_x_days \\ 30, limit \\ 10) do
    # todo: configurable
    exclude = [Bonfire.Data.Identity.User.__pointers__(:table_id)]

    DateTime.now!("Etc/UTC")
    |> DateTime.add(-in_last_x_days * 24 * 60 * 60, :second)
    |> Queries.list_trending(exclude, limit)
    |> repo().all()
    |> Enum.map(fn tag -> struct(Tagged, tag) end)
    |> repo().maybe_preload(tag: [:profile, :character])
    |> repo().maybe_preload(:tag, skip_boundary_check: true)

    # |> debug
  end

  @doc """
  Try to find one (best-match) tag
  """
  def maybe_find_tag(current_user, id_or_username_or_url, types \\ nil)

  def maybe_find_tag(current_user, id_or_username_or_url, types)
      when is_binary(id_or_username_or_url) do
    debug(id_or_username_or_url)
    # check if tag already exists
    get(id_or_username_or_url)
    <~> if is_ulid?(id_or_username_or_url) do
      debug("try by ID")

      Pointers.one(id_or_username_or_url,
        current_user: current_user,
        skip_boundary_check: true
      )
    else
      # if Bonfire.Common.Extend.extension_enabled?(Bonfire.Federate.ActivityPub) do
      debug("try get_by_url_ap_id_or_username")

      with {:ok, federated_object_or_character} <-
             Bonfire.Federate.ActivityPub.AdapterUtils.get_by_url_ap_id_or_username(
               id_or_username_or_url
             ) do
        debug("federated_object_or_character: #{inspect(federated_object_or_character)}")

        {:ok, federated_object_or_character}
      else
        _ ->
          error("no such federated remote tag found")
          nil
      end
    end
  end

  def maybe_find_tag(_, _, _), do: nil

  @doc """
  Search / autocomplete for tags by name
  """
  def maybe_find_tags(current_user, id_or_username_or_url, types \\ nil)
      when is_binary(id_or_username_or_url) do
    debug(id_or_username_or_url)

    find(id_or_username_or_url, types)
    # if couldn't find, try lookup one
    <~> [maybe_find_tag(current_user, id_or_username_or_url, types)]
  end

  @doc """
  Lookup a single for a tag by its name/username
  """
  def maybe_lookup_tag(id_or_username_or_url, _prefix \\ "@")
      when is_binary(id_or_username_or_url),
      do: maybe_find_tag(nil, id_or_username_or_url)

  def maybe_taxonomy_tag(user, id) do
    if Bonfire.Common.Extend.extension_enabled?(Bonfire.TaxonomySeeder.TaxonomyTags) do
      Bonfire.TaxonomySeeder.TaxonomyTags.maybe_make_category(user, id)
    end
  end

  ### Functions for tagging things ###

  @doc """
  Maybe tag something
  """
  def maybe_tag(user, thing, tags \\ nil, boost_category_mentions? \\ true)

  def maybe_tag(user, thing, %{tags: tags}, boost_category_mentions?),
    do: maybe_tag(user, thing, tags, boost_category_mentions?)

  def maybe_tag(user, thing, %{tag: tag}, boost_category_mentions?),
    do: maybe_tag(user, thing, tag, boost_category_mentions?)

  def maybe_tag(user, thing, tags, boost_category_mentions?) when is_list(tags),
    do: tag_something(user, thing, tags, boost_category_mentions?)

  def maybe_tag(user, thing, %{__struct__: _} = tag, boost_category_mentions?),
    do: tag_something(user, thing, tag, boost_category_mentions?)

  def maybe_tag(user, thing, tag_string, boost_category_mentions?)
      when is_binary(tag_string) do
    String.split(tag_string, ",")
    |> tag_something(user, thing, ..., boost_category_mentions?)
  end

  # def maybe_tag(user, thing, text, boost_category_mentions?) when is_binary(text) do
  #   tags = if text != "", do: Bonfire.Tag.Autocomplete.find_all_tags(text) |> debug # TODO, switch to TextContent.Process?
  #   if is_map(tags) or (is_list(tags) and tags != []) do
  #     maybe_tag(user, thing, tags, boost_category_mentions?)
  #   else
  #     debug("Bonfire.Tag - no matches in '#{text}'")
  #     {:ok, thing}
  #   end
  # end
  # otherwise maybe we have tagnames inline in the text assocs of the object?
  def maybe_tag(user, obj, _, boost_category_mentions?),
    do:
      maybe_tag(
        user,
        obj,
        Process.object_text_content(obj),
        boost_category_mentions?
      )

  # def maybe_tag(_user, thing, _maybe_tags, boost_category_mentions?) do
  #   #debug(maybe_tags: maybe_tags)
  #   {:ok, thing}
  # end

  @doc """
  tag existing thing with one or multiple Tags, Pointers, or anything that can be made into a tag
  """
  # def tag_something(user, thing, tags) when is_struct(thing) do
  #   with {:ok, tagged} <- do_tag_thing(user, thing, tags) do
  #     {:ok, Map.put(thing, :tags, Map.get(tagged, :tags, []))}
  #   end
  # end
  def tag_something(user, thing, tags, boost_category_mentions? \\ true) do
    with {:ok, thing} <- do_tag_thing(user, thing, tags) do
      if boost_category_mentions? &&
           module_enabled?(Bonfire.Social.Tags, user) do
        debug("Bonfire.Tag: try to boost mentions to the category's feed, as permitted")

        Bonfire.Social.Tags.maybe_auto_boost(
          user,
          e(thing, :tags, nil) || tags,
          thing
        )
      end

      {:ok, thing}
    end
  end

  # doc """ Add tag(s) to a pointable thing. Will replace any existing tags. """
  defp do_tag_thing(user, thing, tags) when is_list(tags) do
    pointer =
      thing
      # |> debug("thing")
      |> thing_to_pointer()
      |> debug("thing pointer")

    if pointer do
      tags =
        Enum.map(tags, &tag_preprocess(user, &1))
        |> debug("tags")
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(& &1.id)

      # |> debug("tags")
      with {:ok, tagged} <- thing_tags_save(pointer, tags) |> debug("saved") do
        {:ok, if(is_map(thing), do: thing, else: pointer) |> Map.merge(%{tags: tags})}
      end

      # Bonfire.Common.Repo.maybe_preload(thing, :tags)
    end
  end

  defp do_tag_thing(user, thing, tag), do: do_tag_thing(user, thing, [tag])

  # doc """ Prepare a tag to be used, by loading it from DB if necessary """
  defp tag_preprocess(_user, %{__struct__: _} = tag),
    do: thing_to_pointer(tag)

  defp tag_preprocess(_, tag) when is_nil(tag) or tag == "", do: nil

  defp tag_preprocess(_user, {:error, e}) do
    warn("Tags: invalid tag: #{inspect(e)}")
    nil
  end

  defp tag_preprocess(user, {_at_mention, tag}), do: tag_preprocess(user, tag)
  defp tag_preprocess(user, "@" <> tag), do: tag_preprocess(user, tag)
  defp tag_preprocess(user, "+" <> tag), do: tag_preprocess(user, tag)
  defp tag_preprocess(user, "&" <> tag), do: tag_preprocess(user, tag)

  defp tag_preprocess(_user, tag) when is_binary(tag),
    do: get(tag) |> ok_unwrap(nil) |> thing_to_pointer()

  defp tag_preprocess(_user, tag) do
    error("Tags.tag_preprocess: didn't recognise this as a tag: #{inspect(tag)} ")

    nil
  end

  def tag_ids(tags) when is_list(tags), do: Enum.map(tags, &tag_ids(&1))
  def tag_ids({_at_mention, %{id: tag_id}}), do: tag_id
  def tag_ids(%{id: tag_id}), do: tag_id

  defp thing_tags_save(%{} = thing, tags)
       when is_list(tags) and length(tags) > 0 do
    tags
    # |> debug("tags")
    |> Bonfire.Tag.thing_tags_changeset(thing, ...)
    # |> debug("changeset")
    |> repo().transact_with(fn -> repo().update(..., on_conflict: :nothing) end)
  end

  defp thing_tags_save(thing, _tags), do: {:ok, thing}

  defp thing_to_pointer({:ok, thing}), do: thing_to_pointer(thing)
  defp thing_to_pointer(%{} = thing), do: Pointers.maybe_forge(thing)

  defp thing_to_pointer(pointer_id) when is_binary(pointer_id),
    do:
      Pointers.one(id: pointer_id, skip_boundary_check: true)
      |> thing_to_pointer()

  defp thing_to_pointer(other) do
    warn(other, "dunno how to get a pointer from")
  end

  def indexing_object_format(object) do
    # debug(indexing_object_format: object)
    %{
      "id" => object.id,
      "name" => object.profile.name,
      "summary" => object.profile.summary

      # TODO: add url/username
    }
  end

  def indexing_object_format_name(object), do: object.profile.name
end
