defmodule Bonfire.Tag.Tagged do
  use Ecto.Schema
  import Ecto.Query, only: [from: 2]
  import Bonfire.Common.Config, only: [repo: 0]

  @primary_key false
  @foreign_key_type Pointers.ULID
  schema "bonfire_tagged" do
    belongs_to :tag, Bonfire.Tag
    belongs_to :pointer,  Pointers.Pointer
    timestamps() # Added bonus, a join schema will also allow you to set timestamps
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> Ecto.Changeset.cast(params, [:tag_id, :pointer_id])
    |> Ecto.Changeset.validate_required([:tag_id, :pointer_id])
  end

  @doc """
  Get the latest tag added to a thing
  """
  def latest(%{id: id}), do: latest(id)

  def latest(thing_id) do
      q = from va in Bonfire.Tag.Tagged,
      order_by: [desc: va.inserted_at],
      where: va.id == ^thing_id,
      limit: 1

    tagged = repo().one(q)
      |> repo().maybe_preload([:pointer, [tag: [:profile, :geolocation, :category, :character]]])

    tagged
      |> Map.put(:thing, Bonfire.Common.Pointers.follow!(tagged.pointer))
  end

  @doc """
  Get the things tagged with a certain tag
  """
  def with_tag(%{id: id}), do: with_tag(id)
  def with_tag(tag_id) do
      q = from va in Bonfire.Tag.Tagged,
      where: [tag_id: ^tag_id],
      order_by: [desc: va.inserted_at]

    repo().all(q)
  end

  @doc """
  Get the tags of a thing
  """
  def with_thing(%{id: id}), do: with_thing(id)
  def with_thing(thing_id) do
      q = from va in Bonfire.Tag.Tagged,
      where: [pointer_id: ^thing_id],
      order_by: [desc: va.inserted_at]

    repo().all(q)
  end

  def all() do
    repo().all(Bonfire.Tag.Tagged)
  end
end
