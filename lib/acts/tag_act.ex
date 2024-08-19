defmodule Bonfire.Tag.Acts.Tag do
  @moduledoc """
  An act that optionally tags an object. 

  Epic Options:
    * ...

  Act Options:
    * `:on` - key to find changeset, required.
  """

  alias Bonfire.Epics
  # alias Bonfire.Epics.Act
  alias Bonfire.Epics.Epic

  alias Bonfire.Common.Utils
  alias Ecto.Changeset
  import Epics
  use Arrows

  def run(epic, act) do
    on = Keyword.get(act.options, :on, :post)
    changeset = epic.assigns[on]
    current_user = Bonfire.Common.Utils.current_user(epic.assigns[:options])

    cond do
      epic.errors != [] ->
        maybe_debug(
          epic,
          act,
          length(epic.errors),
          "Skipping due to epic errors"
        )

        epic

      is_nil(on) or not is_atom(on) ->
        maybe_debug(epic, act, on, "Skipping due to `on` option")
        epic

      not (is_struct(current_user) or is_binary(current_user)) ->
        maybe_debug(
          epic,
          act,
          current_user,
          "Skipping due to missing current_user"
        )

        epic

      not is_struct(changeset) || changeset.__struct__ != Changeset ->
        maybe_debug(epic, act, changeset, "Skipping :#{on} due to changeset")
        epic

      changeset.action not in [:insert, :upsert, :delete] ->
        maybe_debug(
          epic,
          act,
          changeset.action,
          "Skipping, no matching action on changeset"
        )

        epic

      changeset.action in [:insert, :upsert] ->
        # boundary = epic.assigns[:options][:boundary] # TODO?
        attrs_key = Keyword.get(act.options, :attrs, :post_attrs)
        attrs = Keyword.get(epic.assigns[:options], attrs_key, %{})

        categories_auto_boost =
          Utils.e(changeset, :changes, :post_content, :changes, :mentions, [])
          |> Bonfire.Social.Tags.maybe_boostable_categories(current_user, ...)
          |> maybe_debug(epic, act, ..., "categories_auto_boost")

        maybe_debug(epic, act, "tags", "Casting")

        changeset
        |> Bonfire.Tag.cast(attrs, current_user,
          put_tree_parent: List.first(categories_auto_boost)
        )
        # only add as "published in" in first mentioned category ^
        |> Epic.assign(epic, on, ...)
        |> Epic.assign(..., :categories_auto_boost, categories_auto_boost)

      changeset.action == :delete ->
        # TODO: deletion
        epic
    end
  end
end
