defmodule Bonfire.Tag.Migrations do
  import Ecto.Migration
  import Pointers.Migration

  alias Bonfire.Tag

  def up() do

    create_mixin_table("bonfire_tag") do
      add(:prefix, :string)
      add(:facet, :string)
    end

  end

  def tagged_up() do

    create_if_not_exists table(:bonfire_tagged, primary_key: false) do
      add(:pointer_id, strong_pointer(), null: false)

      add(:tag_id, strong_pointer(Tag), null: false)
    end

    create(unique_index(:bonfire_tagged, [:pointer_id, :tag_id]))
  end

  def tagged_timestamps_up() do
    alter table(:bonfire_tagged) do
      add :inserted_at, :naive_datetime, default: fragment("now()")
      add :updated_at, :naive_datetime
    end
  end

  def tagged_timestamps_down() do
    alter table(:bonfire_tagged) do
      remove :inserted_at
      remove :updated_at
    end
  end

  def down() do
    drop_mixin_table(Tag)
  end

  def tagged_down() do
    drop_table(:bonfire_tagged)
  end
end
