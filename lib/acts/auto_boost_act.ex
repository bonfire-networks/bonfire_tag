defmodule Bonfire.Tags.Acts.AutoBoost do
  @moduledoc """
  An act that optionally boosts an activity as a category. This is a way to auto-post in a category/group when tagged (and the author has permission).

  Epic Options:
    * ...

  Act Options:
    * `:on` - key to find changeset, required.
  """

  use Bonfire.Common.Utils
  alias Bonfire.Epics
  # alias Bonfire.Epics.Act
  # alias Bonfire.Epics.Epic
  import Epics

  def run(epic, act) do
    if epic.errors == [] do
      on = Keyword.get(act.options, :on, :activity)
      key = :categories_auto_boost
      categories_auto_boost = ed(epic.assigns, key, [])

      if categories_auto_boost != [] do
        maybe_debug(
          epic,
          act,
          categories_auto_boost,
          "Maybe auto-boosting to categories at assign #{key}"
        )

        case epic.assigns[on] do
          %{object: %{id: _} = object} ->
            Bonfire.Common.Utils.maybe_apply(Bonfire.Social.Tags, :auto_boost, [
              categories_auto_boost,
              object
            ])

            epic

          %{} = object ->
            Bonfire.Common.Utils.maybe_apply(Bonfire.Social.Tags, :auto_boost, [
              categories_auto_boost,
              object
            ])

            epic

          _ ->
            maybe_debug(epic, act, on, "Skipping: no activity or object at")
            epic
        end
      else
        maybe_debug(epic, act, on, "Skipping: no categories at assign #{key}")
        epic
      end
    else
      maybe_debug(act, length(epic.errors), "Skipping due to errors!")
      epic
    end
  end
end
