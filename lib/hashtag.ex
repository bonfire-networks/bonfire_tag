defmodule Bonfire.Tag.Hashtag do
  @moduledoc "A virtual schema used for hashtags"

  use Needle.Virtual,
    otp_app: :bonfire_tag,
    table_id: "7HASHTAG1SPART0FF01KS0N0MY",
    source: "bonfire_hashtag"

  alias Bonfire.Tag.Hashtag
  alias Bonfire.Data.Identity.Named
  # alias Needle.Changesets
  import Ecto.Changeset

  virtual_schema do
    has_one(:named, Named, foreign_key: :id, references: :id)
  end

  def changeset(hashtag \\ %Hashtag{}, params)

  def changeset(cs, %{name: name}) do
    changeset(cs, %{named: %{name: name}})
  end

  def changeset(cs, name) when is_binary(name) do
    changeset(cs, %{named: %{name: name}})
  end

  def changeset(cs, %{named: %{name: name}} = params) when is_binary(name) do
    cs
    |> cast(params, [])
    |> cast_assoc(:named,
      with: fn cs, params ->
        Named.changeset(cs, params, normalize_fn: &normalize_name/1)
      end
    )
  end

  def normalize_name(name) do
    name
    |> String.trim()
    # |> String.downcase()
    |> String.trim_leading("#")
    |> String.replace(" ", "_")
  end
end

defmodule Bonfire.Tag.Hashtag.Migration do
  @moduledoc false
  use Ecto.Migration
  import Needle.Migration
  alias Bonfire.Tag.Hashtag
  @old_hashtag_table "bonfire_tag_hashtag"
  @hashtag_view "bonfire_hashtag"
  @named_mixin "bonfire_data_social_named"

  # def migrate_hashtag(), do: migrate_virtual(Hashtag)

  def maybe_migrate_old_table(_opts \\ []) do
    execute """
    do $$
    begin

    if exists (
      select 1
      from information_schema.columns
      where table_name='#{@old_hashtag_table}'
      and column_name='name'
      -- AND NOT attisdropped
    )

    then

    insert into #{@named_mixin}(id, name)
        select id, name from #{@old_hashtag_table}
          ON CONFLICT DO NOTHING ;

    insert into #{@hashtag_view}(id)
        select id from #{@old_hashtag_table}
          ON CONFLICT DO NOTHING ;

    end if;

    end $$
    """

    # drop_if_exists table(@old_hashtag_table)
  end

  defp maa(:up) do
    quote do
      migrate_virtual(Bonfire.Tag.Hashtag)
      Bonfire.Tag.Hashtag.Migration.maybe_migrate_old_table()
    end
  end

  defp maa(:down) do
    quote do
      migrate_virtual(Bonfire.Tag.Hashtag)
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
