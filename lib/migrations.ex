defmodule Bonfire.Tag.Migrations do
  import Ecto.Migration
  import Pointers.Migration

  alias Bonfire.Tag

  def up() do

    create_mixin_table(Bonfire.Tag) do
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

  def down() do
    drop_mixin_table(Tag)
  end

  def tagged_down() do
    drop_table(:bonfire_tagged)
  end
end
