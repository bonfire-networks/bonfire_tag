Bonfire.Common.Config.require_extension_config!(:bonfire_tag)

defmodule Bonfire.Tag.Tags do

  import Bonfire.Common.Config, only: [repo: 0]
  alias Bonfire.Common.Utils

  alias Bonfire.Tag
  alias Bonfire.Tag.Queries
  alias Bonfire.Tag.TextContent.Process

  require Logger

  def cursor(), do: &[&1.id]
  def test_cursor(), do: &[&1["id"]]

  @doc """
  Retrieves a single tag by arbitrary filters.
  Used by:
  * GraphQL Item queries
  * ActivityPub integration
  * Various parts of the codebase that need to query for tags (inc. tests)
  """
  def one(filters), do: repo().single(Queries.query(Tag, filters))

  @doc """
  Retrieves a list of tags by arbitrary filters.
  Used by:
  * Various parts of the codebase that need to query for tags (inc. tests)
  """
  def many(filters \\ []), do: {:ok, repo().many(Queries.query(Tag, filters))}


  def get(id) do
    if Bonfire.Common.Utils.is_ulid?(id) do
      one(id: id)
    else
      # TODO: lookup Peered with canonical_uri if id is a URL
      with {:ok, character} <- Utils.maybe_apply(Bonfire.Me.Characters, :by_username, id) do
        {:ok, character}
      else _ ->
        one(username: id)
      end
    end
  end

  def find(id) do
    if Bonfire.Common.Utils.is_ulid?(id) do
      one(id: id)
    else
      # TODO: lookup Peered with canonical_uri if id is a URL
      many(autocomplete: id)
    end
  end

  # def many(filters \\ []), do: {:ok, repo().many(Queries.query(Tag, filters))}

  def prefix("Community") do
    "&"
  end

  def prefix("User") do
    "@"
  end

  def prefix(_) do
    "+"
  end

  def maybe_find_tag(user \\ nil, id_or_username_or_url) when is_binary(id_or_username_or_url) do
    Logger.info("Tags.maybe_find_tag: #{id_or_username_or_url}")
    with {:ok, tag} <- get(id_or_username_or_url) do # check if tag already exists
      {:ok, tag}
    else
      e ->
      # Logger.info("Tags.maybe_find_tag: no prexisting tag #{inspect e}")

        if Bonfire.Common.Utils.is_ulid?(id_or_username_or_url) do
          Logger.info("Tags.maybe_find_tag: try by ID")
          with {:ok, obj} <- Bonfire.Common.Pointers.one(id_or_username_or_url, current_user: user, skip_boundary_check: true) do
            {:ok, obj}
          end
        else
          # if Bonfire.Common.Extend.extension_enabled?(Bonfire.Federate.ActivityPub) do
          Logger.info("Tags.maybe_find_tag: try get_by_url_ap_id_or_username")
            with {:ok, federated_object_or_character} <- Bonfire.Federate.ActivityPub.Utils.get_by_url_ap_id_or_username(id_or_username_or_url) do
              Logger.debug("Tags: federated_object_or_character: #{inspect federated_object_or_character}")
              {:ok, federated_object_or_character}
            end
          # else
          #   {:error, "no such tag"}
          # end
        end
    end
  end

  @doc """
  Search / autocomplete for tags by name
  """
  def maybe_find_tags(_user \\ nil, id_or_username_or_url) when is_binary(id_or_username_or_url) do
    Logger.info("Tags.maybe_find_tag: #{id_or_username_or_url}")
    with {:ok, tags} <- find(id_or_username_or_url) do # check if tag already exists
      {:ok, tags}
    else
      e ->
        {:ok, [maybe_find_tag(id_or_username_or_url)]}
    end
  end

  @doc """
  Lookup a signle for a tag by its name/username
  """
  def maybe_lookup_tag(id_or_username_or_url, _prefix \\ "@") when is_binary(id_or_username_or_url) do
    maybe_find_tag(id_or_username_or_url)
  end

