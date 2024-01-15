defmodule Bonfire.Tag.Tagged do
  import Ecto.Query, only: [from: 2]
  use Bonfire.Common.Repo
  use Ecto.Schema
  import Untangle

  use Needle.Mixin,
    otp_app: :bonfire_tag,
    source: "bonfire_tagged"

  alias Bonfire.Common.Utils
  alias Bonfire.Common.Types
  alias Needle.Pointer

  mixin_schema do
    belongs_to(:tag, Pointer)

    field(:count, :integer, virtual: true)

    # Added bonus, a join schema will also allow you to set timestamps
    timestamps()
  end

  @cast [:id, :tag_id]
  @required [:tag_id]

  def changeset(struct, params \\ %{})

  def changeset(struct, %_{id: tag_id} = _object) do
    debug(tag_id, "tag_id")

    struct
    |> Ecto.Changeset.cast(%{tag_id: tag_id}, @cast)
    |> Ecto.Changeset.validate_required(@required)
  end

  def changeset(struct, params) do
    debug(params, "params")

    struct
    |> Ecto.Changeset.cast(params, @cast)
    |> Ecto.Changeset.validate_required(@required)
  end

  @doc """
  Get the latest tag added to a thing
  """
  def latest(%{id: id}), do: latest(id)

  def latest(thing_id) do
    q =
      from(va in Bonfire.Tag.Tagged,
        order_by: [desc: va.inserted_at],
        where: va.id == ^thing_id,
        limit: 1
      )

    tagged =
      repo().one(q)
      |> repo().maybe_preload([
        :pointer,
        [tag: [:profile, :geolocation, :category, :character]]
      ])

    Map.put(tagged, :thing, Bonfire.Common.Needles.get(Utils.e(tagged, :pointer, nil)))
  end

  @doc """
  List the things tagged with a certain tag
  """
  def q_with_tag(%{id: id}), do: q_with_tag(id)

  def q_with_tag(tag_id) do
    from(va in Bonfire.Tag.Tagged,
      where: va.tag_id in ^Types.ulids(tag_id),
      order_by: [desc: va.inserted_at]
    )
  end

  def with_tag(tag_id) do
    repo().many(q_with_tag(tag_id))
  end

  @doc """
  List the tags of a thing
  """
  def q_with_thing(%{id: id}), do: q_with_thing(id)

  def q_with_thing(thing_id) do
    from(va in Bonfire.Tag.Tagged,
      where: [id: ^thing_id],
      order_by: [desc: va.inserted_at]
    )
  end

  def with_thing(thing_id) do
    repo().many(q_with_tag(thing_id))
  end

  @doc """
  List by type of tagged thing
  """
  def q_with_type(types) do
    table_ids =
      List.wrap(types)
      |> Enum.map(&Utils.maybe_apply(&1, :__pointers__, :table_id))

    from(va in Bonfire.Tag.Tagged,
      left_join: tag in assoc(va, :tag),
      where: tag.table_id in ^Types.ulids(table_ids),
      order_by: [desc: va.inserted_at]
    )
  end

  def with_type(types) do
    repo().many(q_with_type(types))
  end

  def search_query(text, opts) do
    case Bonfire.Tag.Tags.search_hashtag(text, opts) do
      [] ->
        opts[:query] || nil

      hashtags ->
        (opts[:query] || Pointer)
        |> proload([:tagged])
        |> or_where(
          [tagged: t],
          t.tag_id in ^Types.ulids(hashtags)
        )
    end
  end

  def all(), do: repo().many(Bonfire.Tag.Tagged)
end
