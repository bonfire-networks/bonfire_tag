# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Tag do

  use Pointers.Mixin,
    otp_app: :bonfire_tag,
    source: "bonfire_tag"

  import Flexto

  alias Ecto.Changeset
  alias Bonfire.Tag

  import Bonfire.Common.Config, only: [repo: 0]

  @type t :: %__MODULE__{}
  @required ~w(id prefix facet)a

  mixin_schema do

    # eg. @ or + or #
    field(:prefix, :string)

    field(:facet, :string) # FIXME: make enum or ref to other table?

    # field(:tagged_count, :integer) # TODO

    # Optionally, a profile and character (if not using context) - TODO should be set these in config using Flexto instead (after (ArgumentError) field/association :character is already set on schema issue is sorted)
    has_one(:category, Bonfire.Classify.Category, references: :id, foreign_key: :id)
    # stores common fields like name/description
    has_one(:profile, Bonfire.Data.Social.Profile, references: :id, foreign_key: :id)
    # allows it to be follow-able and federate activities
    has_one(:character, Bonfire.Data.Identity.Character, references: :id, foreign_key: :id)
    # location used as tag
    has_one(:geolocation, Bonfire.Geolocate.Geolocation, references: :id, foreign_key: :id)

    many_to_many(:tagged, Pointers.Pointer,
      join_through: Bonfire.Tag.Tagged,
      unique: true,
      join_keys: [tag_id: :id, pointer_id: :id],
      on_replace: :delete
    )

    # include fields/relations defined in config (using Flexto)
    flex_schema(:bonfire_tag)
  end

  def create_changeset(attrs) do
    %Tag{}
    |> Changeset.cast(attrs, @required)
    |> common_changeset()
  end

  def update_changeset(
        %Tag{} = tag,
        attrs
      ) do
    tag
    |> Changeset.cast(attrs, @required)
    |> common_changeset()
  end

  defp common_changeset(changeset) do
    changeset
    # |> Changeset.foreign_key_constraint(:pointer_id, name: :tag_pointer_id_fkey)
    # |> change_public()
    # |> change_disabled()
  end

  @doc """
  Add things (Pointer objects) to a tag. You usually want to add tags to a thing instead, see `thing_tags_changeset`
  """
  def tag_things_changeset(
        %Tag{} = tag,
        things
      ) do
    tag
    |> repo().preload(:tagged)
    |> Changeset.change()
    # Set the association
    |> Ecto.Changeset.put_assoc(:tagged, things)
    |> common_changeset()
  end

  @doc """
  Add tags to a thing (any Pointer object which defines a many_to_many relation to tag). This function applies to your object schema but is here for convenience.
  """
  def thing_tags_changeset(
        %{} = thing,
        tags
      ) do
    thing
    |> repo().preload(:tags)
    |> Changeset.change()
    # Set the association
    |> Ecto.Changeset.put_assoc(:tags, tags)
    |> common_changeset()
  end

  def context_module, do: Bonfire.Tag.Tags

  def queries_module, do: Bonfire.Tag.Queries

  def follow_filters, do: [:default]
end
