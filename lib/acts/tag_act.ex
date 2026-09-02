defmodule Bonfire.Tag.Acts.Tag do
  @moduledoc """
  An act that optionally tags an object. 

  Epic Options:
    * ...

  Act Options:
    * `:on` - key to find changeset, required.
  """

  use Arrows
  use Bonfire.Common.E
  import Untangle
  import Bonfire.Epics

  alias Bonfire.Epics
  # alias Bonfire.Epics.Act
  alias Bonfire.Epics.Epic

  alias Bonfire.Common.Utils
  alias Bonfire.Common.Extend
  alias Ecto.Changeset

  def run(epic, act) do
    on = Keyword.get(act.options, :on, :post)
    changeset = epic.assigns[on]
    current_user = Bonfire.Common.Utils.current_user_or_id(epic.assigns[:options])

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
        # boundary = epic.assigns[:options][:boundary] # TODO?
        attrs_key = Keyword.get(act.options, :attrs, :post_attrs)

        attrs =
          Keyword.get(epic.assigns[:options], attrs_key, %{})
          |> debug("attrs for tagging")

        quotes_key = Keyword.get(act.options, :quotes, :quotes)

        quotes =
          (e(attrs, quotes_key, []) ++
             e(epic.assigns, quotes_key, []) ++
             Keyword.get(epic.assigns[:options], quotes_key, []))
          |> debug("possible quotes for tagging")

        # Process quotes through request system
        {approved_quotes, pending_quotes} =
          if Extend.module_enabled?(Bonfire.Social.Quotes) and quotes != [] do
            Bonfire.Social.Quotes.process_quotes(current_user, quotes,
              boundary: epic.assigns[:options][:boundary]
            )
          else
            {quotes, []}
          end
          |> debug("quote processing results")

        context_id = Keyword.get(epic.assigns[:options], :context_id, nil)

        # A reply belongs to the group its thread is in, whoever made it. The composer arranges this by mentioning the group, but an API client or an incoming federated activity does not, so derive it here: this act runs for every object type, and after `Threaded`, which has already resolved (and boundary-checked) what is being replied to.
        # No permission shortcut: the result goes through `maybe_boostable_categories/2` below like any other candidate, so an author without `:tag` on the group still boosts nothing.
        # `assigns[:reply_to]` is the object `Threaded` already resolved and boundary-checked, so
        # passing it in means nothing is fetched here for the common case.
        reply_to =
          e(epic.assigns, :reply_to, nil) ||
            e(changeset, :changes, :replied, :changes, :reply_to, nil) ||
            e(changeset, :changes, :replied, :changes, :reply_to_id, nil)

        {publish_in, epic} =
          case Utils.maybe_apply(
                 Bonfire.Social.Threads,
                 :maybe_publish_in,
                 # falls back to `context_id`, which for a reply IS the thread: it is dropped below
                 # as a boost candidate (only categories can be one), but it still answers "which
                 # group is this thread in" for anything that arrives without a `reply_to`
                 [reply_to || context_id, attrs, epic.assigns[:options] || []],
                 fallback_return: nil
               ) do
            {:ok, reply_to, group} when not is_nil(reply_to) ->
              {group, Epic.assign(epic, :reply_to, reply_to)}

            {:ok, _object, group} ->
              {group, epic}

            _ ->
              {nil, epic}
          end

        categories_auto_boost =
          (List.wrap(context_id) ++
             e(changeset, :changes, :post_content, :changes, :mentions, []) ++
             List.wrap(publish_in))
          |> Enum.uniq_by(fn
            %{id: id} -> id
            id -> id
          end)
          |> Bonfire.Social.Tags.maybe_boostable_categories(current_user, ...)
          |> maybe_debug(epic, act, ..., "categories_auto_boost")
          |> debug("categories_auto_boost")

        maybe_debug(epic, act, "tags", "Casting")

        attrs
        |> Map.update(:tags, approved_quotes, fn tags ->
          List.wrap(tags) ++ approved_quotes
        end)
        |> Bonfire.Tag.cast(changeset, ..., current_user,
          put_tree_parent: List.first(categories_auto_boost)
        )
        |> debug("cssss")
        # only add as "published in" in first mentioned category ^
        |> Epic.assign(epic, on, ...)
        |> Epic.assign(..., :categories_auto_boost, categories_auto_boost)
        # Store for later processing
        |> Epic.assign(..., :request_quotes, pending_quotes)

      changeset.action == :delete ->
        # TODO: deletion
        epic
    end
  end
end
