# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Tag do
  import Bonfire.Common.Config, only: [repo: 0]
  alias Ecto.Changeset
  import Untangle
  alias Needle.Changesets

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

  @behaviour Bonfire.Common.SchemaModule
  def context_module, do: Bonfire.Tag.Tags
  def query_module, do: Bonfire.Tag.Queries
end
