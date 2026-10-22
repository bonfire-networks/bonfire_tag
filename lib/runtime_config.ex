defmodule Bonfire.Tag.RuntimeConfig do
  use Bonfire.Common.Localise

  @behaviour Bonfire.Common.ConfigModule
  def config_module, do: true

  @doc """
  NOTE: you can override this default config in your app's `runtime.exs`, by placing similarly-named config keys below the `Bonfire.Common.Config.LoadExtensionsConfig.load_configs()` line
  """
  def config do
    import Config

    # How the "Trending" hashtag block words itself. `module:` makes this extension's gettext domain the one the phrases are looked up in, which is where `l/1` extracts them (and where the old strings were translated)
    config :bonfire_common, Bonfire.Common.Vocabulary,
      kinds: [
        trending_tags: [
          module: __MODULE__,
          presets: %{
            trending_tags: %{
              title: l("Trending"),
              empty: l("Nothing trending at the moment")
            },
            buzzing: %{
              title: l("What is buzzing"),
              empty: l("Nothing is buzzing yet")
            }
          }
        ]
      ]
  end
end