### Functions for creating tags ###

  @doc """
  Create a Tag from an existing object (eg. Bonfire.Geolocate.Geolocation)
  """
  def maybe_make_tag(user, context) do
    maybe_make_tag(user, context, %{})
  end

  def maybe_make_tag(user, %Bonfire.Tag{} = tag, attrs) do
    {:ok, tag}
  end

  def maybe_make_tag(user, id_or_username_or_url, attrs) when is_binary(id_or_username_or_url) do
    if Bonfire.Common.Utils.is_numeric(id_or_username_or_url) do # rembemer is_number != is_numeric
      maybe_make_tag(user, String.to_integer(id_or_username_or_url), attrs)
    else
      with {:ok, tag} <- maybe_find_tag(user, id_or_username_or_url) do
        Logger.info("Tag does not already exist, make it now")
        make_tag(user, tag, attrs)
      end
    end
  end

  def maybe_make_tag(user, %Pointers.Pointer{} = pointer, attrs) do
    with {:ok, obj} <- Bonfire.Common.Pointers.get(pointer, current_user: user, skip_boundary_check: true) do
      Logger.info("Tag from pointer")
      if obj != pointer do
        maybe_make_tag(user, obj, attrs)
      end
    end
  end

  def maybe_make_tag(user, %{id: _} = obj, attrs) when is_struct(obj) do # some other obj
    Logger.info("Tag from struct")
    make_tag(user, obj, attrs)
  end

  def maybe_make_tag(user, %{id: id} = _context, attrs) do
    Logger.info("Tag from object or search index")
    maybe_make_tag(user, id, attrs)
  end

  def maybe_make_tag(user, %{value: value} = _context, attrs) do
    # FIXME?
    maybe_make_tag(user, value, attrs)
  end

  def maybe_make_tag(user, id, _) when is_number(id) do # for the old taxonomy with int IDs
    with {:ok, t} <- maybe_taxonomy_tag(user, id) do
      {:ok, t}
    else
      _e ->
        {:error, "Please provide a pointer"}
    end
  end

  # def maybe_make_tag(user, %{} = obj, attrs) do
  #   make_tag(user, obj, attrs)
  # end

  @doc """
  Create a tag mixin for an existing poitable object (you usually want to use maybe_make_tag instead)
  """
  def make_tag(_creator, %{id: _} = pointable_obj, attrs) when is_map(attrs) do
    repo().transact_with(fn ->
      # TODO: check that the tag doesn't already exist (same name and parent)

      with {:ok, attrs} <- attrs_with_tag(attrs, pointable_obj),
           {:ok, tag} <- insert_tag(attrs) do
            # TODO: add Peered mixin with canonical URL
        {:ok, tag}
      end
    end)
  end

  defp attrs_with_tag(%{facet: facet} = attrs, %{} = pointable_obj) when not is_nil(facet) do
    attrs = Map.put(attrs, :prefix, prefix(attrs.facet))
    attrs = Map.put(attrs, :id, pointable_obj.id)
    #IO.inspect(attrs)
    {:ok, attrs}
  end

  defp attrs_with_tag(attrs, %{} = pointable_obj) do
    attrs_with_tag(
      Map.put(
        attrs,
        :facet,
        Bonfire.Common.Types.object_type(pointable_obj) |> to_string() |> String.split(".") |> List.last()
      ),
      pointable_obj
    )
  end

  defp insert_tag(attrs) do
    #IO.inspect(insert_tag: attrs)
    cs = Tag.create_changeset(attrs)
    with {:ok, tag} <- repo().insert(cs, on_conflict: :nothing), do: {:ok, tag}
  end

  # TODO: take the user who is performing the update
  def update(_user, %Tag{} = tag, attrs) do
    repo().transact_with(fn ->
      # :ok <- publish(tag, :updated)
      with {:ok, tag} <- repo().update(Tag.update_changeset(tag, attrs)) do
        {:ok, tag}
      end
    end)
  end


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

  # def maybe_tag(user, thing, %{tags: tag_string}) when is_binary(tag_string) do
  #   tag_strings = Bonfire.Tag.Autocomplete.tags_split(tag_string)
  #   tag_something(user, thing, tag_strings)
  # end

  def maybe_tag(user, thing, %{tags: tags}, boost_category_mentions?), do: maybe_tag(user, thing, tags, boost_category_mentions?)
  def maybe_tag(user, thing, %{tag: tag}, boost_category_mentions?), do: maybe_tag(user, thing, tag, boost_category_mentions?)
  def maybe_tag(user, thing, tags, boost_category_mentions?) when is_list(tags), do: tag_something(user, thing, tags, boost_category_mentions?)
  def maybe_tag(user, thing, %Bonfire.Tag{} = tag, boost_category_mentions?), do: tag_something(user, thing, tag, boost_category_mentions?)

  def maybe_tag(user, thing, text, boost_category_mentions?) when is_binary(text) do

    tag_or_tags = if text != "", do: Bonfire.Tag.Autocomplete.find_all_tags(text) # TODO, switch to TextContent.Process?

    case tag_or_tags do
      %{} = tag ->

        maybe_tag(user, thing, tag, boost_category_mentions?)

      tags when is_list(tags) and length(tags)>0 ->

        maybe_tag(user, thing, tags, boost_category_mentions?)

      _ ->
        Logger.info("Bonfire.Tag - no matches in '#{text}'")
        {:ok, thing}
    end
  end

  #doc """ otherwise maybe we have tagnames inline in the text of the object? """
  def maybe_tag(user, obj, _, boost_category_mentions?), do: maybe_tag(user, obj, Process.object_text_content(obj), boost_category_mentions?)

  # def maybe_tag(_user, thing, _maybe_tags, boost_category_mentions?) do
  #   #IO.inspect(maybe_tags: maybe_tags)
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

  def tag_something(user, thing, tags, boost_category_mentions?) do
    with {:ok, thing} <- do_tag_thing(user, thing, tags) do

      if boost_category_mentions? and Bonfire.Common.Utils.module_enabled?(Bonfire.Classify.Categories) and Bonfire.Common.Utils.module_enabled?(Bonfire.Social.Boosts) do
        Logger.info("Bonfire.Tag: boost mentions to the category's feed")
        tags = thing.tags
        |> repo().maybe_preload([:category, :character])
        |> Enum.reject(&(is_nil(&1.category) or is_nil(&1.character)))
        |> Enum.each(&Bonfire.Social.Boosts.boost(&1, thing))
      end

      {:ok, thing}
    end
  end

  #doc """ Add tag(s) to a pointable thing. Will replace any existing tags. """
  defp do_tag_thing(user, thing, tags) when is_list(tags) do
    pointer = thing_to_pointer(thing)
    tags = Enum.map(tags, &tag_preprocess(user, &1)) |> Enum.reject(&is_nil/1)
    # IO.inspect(do_tag_thing: tags)
    with {:ok, tagged} <- thing_tags_save(pointer, tags) do
       {:ok, (if is_map(thing), do: thing, else: pointer) |> Map.merge(%{tags: tags})}
    end
    # Bonfire.Repo.maybe_preload(thing, :tags)
  end

  defp do_tag_thing(user, thing, tag) do
    do_tag_thing(user, thing, [tag])
  end

  #doc """ Prepare a tag to be used, by loading or even creating it """
  defp tag_preprocess(_user, %Tag{} = tag) do
    tag
  end

  defp tag_preprocess(_, tag) when is_nil(tag) or tag == "" do
    nil
  end

  defp tag_preprocess(_user, {:error, e}) do
    Logger.warn("Tags: invalid tag: #{inspect e}")
    nil
  end

  defp tag_preprocess(user, {_at_mention, tag}) do
    # IO.inspect("wooo")
    tag_preprocess(user, tag)
  end

  defp tag_preprocess(user, "@" <> tag) do
    tag_preprocess(user, tag)
  end

  defp tag_preprocess(user, "+" <> tag) do
    tag_preprocess(user, tag)
  end

  defp tag_preprocess(user, "&" <> tag) do
    tag_preprocess(user, tag)
  end

  defp tag_preprocess(user, tag) do

    with {:ok, tag} <- maybe_make_tag(user, tag) do
      # with an object that we have just made into a tag
      tag_preprocess(user, tag)
    else
      e ->
        Logger.error("Got #{inspect e} when trying to find or create this tag: #{inspect tag} ")
        nil
    end
  end

  def tag_ids(tags) when is_list(tags) do
    Enum.map(tags, &tag_ids(&1))
  end
  def tag_ids({_at_mention, %{id: tag_id}}) do
    tag_id
  end
  def tag_ids(%{id: tag_id}) do
    tag_id
  end


  defp thing_tags_save(%{} = thing, tags) when is_list(tags) and length(tags) > 0 do
    # remove nils
    tags = Enum.filter(tags, & &1)
    |> Map.new(fn x -> {x.id, x} end)
    |> Map.values()
    # |> IO.inspect(label: "thing_tags_save")

    repo().transact_with(fn ->
      cs = Tag.thing_tags_changeset(thing, tags)
      with {:ok, tagged} <- repo().update(cs, on_conflict: :nothing), do:
        {:ok, tagged}
    end)
  end

  defp thing_tags_save(thing, _tags) do
    {:ok, thing}
  end

  #doc """ Load thing as Pointer """
  defp thing_to_pointer(pointer_id) when is_binary(pointer_id) do
    with {:ok, pointer} <- Bonfire.Common.Pointers.one(id: pointer_id, skip_boundary_check: true) do
      pointer
    end
  end

  defp thing_to_pointer(%Pointers.Pointer{} = pointer) do
    pointer
  end

  defp thing_to_pointer(%{id: id}) do
    thing_to_pointer(id)
  end

  def indexing_object_format(object) do
    # IO.inspect(indexing_object_format: object)
    %{
      "id"=> object.id,
      "name"=> object.profile.name,
      "summary"=> object.profile.summary,
      "prefix"=> object.prefix,
      "facet"=> object.facet
      # TODO: add url/username
    }
  end

  def indexing_object_format_name(object) do
     object.profile.name
  end


end
