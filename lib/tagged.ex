defmodule Bonfire.Tag.Tagged do
  use Ecto.Schema
  use Pointers.Mixin,
    otp_app: :bonfire_tag,
    source: "bonfire_tagged"

  import Ecto.Query, only: [from: 2]
  import Bonfire.Common.Config, only: [repo: 0]

  mixin_schema do
    belongs_to :tag, Bonfire.Tag
    timestamps() # Added bonus, a join schema will also allow you to set timestamps
  end

  @cast [:id, :tag_id]
  @required [:tag_id]

  def changeset(struct, params \\ %{})

  def changeset(struct, %_{id: tag_id} = _object) do
    struct
    |> Ecto.Changeset.cast(%{tag_id: tag_id}, @cast)
    |> Ecto.Changeset.validate_required(@required)
  end

  def changeset(struct, params) do
    struct
    |> Ecto.Changeset.cast(params, @cast)
    |> Ecto.Changeset.validate_required(@required)
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

    repo().many(q)
  end

  @doc """
  Get the tags of a thing
  """
  def with_thing(%{id: id}), do: with_thing(id)
  def with_thing(thing_id) do
    q = from va in Bonfire.Tag.Tagged,
      where: [id: ^thing_id],
      order_by: [desc: va.inserted_at]
    repo().many(q)
  end

  def all(), do: repo().many(Bonfire.Tag.Tagged)

end
