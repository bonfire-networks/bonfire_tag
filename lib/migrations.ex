defmodule Bonfire.Tag.Migrations do
  import Ecto.Migration
  import Pointers.Migration

  alias Bonfire.Tag
  alias Bonfire.Tag.Tagged

  def up() do
    create_mixin_table(Tag) do
      add(:prefix, :string)
      add(:facet, :string)
    end

  end

  def tagged_up() do
    create_mixin_table(Tagged, primary_key: false) do
      add(:tag_id, strong_pointer(Tag), null: false, primary_key: true)
    end
    create(index(:bonfire_tagged, [:tag_id]))
  end

  def tagged_timestamps_up() do
    alter table(:bonfire_tagged) do
      add_if_not_exists :inserted_at, :naive_datetime, default: fragment("now()")
      add_if_not_exists :updated_at, :naive_datetime
    end
  end

  def tagged_timestamps_down() do
    alter table(:bonfire_tagged) do
      remove :inserted_at
      remove :updated_at
    end
  end

  def down(), do: drop_mixin_table(Tag)

  def tagged_down(), do: drop_mixin_table(Tagged)

end
