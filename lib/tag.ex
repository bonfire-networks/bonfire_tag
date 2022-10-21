# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Tag do
  import Bonfire.Common.Config, only: [repo: 0]
  alias Ecto.Changeset

  @doc """
  Add things (Pointer objects) to a tag. You usually want to add tags to a thing instead, see `thing_tags_changeset`
  """
  def tag_things_changeset(
        %{} = tag,
        things
      ) do
    tag
    |> repo().maybe_preload(:tagged)
    |> Changeset.change()
    # Set the association
    |> Changeset.put_assoc(:tagged, things)
  end

  @doc """
  Add tags to a thing (any Pointer object which defines a many_to_many relation to tag). This function applies to your object schema but is here for convenience.
  """

  def thing_tags_changeset(
        %{} = thing,
        tags
      ) do
    thing
    |> repo().maybe_preload(:tags)
    |> Changeset.change()
    # Set the association
    |> Changeset.put_assoc(:tags, tags)
  end

  @behaviour Bonfire.Common.SchemaModule
  def context_module, do: Bonfire.Tag.Tags
  def query_module, do: Bonfire.Tag.Queries
end
