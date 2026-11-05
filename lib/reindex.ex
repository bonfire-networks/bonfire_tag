defmodule Bonfire.Tag.Reindex do
  @moduledoc """
  (Re)indexes hashtags into the search index, in batches.

  Implements `EctoSparkles.DataMigration` (so it reuses the batched, keyset-paginated, throttled runner) and registers as a `Bonfire.Common.ReindexModule` so it runs as part of a full search backfill via `Bonfire.Search.Indexer.reindex_from_db/1`. Needed for hashtags made before search was on, or before hashtags were indexed.
  """
  @behaviour EctoSparkles.DataMigration
  @behaviour Bonfire.Common.ReindexModule
  import Ecto.Query
  alias EctoSparkles.DataMigration

  @impl Bonfire.Common.ReindexModule
  def reindex_module, do: __MODULE__

  @impl Bonfire.Common.ReindexModule
  def reindex(opts \\ []), do: DataMigration.Runner.run(__MODULE__, opts)

  @impl DataMigration
  def base_query(_opts \\ []) do
    from(h in Bonfire.Tag.Hashtag, as: :main_object)
  end

  @impl DataMigration
  def config do
    # `first_id`: lowest ULID string (Needle.UID-castable), see Bonfire.Me.Users.Reindex.
    %DataMigration.Config{
      batch_size: 100,
      throttle_ms: 1000,
      repo: Bonfire.Common.Repo,
      first_id: "00000000000000000000000000"
    }
  end

  @impl DataMigration
  def migrate(hashtags) do
    hashtags
    |> Bonfire.Common.Repo.maybe_preload(:named)
    |> Enum.each(&Bonfire.Tag.maybe_index_hashtag/1)
  end
end
