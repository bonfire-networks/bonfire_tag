defmodule Bonfire.Tag.Hashtag do

  use Pointers.Pointable,
    otp_app: :bonfire_tag,
    table_id: "7HASHTAG1SPART0FF01KS0N0MY",
    source: "bonfire_tag_hashtag"
  @hashtag_table "bonfire_tag_hashtag"

  alias Bonfire.Tag.Hashtag
  # alias Pointers.Changesets
  import Ecto.Changeset
  import Ecto.Query
  import Bonfire.Common.Config, only: [repo: 0]

  pointable_schema do
    field :name, :string
  end

  def changeset(hashtag \\ %Hashtag{}, params)

  def changeset(%Hashtag{} = struct, params) do
    struct
    |> cast(params, [:name])
    |> update_change(:name, &normalize_name/1)
    |> validate_required([:name])
    |> unique_constraint(:name)
  end

  def normalize_name(name) do
    name
    |> String.downcase()
    |> String.trim_leading("#")
    |> String.trim()
    |> String.replace(" ", "_")
  end

  def get_or_create_by_name(name) do
    changeset = changeset(%Hashtag{}, %{name: name})

    repo().insert(
      changeset,
      on_conflict: [set: [name: get_field(changeset, :name)]],
      conflict_target: :name,
      returning: true
    )
  end
end

defmodule Bonfire.Tag.Hashtag.Migration do
  use Ecto.Migration
  import Pointers.Migration
  alias Bonfire.Tag.Hashtag

  @hashtag_table "bonfire_tag_hashtag"

  defp make_hashtag_table(exprs) do
    quote do
      require Pointers.Migration
      Pointers.Migration.create_pointable_table(Bonfire.Tag.Hashtag) do
        Ecto.Migration.add :name, :string
        unquote_splicing(exprs)
      end
    end
  end

  defmacro create_hashtag_table, do: make_hashtag_table([])
  defmacro create_hashtag_table([do: body]), do: make_hashtag_table(body)

  def drop_hashtag_table(), do: drop_pointable_table(Hashtag)

  defp make_name_index(opts) do
    quote do
      Ecto.Migration.create_if_not_exists(
        Ecto.Migration.unique_index(unquote(@hashtag_table), [:name], unquote(opts))
      )
    end
  end

  defmacro create_name_index(opts \\ [])
  defmacro create_name_index(opts), do: make_name_index(opts)

  # drop_name_index/{0,1}

  def drop_name_index(opts \\ []) do
    drop_if_exists(unique_index(@hashtag_table, [:name], opts))
  end

  defp maa(:up) do
    quote do
      unquote(make_hashtag_table([]))
      unquote(make_name_index([]))
    end
  end
  defp maa(:down) do
    quote do
      Bonfire.Tag.Hashtag.Migration.drop_name_index()
      Bonfire.Tag.Hashtag.Migration.drop_hashtag_table()
    end
  end

  defmacro migrate_hashtag() do
    quote do
      if Ecto.Migration.direction() == :up,
        do: unquote(maa(:up)),
        else: unquote(maa(:down))
    end
  end
  defmacro migrate_hashtag(dir), do: maa(dir)
end
