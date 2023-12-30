# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.Tag.Queries do
  import Ecto.Query

  alias Needle.Pointer, as: Tag
  alias Bonfire.Tag.Tagged
  alias Bonfire.Common.Utils
  alias Bonfire.Common.Types

  def query(Tag) do
    from(t in Tag,
      as: :tag

      # left_join: c in assoc(t, :character),
      # as: :character
    )
  end

  def query(:count) do
    from(c in Tag, as: :tag)
  end

  def query(pointable) when is_atom(pointable) do
    from(t in pointable,
      as: :tag

      # left_join: c in assoc(t, :character),
      # as: :character
    )
  end

  def query(filters) when is_list(filters), do: query(Tag, filters)

  def query(q, filters), do: filter(query(q), filters)

  def queries(query, base_filters, data_filters, count_filters) do
    base_q = query(query, base_filters)
    data_q = filter(base_q, data_filters)
    count_q = filter(base_q, count_filters)
    {data_q, count_q}
  end

  def join_to(q, table_or_tables, jq \\ :left)

  ## many

  def join_to(q, tables, jq) when is_list(tables) do
    Enum.reduce(tables, q, &join_to(&2, &1, jq))
  end

  def join_to(q, :profile, jq) do
    join(q, jq, [tag: c], t in assoc(c, :profile), as: :profile)
  end

  def join_to(q, :character, jq) do
    join(q, jq, [tag: c], t in assoc(c, :character), as: :character)
  end

  def join_to(q, :category, jq) do
    join(q, jq, [tag: c], t in assoc(c, :category), as: :category)
  end

  @doc "Filter the query according to arbitrary criteria"
  def filter(q, filter_or_filters)

  ## many

  def filter(q, filters) when is_list(filters) do
    Enum.reduce(filters, q, &filter(&2, &1))
  end

  ## by join

  def filter(q, {:join, {rel, jq}}), do: join_to(q, rel, jq)

  def filter(q, {:join, rel}), do: join_to(q, rel)

  ## by field values

  def filter(q, {:id, id}) when is_binary(id) do
    where(q, [tag: f], f.id == ^id)
  end

  def filter(q, {:id, ids}) when is_list(ids) do
    where(q, [tag: f], f.id in ^ids)
  end

  def filter(q, {:id, id}) when is_binary(id),
    do: where(q, [tag: c], c.id == ^id)

  def filter(q, {:id, ids}) when is_list(ids),
    do: where(q, [tag: c], c.id in ^ids)

  def filter(q, {:type, types}) when is_list(types) or is_atom(types) do
    table_ids =
      List.wrap(types)
      |> Enum.map(&Utils.maybe_apply(&1, :__pointers__, :table_id))

    where(q, [tag], tag.table_id in ^Types.ulids(table_ids))
  end

  def filter(q, {:username, username}) when is_binary(username) do
    q
    |> join_to(:character)
    |> preload(:character)
    |> where([character: a], a.username == ^username)
  end

  def filter(q, {:username, usernames}) when is_list(usernames) do
    q
    |> join_to(:character)
    |> preload(:character)
    |> where([character: a], a.username in ^usernames)
  end

  def filter(q, {:name, name}) when is_binary(name) do
    where(
      q,
      [a],
      # a.name == ^name
      ilike(a.name, ^name)
    )
  end

  def filter(q, {:name, name}) when is_list(name) do
    where(q, [a], a.name in ^name)
  end

  def filter(q, {:autocomplete, text}) when is_binary(text) do
    q
    # exclude soft-deleted categories
    |> filter(:deleted)
    |> join_to(:profile)
    |> preload(:profile)
    |> join_to(:character)
    |> preload(:character)
    |> where(
      [profile: p, character: a],
      a.username == ^text or
        p.name == ^text or
        ilike(p.name, ^"#{text}%") or
        ilike(p.name, ^"% #{text}%") or
        ilike(a.username, ^"#{text}%") or
        ilike(a.username, ^"% #{text}%")
    )
  end

  def filter(q, :deleted) do
    if Bonfire.Common.Extend.module_enabled?(Bonfire.Classify.Category) do
      q
      |> join_to(:category)
      |> where([category: o], is_nil(o.deleted_at))
    else
      q
    end
  end

  def filter(q, {:user, _user}), do: q

  # pagination

  def filter(q, {:limit, limit}), do: limit(q, ^limit)

  def filter(q, {:order, [asc: :id]}), do: order_by(q, [tag: r], asc: r.id)
  def filter(q, {:order, [desc: :id]}), do: order_by(q, [tag: r], desc: r.id)

  def list_trending(since_date, exclude_table_ids \\ [], limit \\ 10) do
    from(tagged in Tagged,
      left_join: tag in assoc(tagged, :tag),
      # left_join: object in assoc(tagged, :pointer),
      group_by: tagged.tag_id,
      select: %{tag_id: tagged.tag_id, count: count(tagged.id)},
      where: tag.table_id not in ^exclude_table_ids,
      where: tagged.inserted_at >= ^since_date,
      order_by: [desc: :count],
      limit: ^limit

      # preload: [tag: tag]
    )
  end
end
