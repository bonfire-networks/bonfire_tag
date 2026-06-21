defmodule Bonfire.Tag.HashtagTest do
  use ExUnit.Case, async: true
  alias Bonfire.Tag.Hashtag

  describe "normalize_name/1 should" do
    test "normalize different casings of the same hashtag to one name" do
      assert Hashtag.normalize_name("#Testing") == "testing"
      assert Hashtag.normalize_name("#testing") == "testing"
      assert Hashtag.normalize_name("#Testing") == Hashtag.normalize_name("#testing")
    end

    test "trim whitespace, strip the leading #, downcase, and replace spaces" do
      assert Hashtag.normalize_name("  #Hello World ") == "hello_world"
    end

    test "leave an already-lowercase hashtag unchanged" do
      assert Hashtag.normalize_name("#elixir") == "elixir"
    end
  end
end
