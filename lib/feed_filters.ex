defmodule Bonfire.Tag.FeedFilters do
  @moduledoc """
  Narrows a feed by what its objects are tagged with, given as ids, as hashtag names, or as a mix of both.

  "Mentions of me" is this filter with the reader's id in it: a mention is stored as an ordinary `:create` carrying a Tagged row from the post to the person named, so nothing about the activity says it is a mention and only the tag does. The notifications Mentions chip and the audience rows about unsolicited mentions both pass an id here, and nothing needs a second predicate.

  Lives here rather than in the feed loader because a Tagged row is this extension's. The key is declared as a field on `Bonfire.Social.FeedFilters` from this extension's config, and this module applies it; `Bonfire.Common.FeedFilterModule` explains why the two halves are declared in different places.
  """
  use Bonfire.Common.Utils, only: []
  use Bonfire.Common.Repo
  import Untangle

  @behaviour Bonfire.Common.FeedFilterModule

  @impl true
  def feed_filter_module, do: __MODULE__

  @doc """
  Cleans a user-typed hashtag for the `:tags` filter (strips `#`, rejects junk).

  Keeps the case somebody typed and refuses what cannot be a hashtag, which is what an input needs; `Bonfire.Tag.Hashtag.normalize_name/1` is the other direction, canonicalising a name for matching and never refusing.

      iex> normalise_tag("#Bonfire ")
      "Bonfire"
      iex> normalise_tag("bad tag")
      nil
  """
  def normalise_tag(tag) when is_binary(tag) do
    tag = tag |> String.trim() |> String.trim_leading("#")
    if tag != "" and not String.contains?(tag, [" ", "/"]), do: tag
  end

  def normalise_tag(_), do: nil

  @impl true
  def maybe_filter(query, filter, opts \\ [])

  def maybe_filter(query, {:tags, tags}, _opts)
      when is_binary(tags) or (is_list(tags) and tags != []) do
    case ids_and_hashtags(tags) do
      {[], []} ->
        query

      {ids, []} ->
        query
        |> proload(:inner, activity: [object: [:tagged]])
        |> where([tagged: tagged], tagged.tag_id in ^ids)

      {[], hashtags} ->
        query
        |> proload(:inner, activity: [object: [tagged: {"tagged_", [:named]}]])
        |> where([tagged_named: tagged_named], tagged_named.name in ^hashtags)

      {ids, hashtags} ->
        query
        |> proload(:inner, activity: [object: [:tagged]])
        |> proload(activity: [object: [tagged: {"tagged_", [:named]}]])
        |> where(
          [tagged: tagged, tagged_named: tagged_named],
          tagged.tag_id in ^ids or tagged_named.name in ^hashtags
        )
    end
  end

  # the other side: leaves out what is tagged with any of these, so "replies that don't name me" is a reply filter plus this with the reader in it. A NOT EXISTS rather than a join, because an object with several tags would otherwise come back once per tag, and an object with none has to stay
  def maybe_filter(query, {:exclude_tags, tags}, _opts)
      when is_binary(tags) or (is_list(tags) and tags != []) do
    case ids_and_hashtags(tags) do
      {[], []} ->
        query

      {ids, hashtags} ->
        where(query, not exists(tagged_with(ids, hashtags)))
    end
  end

  def maybe_filter(query, _filter, _opts), do: query

  # ids and hashtag names mean the same in both directions, so both parse them here
  defp ids_and_hashtags(tags) do
    tags
    |> debug("tags provided")
    |> Types.partition_uids(prepare_non_uid_fun: &Bonfire.Tag.Hashtag.normalize_name/1)
    |> debug("partitioned")
  end

  defp tagged_with(ids, hashtags) do
    from(tagged in Bonfire.Tag.Tagged,
      left_join: named in Bonfire.Data.Identity.Named,
      on: named.id == tagged.tag_id,
      where: tagged.id == parent_as(:activity).object_id,
      where: tagged.tag_id in ^ids or named.name in ^hashtags,
      select: 1
    )
  end
end
