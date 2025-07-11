# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Tag do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  use Arrows
  import Untangle
  use Bonfire.Common.Utils
  use Bonfire.Common.Repo
  # alias Bonfire.Common.Types

  # warning: do not move after we alias Needle
  alias Needle.Pointer
  # warning: do not move before we alias Pointer
  alias Bonfire.Common.Needles
  # alias Bonfire.Me.Characters
  alias Bonfire.Tag.Queries

  alias Bonfire.Tag.Tagged
  alias Bonfire.Tag.Hashtag

  # import Bonfire.Common.Config, only: [repo: 0]
  # alias Ecto.Changeset
  # alias Needle.Changesets

  @behaviour Bonfire.Common.SchemaModule
  def context_module, do: Bonfire.Tag
  def query_module, do: Bonfire.Tag.Queries

  @doc """
  Retrieves a single tag by arbitrary filters.
  Used by:
  * GraphQL Item queries
  * ActivityPub integration
  * Various parts of the codebase that need to query for tags (inc. tests)
  """
  def one(filters, opts \\ []),
    do: repo().single(Queries.query(e(opts, :pointable, Pointer), filters))

  def get(id, opts \\ []) do
    if is_uid?(id),
      do: one([id: id], opts),
      else: one([username: id], opts)

    # else: maybe_apply(Characters, :by_username, id) <~> one(username: id)
    # TODO: lookup Peered with canonical_uri if id is a URL
  end

  def get_hashtag(name) do
    Hashtag.normalize_name(name)
    |> do_get_hashtag()
  end

  def find(id, types \\ nil) do
    if is_uid?(id),
      do: one(id: id, type: types),
      # TODO: lookup Peered with canonical_uri if id is a URL
      else: many(autocomplete: id, type: types)
  end

  @doc """
  Retrieves a list of tags by arbitrary filters.
  Used by:
  * Various parts of the codebase that need to query for tags (inc. tests)
  """
  def many(filters \\ [], opts \\ []),
    do: {:ok, repo().many(Queries.query(e(opts, :pointable, Pointer), filters))}

  defp do_get_hashtag(name) do
    repo().single(
      Hashtag
      |> proload(:named)
      |> where([named: named], named.name == ^name)
    )
  end

  def search_hashtag(text, opts \\ [])

  def search_hashtag(text, opts) do
    repo().many(search_hashtag_query(text, opts))
  end

  def search_hashtag_query(text, opts) do
    text = Hashtag.normalize_name(text)

    (opts[:query] || Hashtag)
    |> proload([:named])
    |> or_where(
      [named: n],
      ilike(n.name, ^"#{text}%") or ilike(n.name, ^"_#{text}%")
    )
    |> prepend_order_by([named: n], [
      {:desc, fragment("? % ?", ^text, n.name)}
    ])
  end

  def get_or_create_hashtag(name) do
    name = Hashtag.normalize_name(name)

    case do_get_hashtag(name) do
      {:ok, hashtag} ->
        {:ok, hashtag}

      {:error, :not_found} ->
        Hashtag.changeset(%{named: %{name: name}})
        |> repo().insert(
          # on_conflict: [set: [name: Needle.Changesets.get_field(changeset, :name)]],
          # conflict_target: :name,
          returning: true
        )
    end
  end

  # 1 hour # NOTE: these are just defaults but the UI checks for overrides in settings
  @default_cache_ttl 1_000 * 60 * 60
  @default_in_last_x_days 30
  @default_limit 10

  def list_trending(in_last_x_days \\ @default_in_last_x_days, limit \\ @default_limit) do
    Cache.maybe_apply_cached(
      &list_trending_without_cache/2,
      [in_last_x_days || @default_in_last_x_days, limit || @default_limit],
      expire: @default_cache_ttl
    )

    # Cache.maybe_apply_cached({__MODULE__, :list_trending_without_cache}, [in_last_x_days, limit], expire: @default_cache_ttl)
  end

  def list_trending_reset(in_last_x_days \\ @default_in_last_x_days, limit \\ @default_limit) do
    Cache.reset(&list_trending_without_cache/2, [
      in_last_x_days || @default_in_last_x_days,
      limit || @default_limit
    ])
  end

  def list_trending_without_cache(
        in_last_x_days \\ @default_in_last_x_days,
        limit \\ @default_limit
      ) do
    only_table_types =
      Bonfire.Common.Config.get(
        [Bonfire.Tag, :trending, :only_table_types],
        [Bonfire.Tag.Hashtag],
        name: l("Trending Tags"),
        description: l("Set object types to include.")
      )

    exclude_object_types =
      Bonfire.Common.Config.get(
        [Bonfire.Tag, :trending, :exclude_object_types],
        [Bonfire.Data.Identity.User],
        name: l("Trending Tags"),
        description: l("Set object types to exclude.")
      )

    exclude_ids =
      Bonfire.Common.Config.get(
        [Bonfire.Tag, :trending, :exclude_object_ids],
        maybe_apply(Bonfire.Label.ContentLabels, :built_in_ids, [], fallback_return: []),
        name: l("Trending Tags"),
        description: l("Set object IDs to exclude.")
      )

    opts = [
      only_table_ids: Enum.map(only_table_types, & &1.__pointers__(:table_id)),
      exclude_table_ids: Enum.map(exclude_object_types, & &1.__pointers__(:table_id)),
      exclude_ids: exclude_ids,
      limit: limit || @default_limit
    ]

    # |> debug()

    DateTime.now!("Etc/UTC")
    |> DateTime.add(-(in_last_x_days || @default_in_last_x_days) * 24 * 60 * 60, :second)
    |> Queries.list_trending(opts)
    |> repo().all()
    |> Enum.map(fn tag -> struct(Tagged, tag) end)
    |> repo().maybe_preload(tag: [:profile, :character, :named])
    |> repo().maybe_preload(:tag, skip_boundary_check: true)

    # |> debug
  end

  @doc """
  Try to find one (best-match) tag
  """
  def maybe_find_tag(current_user, id_or_username_or_url, types \\ nil)

  def maybe_find_tag(current_user, id_or_username_or_url, _types)
      when is_binary(id_or_username_or_url) do
    debug(id_or_username_or_url)
    # check if tag already exists
    get(id_or_username_or_url)
    <~> if is_uid?(id_or_username_or_url) do
      debug("try by ID")

      Needles.one(id_or_username_or_url,
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

  def get_mentions_from_changeset(%{changes: %{post_content: %{changes: %{mentions: mentions}}}}),
    do: mentions || []

  def get_mentions_from_changeset(_), do: []

  def get_hashtags_from_changeset(changeset),
    do: e(changeset, :changes, :post_content, :changes, :hashtags, [])

  def format_tag(%{} = obj), do: obj

  def format_tag(id) when is_binary(id) do
    if Types.is_uid?(id), do: %{tag_id: id}
  end

  def format_tag(other) do
    warn(other, "unsupported")
    nil
  end

  def format_tags(tags) do
    Enum.map(tags, &format_tag/1)
    |> filter_empty([])
    |> Enums.uniq_by_id()
  end

  @doc "For using on changesets (eg in epics)"
  def cast(changeset, attrs, creator, opts \\ []) do
    # with true <- module_enabled?(Bonfire.Tag, creator),
    # tag any mentions that were found in the text and injected into the changeset by PostContents (NOTE: this doesn't necessarily mean they should be included in boundaries or notified)
    # tag any hashtags that were found in the text and injected into the changeset by PostContents
    # TODO: what fields to look for should be defined by the caller ^
    with tags when is_list(tags) and length(tags) > 0 <-
           (get_mentions_from_changeset(changeset) ++
              get_hashtags_from_changeset(changeset) ++
              e(attrs, :tags, []))
           |> format_tags()
           |> debug(label: "cast tags") do
      changeset
      # does this really have to happen here? Could it be decoupled?
      |> maybe_put_tree_parent(opts[:put_tree_parent], creator)
      |> Changeset.cast(%{tagged: tags}, [])
      |> debug("before cast assoc")
      |> Changeset.cast_assoc(:tagged, with: &Bonfire.Tag.Tagged.changeset/2)
      |> debug("changeset with :tagged")
    else
      _ ->
        debug("not casting any tags")
        changeset
    end
  end

  def maybe_update_tags(creator, object, attrs) do
    # Use the already prepared hashtags and mentions from attrs
    new_hashtags = Map.get(attrs, :hashtags, %{}) |> Map.values()
    new_mentions = Map.get(attrs, :mentions, %{}) |> Map.values()
    all_new_tags = new_hashtags ++ new_mentions

    # Compare with current tags to find what needs to be added/removed
    current_tag_ids = (object.tags || []) |> Enums.ids() |> MapSet.new()
    new_tag_ids = all_new_tags |> Enums.ids() |> MapSet.new()

    if not MapSet.equal?(current_tag_ids, new_tag_ids) do
      # Find tags to remove and tags to add
      tags_to_remove_ids = MapSet.difference(current_tag_ids, new_tag_ids)
      tags_to_add_ids = MapSet.difference(new_tag_ids, current_tag_ids)

      # Remove tags that are no longer present
      if not Enum.empty?(tags_to_remove_ids) do
        Tagged.thing_tags_remove(object, MapSet.to_list(tags_to_remove_ids))
      end

      # Add only the new tags (we already have them in all_new_tags)
      if not Enum.empty?(tags_to_add_ids) do
        tags_to_add = all_new_tags |> Enum.filter(&(Enums.id(&1) in tags_to_add_ids))
        tag_something(creator, object, tags_to_add)
        # Bonfire.Tag.Tagged.thing_tags_insert(object, tags_to_add)
      end
    end
  end

  def maybe_put_tree_parent(changeset, category, creator)
      when is_map(category) or is_binary(category) do
    custodian =
      e(category, :tree, :custodian, nil) ||
        e(category, :tree, :custodian_id, nil) || creator

    with {:error, _} <-
           Utils.maybe_apply(
             Bonfire.Classify.Tree,
             :put_tree,
             [
               changeset,
               custodian,
               category
             ],
             custodian
           ) do
      changeset
    end
  end

  def maybe_put_tree_parent(changeset, _, _), do: changeset

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
        Bonfire.Common.Utils.maybe_apply(Bonfire.Social.PostContents, :all_text_content, [obj]),
        boost_category_mentions?
      )

  # def maybe_tag(_user, thing, _maybe_tags, boost_category_mentions?) do
  #   #debug(maybe_tags: maybe_tags)
  #   {:ok, thing}
  # end

  @doc """
  tag existing thing with one or multiple Tags, Needle, or anything that can be made into a tag
  """
  # def tag_something(user, thing, tags) when is_struct(thing) do
  #   with {:ok, tagged} <- do_tag_thing(user, thing, tags) do
  #     {:ok, Map.put(thing, :tags, Map.get(tagged, :tags, []))}
  #   end
  # end
  def tag_something(user, thing, tags, boost_or_label_category_tags? \\ true) do
    with {:ok, thing} <- do_tag_thing(user, thing, tags) do
      if boost_or_label_category_tags? &&
           module_enabled?(Bonfire.Social.Tags, user) do
        tags = e(thing, :tags, nil) || tags

        debug(tags, "Bonfire.Tag: try to boost mentions to the category's feed, as permitted")

        if boost_or_label_category_tags? == :skip_boundary_check do
          Bonfire.Common.Utils.maybe_apply(Bonfire.Social.Tags, :auto_boost, [tags, thing])
        else
          Bonfire.Common.Utils.maybe_apply(Bonfire.Social.Tags, :maybe_auto_boost, [
            user,
            tags,
            thing
          ])
        end
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
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq_by(&Enums.id/1)

      # |> debug("tags")

      # |> debug("tags")
      with {:ok, _tagged} <- thing_tags_save(pointer, tags) |> debug("saved") do
        {:ok, if(is_map(thing), do: thing, else: pointer) |> Map.merge(%{tags: tags})}
      end

      # repo().maybe_preload(thing, :tags)
    end
  end

  defp do_tag_thing(user, thing, tag), do: do_tag_thing(user, thing, [tag])

  # doc """ Prepare a tag to be used, by loading it from DB if necessary """
  defp tag_preprocess(_user, %{__struct__: _} = tag),
    do: thing_to_pointer(tag)

  defp tag_preprocess(_, tag) when is_nil(tag) or tag == "", do: nil

  defp tag_preprocess(_user, {:error, e}) do
    error(e, "Tags: invalid tag")
    nil
  end

  defp tag_preprocess(user, {_at_mention, tag}), do: tag_preprocess(user, tag)
  defp tag_preprocess(user, "@" <> tag), do: tag_preprocess(user, tag)
  defp tag_preprocess(user, "+" <> tag), do: tag_preprocess(user, tag)
  defp tag_preprocess(user, "&" <> tag), do: tag_preprocess(user, tag)

  defp tag_preprocess(_user, tag) when is_binary(tag),
    do: get(tag) |> ok_unwrap(nil) |> thing_to_pointer()

  defp tag_preprocess(_user, tag) do
    error(tag, "didn't recognise this as a tag")

    nil
  end

  def tag_ids(tags) when is_list(tags), do: Enum.map(tags, &tag_ids(&1))
  def tag_ids({_at_mention, %{id: tag_id}}), do: tag_id
  def tag_ids(%{id: tag_id}), do: tag_id

  defp thing_tags_save(%{} = thing, tags)
       when is_list(tags) and length(tags) > 0 do
    tags
    # |> debug("tags")
    |> Bonfire.Tag.Tagged.thing_tags_insert(thing, ...)

    # |> thing_tags_changeset(thing, ...)
    # |> debug("changeset")
    # |> repo().transact_with(fn -> repo().update(..., on_conflict: :nothing) end)
  end

  defp thing_tags_save(thing, _tags), do: {:ok, thing}

  defp thing_to_pointer({:ok, thing}), do: thing_to_pointer(thing)
  defp thing_to_pointer(%{} = thing), do: Needles.maybe_forge(thing)

  defp thing_to_pointer(pointer_id) when is_binary(pointer_id),
    do:
      Needles.one(id: pointer_id, skip_boundary_check: true)
      |> thing_to_pointer()

  defp thing_to_pointer(other) do
    warn(other, "dunno how to get a pointer from")
  end

  @doc """
  Add things (Pointer objects) to a tag. You usually want to add tags to a thing instead, see `thing_tags_changeset`
  """
  def tag_things_changeset(
        %{} = tag,
        things
      ) do
    debug(things, "things to tag")

    tag
    |> repo().maybe_preload(:tagged)
    # |> Changeset.change()
    # Set the association
    |> Changesets.put_assoc(:tagged, things)
  end

  @doc """
  Add tags to a thing (any Pointer object which defines a many_to_many relation to tag). This function applies to your object schema but is here for convenience.
  """

  def thing_tags_changeset(
        %{id: _thing_id} = thing,
        tags
      ) do
    debug(tags, "tags to add to thing")
    # FIXME...
    thing
    |> repo().maybe_preload(:tags)
    |> Changeset.change()
    # Set the association
    |> Changeset.put_assoc(:tags, tags)

    # |> Map.put(:tags, tags)
    # |> Changesets.cast_assoc(:tags, tags)
  end

  def indexing_object_format(object) do
    # debug(indexing_object_format: object)
    %{
      "id" => Enums.id(object),
      "index_type" => Types.module_to_str(Tag),
      "name" => indexing_object_format_name(object),
      "summary" => e(object, :profile, :summary, nil)
      # TODO: add url/username
    }
  end

  def indexing_object_format_name(object), do: e(object, :profile, :name, nil)
end
