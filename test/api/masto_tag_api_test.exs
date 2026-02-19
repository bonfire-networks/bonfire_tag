# SPDX-License-Identifier: AGPL-3.0-only
if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.Tag.Web.MastoTagApiTest do
    @moduledoc """
    Tests for Mastodon-compatible Tags API endpoints.

    Run with: just test extensions/bonfire_tag/test/api/masto_tag_api_test.exs
    """

    use Bonfire.Tag.ConnCase, async: false

    alias Bonfire.Me.Fake
    alias Bonfire.Social.Graph.Follows
    alias Bonfire.Tag

    @moduletag :masto_api

    setup do
      account = Fake.fake_account!()
      user = Fake.fake_user!(account)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(%{})
        |> Plug.Conn.put_session(:current_user_id, user.id)
        |> Plug.Conn.put_session(:current_account_id, account.id)
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")

      {:ok, conn: conn, user: user, account: account}
    end

    defp unauthenticated_conn do
      Phoenix.ConnTest.build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
    end

    describe "GET /api/v1/tags/:name" do
      test "returns Mastodon-compatible tag format", %{conn: conn} do
        {:ok, hashtag} = Tag.get_or_create_hashtag("testtag")

        response =
          conn
          |> get("/api/v1/tags/testtag")
          |> json_response(200)

        assert response["name"] == "testtag"
        assert response["id"] == to_string(hashtag.id)
        assert String.contains?(response["url"], "/pub/tags/testtag")
        assert response["history"] == []
        assert response["following"] == false
      end

      test "returns 404 for non-existent hashtag", %{conn: conn} do
        response =
          conn
          |> get("/api/v1/tags/surely_nonexistent_#{System.unique_integer([:positive])}")
          |> json_response(404)

        assert response["error"] == "Not found"
      end

      test "reflects follow status for current user", %{conn: conn, user: user} do
        {:ok, hashtag} = Tag.get_or_create_hashtag("status_check")

        # Before following
        response = conn |> get("/api/v1/tags/status_check") |> json_response(200)
        assert response["following"] == false

        # After following (direct call needs skip_boundary_check for test setup)
        {:ok, _} = Follows.follow(user, hashtag, skip_boundary_check: true)
        response = conn |> get("/api/v1/tags/status_check") |> json_response(200)
        assert response["following"] == true
      end
    end

    describe "POST /api/v1/tags/:name/follow" do
      test "establishes follow and returns tag", %{conn: conn, user: user} do
        {:ok, hashtag} = Tag.get_or_create_hashtag("to_follow")
        refute Follows.following?(user, hashtag)

        response =
          conn
          |> post("/api/v1/tags/to_follow/follow")
          |> json_response(200)

        assert response["name"] == "to_follow"
        assert response["following"] == true
        assert Follows.following?(user, hashtag)
      end

      test "creates hashtag on-demand when following", %{conn: conn, user: user} do
        tag_name = "brand_new_#{System.unique_integer([:positive])}"
        assert {:error, :not_found} = Tag.get_hashtag(tag_name)

        response =
          conn
          |> post("/api/v1/tags/#{tag_name}/follow")
          |> json_response(200)

        assert response["name"] == tag_name
        {:ok, hashtag} = Tag.get_hashtag(tag_name)
        assert Follows.following?(user, hashtag)
      end

      test "requires authentication", _context do
        response =
          unauthenticated_conn()
          |> post("/api/v1/tags/anytag/follow")
          |> json_response(401)

        assert response["error"] == "You need to login first."
      end
    end

    describe "POST /api/v1/tags/:name/unfollow" do
      test "removes follow and returns tag", %{conn: conn, user: user} do
        {:ok, hashtag} = Tag.get_or_create_hashtag("to_unfollow")
        {:ok, _} = Follows.follow(user, hashtag, skip_boundary_check: true)
        assert Follows.following?(user, hashtag)

        response =
          conn
          |> post("/api/v1/tags/to_unfollow/unfollow")
          |> json_response(200)

        assert response["name"] == "to_unfollow"
        assert response["following"] == false
        refute Follows.following?(user, hashtag)
      end

      test "returns 404 for non-existent hashtag", %{conn: conn} do
        conn
        |> post("/api/v1/tags/surely_nonexistent_#{System.unique_integer([:positive])}/unfollow")
        |> json_response(404)
      end

      test "requires authentication", _context do
        response =
          unauthenticated_conn()
          |> post("/api/v1/tags/anytag/unfollow")
          |> json_response(401)

        assert response["error"] == "You need to login first."
      end
    end

    describe "GET /api/v1/followed_tags" do
      test "returns only hashtags followed by current user", %{conn: conn, user: user} do
        {:ok, tag1} = Tag.get_or_create_hashtag("mine1")
        {:ok, tag2} = Tag.get_or_create_hashtag("mine2")
        {:ok, _not_mine} = Tag.get_or_create_hashtag("not_mine")
        {:ok, _} = Follows.follow(user, tag1, skip_boundary_check: true)
        {:ok, _} = Follows.follow(user, tag2, skip_boundary_check: true)

        response =
          conn
          |> get("/api/v1/followed_tags")
          |> json_response(200)

        names = Enum.map(response, & &1["name"])
        assert "mine1" in names
        assert "mine2" in names
        refute "not_mine" in names

        Enum.each(response, fn tag ->
          assert tag["following"] == true
          assert String.contains?(tag["url"], "/pub/tags/")
        end)
      end

      test "returns empty list for user with no followed tags", %{conn: conn} do
        response =
          conn
          |> get("/api/v1/followed_tags")
          |> json_response(200)

        assert response == []
      end

      test "requires authentication", _context do
        response =
          unauthenticated_conn()
          |> get("/api/v1/followed_tags")
          |> json_response(401)

        assert response["error"] == "You need to login first."
      end
    end

    describe "GET /api/v1/featured_tags" do
      test "returns empty list when no featured tags", %{conn: conn} do
        response =
          conn
          |> get("/api/v1/featured_tags")
          |> json_response(200)

        assert response == []
      end

      # TODO: Re-enable once Pins.pin supports skip_federation option
      # Currently disabled because Pins.pin always tries to federate but
      # there's no federation handler for pins
      @tag :skip
      test "returns featured tags after pinning", %{conn: conn, user: _user} do
        flunk("Test disabled - feature_tag endpoint not yet implemented")
      end

      test "requires authentication", _context do
        response =
          unauthenticated_conn()
          |> get("/api/v1/featured_tags")
          |> json_response(401)

        assert response["error"] == "You need to login first."
      end
    end

    describe "GET /api/v1/accounts/:id/featured_tags" do
      test "returns featured tags for target user", %{conn: conn} do
        other_account = Fake.fake_account!()
        other_user = Fake.fake_user!(other_account)

        response =
          conn
          |> get("/api/v1/accounts/#{other_user.id}/featured_tags")
          |> json_response(200)

        assert is_list(response)
      end

      test "returns 404 for non-existent user", %{conn: conn} do
        response =
          conn
          |> get("/api/v1/accounts/#{Needle.ULID.generate()}/featured_tags")
          |> json_response(404)

        assert response["error"]
      end
    end

    # TODO: Feature/unfeature endpoints are disabled until Pins.pin supports
    # skip_federation option. See graphql_masto_adapter.ex for details.
    describe "POST /api/v1/featured_tags" do
      test "returns not implemented error", %{conn: conn} do
        response =
          conn
          |> post("/api/v1/featured_tags", %{"name" => "newfeature"})
          |> json_response(400)

        assert response["error"] =~ "not yet implemented"
      end

      test "requires authentication", _context do
        response =
          unauthenticated_conn()
          |> post("/api/v1/featured_tags", Jason.encode!(%{"name" => "test"}))
          |> json_response(401)

        assert response["error"] == "You need to login first."
      end
    end

    describe "DELETE /api/v1/featured_tags/:id" do
      test "returns not implemented error", %{conn: conn} do
        conn
        |> delete("/api/v1/featured_tags/someid")
        |> json_response(400)
      end

      test "returns not implemented error for any id", %{conn: conn} do
        response =
          conn
          |> delete("/api/v1/featured_tags/#{Needle.ULID.generate()}")
          |> json_response(400)

        assert response["error"] =~ "not yet implemented"
      end
    end
  end
end
