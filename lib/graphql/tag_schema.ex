# SPDX-License-Identifier: AGPL-3.0-only
if Bonfire.Common.Extend.module_enabled?(Bonfire.API.GraphQL) do
  defmodule Bonfire.Tag.GraphQL.TagSchema do
    use Absinthe.Schema.Notation

    alias Bonfire.Tag.GraphQL.TagResolver

    object :tag_queries do
      @desc "Get a tag by ID "
      field :tag, :tag do
        arg(:id, :id)
        # arg :find, :category_find
        resolve(&TagResolver.tag/2)
      end
    end

    object :tag_mutations do
      @desc "Tag a thing (using a Pointer) with one or more Tags (or Categories, or even Pointers to anything that can become tag)"
      field :tag, :boolean do
        arg(:thing, non_null(:string))
        arg(:tags, non_null(list_of(:string)))
        resolve(&TagResolver.tag_something/2)
      end
    end

    @desc "A tag could be a category or hashtag or user or community or etc"
    object :tag do
      @desc "The primary key of the tag"
      field(:id, :id)

      @desc "The object used as a tag (eg. Category, Geolocation, Hashtag, User...)"
      field :context, :any_context do
        resolve(&Bonfire.API.GraphQL.CommonResolver.context_edge/3)
      end

      @desc "Name of the tag (derived from its context)"
      field(:name, :string) do
        resolve(&TagResolver.name/3)
      end

      @desc "Description of the tag (derived from its context)"
      field(:summary, :string) do
        resolve(&TagResolver.summary/3)
      end

      @desc "Unique URL (on original instance)"
      field(:canonical_url, :string) do
        resolve(&Bonfire.API.GraphQL.CommonResolver.canonical_url_edge/3)
      end

      @desc "Unique URL (on original instance)"
      field(:display_username, :string) do
        resolve(&Bonfire.API.GraphQL.CommonResolver.display_username_edge/3)
      end

      @desc "Objects that were tagged with this tag"
      field(:tagged, list_of(:any_context)) do
        resolve(&TagResolver.tagged_things_edges/3)
      end
    end
  end
end
