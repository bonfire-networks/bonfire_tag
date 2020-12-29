defmodule Bonfire.Repo.Migrations.ImportQuantify do
  use Ecto.Migration

  def change do
    if Code.ensure_loaded?(Bonfire.Tag.Migrations) do
       Bonfire.Tag.Migrations.change
       Bonfire.Tag.Migrations.change_measure
    end
  end
end
