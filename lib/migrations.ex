defmodule Bonfire.Tag.Migrations do
  import Ecto.Migration
  import Pointers.Migration

  alias Bonfire.Tag.Tagged
  alias Bonfire.Data.Social.Hashtag
  require Bonfire.Tag.Hashtag.Migration

  @table_name :bonfire_tagged

  def up() do
    create_mixin_table(@table_name, primary_key: false) do
      add(:tag_id, strong_pointer(), null: false, primary_key: true)
      add(:inserted_at, :naive_datetime, default: fragment("now()"))
      add(:updated_at, :naive_datetime)
    end

    create(index(@table_name, [:tag_id]))
  end

  def down(), do: drop_mixin_table(Bonfire.Tag.Tagged)

  def migrate_hashtag(), do: Bonfire.Tag.Hashtag.Migration.migrate_hashtag()
end
