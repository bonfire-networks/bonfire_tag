defmodule Bonfire.Tag.TrendingWidgetTitleTest do
  @moduledoc "The \"Trending\" hashtag block takes its title and empty message from the `:trending_tags` vocabulary preset in use, so an instance can word it differently. None of the tests here covered the widget before."
  use Bonfire.Tag.ConnCase, async: false
  @moduletag :ui

  alias Bonfire.Common.Vocabulary

  # no trending tags exist in these tests, so the block shows its empty state
  @widget "aside[data-role=widget]"

  setup do
    account = fake_account!()
    me = fake_user!(account)

    {:ok, conn: conn(user: me, account: account)}
  end

  defp choose(preset_id), do: Process.put([:bonfire_common, Vocabulary, :trending_tags], preset_id)

  defp dashboard(conn) do
    {:ok, view, _html} = live(conn, "/dashboard")

    view |> render_async() |> Floki.parse_document!()
  end

  # the block, found by its title, since the dashboard has other widgets
  defp block(doc, title), do: Floki.find(doc, ~s(#{@widget}[aria-label="#{title}"]))

  test "without a choice the block keeps its title and empty message", %{conn: conn} do
    doc = dashboard(conn)

    assert [_] = block(doc, "Trending"), "control: the block is on the dashboard"
    assert doc |> block("Trending") |> Floki.text() =~ "Nothing trending at the moment"
  end

  # whatever the extension ships, now or later, the block shows it. The expected text comes from `Vocabulary`, so what is checked is that the widget reads it
  test "each built-in wording is the title and the empty message" do
    default_title = Vocabulary.phrase(Vocabulary.preset_for(:trending_tags, :trending_tags), :title)

    for id <- Map.keys(Vocabulary.built_in(:trending_tags)) do
      choose(id)
      preset = Vocabulary.preset(:trending_tags, nil)
      title = Vocabulary.phrase(preset, :title)

      account = fake_account!()
      doc = dashboard(conn(user: fake_user!(account), account: account))

      assert [_] = block(doc, title), "title of #{inspect(id)}"
      assert doc |> block(title) |> Floki.text() =~ Vocabulary.phrase(preset, :empty)

      if title != default_title,
        do: assert([] = block(doc, default_title), "#{inspect(id)} replaces the default's title")
    end
  end

  test "an instance's own wording is the title, and the empty message comes from its base", %{
    conn: conn
  } do
    Process.put(
      [:bonfire_common, Vocabulary, :custom_presets],
      trending_tags: %{
        school_yard: %{base: :trending_tags, title: "What do you hear in the school yard?"}
      }
    )

    choose(:school_yard)
    doc = dashboard(conn)

    assert [_] = block(doc, "What do you hear in the school yard?")

    assert doc |> block("What do you hear in the school yard?") |> Floki.text() =~
             "Nothing trending at the moment"
  end
end
