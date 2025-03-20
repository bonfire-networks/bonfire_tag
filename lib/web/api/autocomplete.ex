defmodule Bonfire.Tag.Web.API.Autocomplete do
  use Bonfire.UI.Common.Web, :controller

  alias Bonfire.Tag.Autocomplete
  import Untangle

  def get(conn, %{
        "prefix" => prefix,
        "search" => search,
        "consumer" => consumer
      }) do
    tags = search_with_meili(search, prefix, consumer)
    json(conn, prepare(tags))
  end

  def get(conn, %{"prefix" => prefix, "search" => search}) do
    tags = search_with_meili(search, prefix, "tag_as")
    json(conn, prepare(tags))
  end

  # Enhanced function that uses Meilisearch search with proper preloading
  defp search_with_meili(search, prefix, consumer) do
    if module_enabled?(Bonfire.Search) and Bonfire.Search.adapter() do
      # First try to use Meilisearch
      debug("Using Meilisearch for autocomplete search: #{search}")

      # Determine the facet filters based on prefix
      index_type = Autocomplete.prefix_index(prefix)

      # Set search options with specific preloading for user profile data
      opts = %{
        limit: 10,
        current_user: nil
      }

      # Perform the search with Meilisearch
      search_results = Bonfire.Search.search_by_type(search, index_type)

      # Format the results for the autocomplete
      if is_list(search_results) and length(search_results) > 0 do
        # Process search results with enhanced preloading
        enhanced_results =
          search_results
          |> Bonfire.Social.Activities.activity_preloads(
              [:with_subject, :with_object],  # Add these preloads to ensure username, name, icon
              opts
            )
          |> repo().maybe_preload([:character, profile: :icon]) # Directly preload profile data when needed
          |> debug("Search results with preloaded user data")

        # Prepare each hit for the autocomplete UI
        enhanced_results
        |> Enum.map(fn hit ->
          Autocomplete.tag_hit_prepare(hit, search, prefix, consumer)
        end)
        |> Enums.filter_empty([])
      else
        # Fallback to original method if no results
        debug("No Meilisearch results, falling back to original lookup method")
        Autocomplete.api_tag_lookup(search, prefix, consumer)
      end
    else
      # Fallback to original method if Meilisearch is not available
      debug("Meilisearch not available, using original lookup method")
      Autocomplete.api_tag_lookup(search, prefix, consumer)
    end
  end

  def prepare({key, val} = tags) when is_tuple(tags) do
    %{key => val}
  end

  def prepare(tags) do
    tags
  end
end
