# SPDX-License-Identifier: AGPL-3.0-only
if Code.ensure_loaded?(Bonfire.API.GraphQL) do
  defmodule Bonfire.Tag.GraphQL.TagResolver do
    @moduledoc "GraphQL tag/category queries"
    import Bonfire.Common.Config, only: [repo: 0]
    use Bonfire.Common.Utils

    alias Bonfire.API.GraphQL

    # FetchFields,
    # FetchPage,
    # FetchPages,
    alias Bonfire.API.GraphQL.ResolveField

    # ResolveFields,
    # ResolvePage,
    # ResolvePages,
    # ResolveRootPage
    alias Bonfire.Tag
    alias Bonfire.Tag

    import Untangle

    if Code.ensure_loaded?(ResolveField) do
      def tag(%{id: id}, info) do
        ResolveField.run(%ResolveField{
          module: __MODULE__,
          fetcher: :fetch_tag,
          context: id,
          info: info
        })
      end
    end

    ## fetchers

    def fetch_tag(_info, id) do
      Tags.one(id: id)
    end

    @doc """
    Things associated with a Tag
    """
    def tagged_things_edges(%{tagged: _things} = tag, %{} = page_opts, info) do
      tag = repo().maybe_preload(tag, :tagged)
      # pointers = for %{id: tid} <- tag.tagged, do: tid
      pointers =
        Utils.e(tag, :tagged, %{})
        |> Enum.map(fn a -> a.id end)

      # |> Map.new()

      Bonfire.API.GraphQL.CommonResolver.context_edges(
        %{context_ids: pointers},
        page_opts,
        info
      )
    end

    @doc """
    Tags associated with a Thing
    """
    def tags_edges(%{tags: _tags} = thing, page_opts, info) do
      # thing = repo().maybe_preload(thing, :tags)
      thing = repo().maybe_preload(thing, tags: [:category, :profile, :character])

      # IO.inspect(tags_edges_thing: thing)

      # |> IO.inspect()
      tags =
        thing
        |> Map.get(:tags, [])
        |> Enum.map(&tag_prepare(&1, page_opts, info))

      {:ok, tags}
    end

    def tags_edges(_, _, _) do
      warn("no tags")
      {:ok, nil}
    end

    def tag_prepare(%{category: %{id: id} = category} = tag, _page_opts, _info)
        when not is_nil(id) do
      Map.merge(
        category,
        %{
          name: e(tag, :profile, :name, nil),
          summary: e(tag, :profile, :summary, nil),
          character: e(tag, :character, nil),
          profile: e(tag, :profile, nil)
        }
      )

      # |> IO.inspect
    end

    def tag_prepare(%{profile: %{name: name}} = tag, page_opts, info)
        when not is_nil(name) do
      Map.merge(
        tag,
        %{
          name: name,
          summary: e(tag, :profile, :summary, nil)
        }
      )
    end

    def tag_prepare(%{category_id: category_id, id: mixin_id}, page_opts, info)
        when is_nil(category_id) do
      Bonfire.API.GraphQL.CommonResolver.context_edge(
        %{context_id: mixin_id},
        page_opts,
        info
      )
    end

    #### MUTATIONS

    def tag_something(%{thing: thing_id, tags: tags}, info) do
      with {:ok, me} <- GraphQL.current_user_or_not_logged_in(info),
           {:ok, _tagged} = Bonfire.Tag.tag_something(me, thing_id, tags) do
        {:ok, true}
      end
    end

    ### decorators

    def name(%{profile: %{name: name}}, _, _info) when not is_nil(name) do
      {:ok, name}
    end

    def name(%{name: name}, _, _info) when not is_nil(name) do
      {:ok, name}
    end

    # def name(%{name: name, context_id: context_id}, _, _info)
    #     when is_nil(name) and not is_nil(context_id) do

    #   # TODO: optimise so it doesn't repeat these queries (for context and summary fields)
    #   with {:ok, context} <- Bonfire.Common.Needles.get(context_id, current_user: user) do
    #     name = if Map.has_key?(context, :name), do: context.name
    #     {:ok, name}
    #   end
    # end

    def name(_, _, _) do
      {:ok, nil}
    end

    def summary(%{profile: %{summary: summary}}, _, _info)
        when not is_nil(summary) do
      {:ok, summary}
    end

    def summary(%{summary: summary}, _, _info) when not is_nil(summary) do
      {:ok, summary}
    end

    # def summary(%{summary: summary, context_id: context_id}, _, _info)
    #     when is_nil(summary) and not is_nil(context_id) do

    #   # TODO: optimise so it doesn't repeat these queries (for context and summary fields)
    #   with {:ok, context} <- Bonfire.Common.Needles.get(context_id, current_user: user) do
    #     summary = if Map.has_key?(context, :summary), do: context.summary
    #     {:ok, summary}
    #   end
    # end

    def summary(_, _, _) do
      {:ok, nil}
    end

    # def tag(%{tag_id: id}, info) do
    #   {:ok, Simulate.tag()}
    #   |> GraphQL.response(info)
    # end

    # def delete_tag(%{id: id}, info) do
    #   with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info),
    #        {:ok, c} <- tag(%{id: id}, info),
    #        :ok <- ensure_delete_allowed(user, c),
    #        {:ok, c} <- Categories.soft_delete(c, user) do
    #     {:ok, true}
    #   end
    # end

    # def ensure_delete_allowed(user, c) do
    #   if user.local_user.is_instance_admin or c.creator_id == user.id do
    #     :ok
    #   else
    #     GraphQL.not_permitted("delete")
    #   end
    # end
  end
end
