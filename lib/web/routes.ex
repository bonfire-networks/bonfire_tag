defmodule Bonfire.Tag.Web.Routes do
  defmacro __using__(_) do

    quote do

      # pages anyone can view
      scope "/", Bonfire.Tag.Web do
        pipe_through :browser

        live "/tags/autocomplete", Pages.Autocomplete

      end

      # pages you need an account to view
      scope "/", Bonfire.Tag.Web do
        pipe_through :browser
        pipe_through :account_required

      end

      # pages you need to view as a user
      scope "/", Bonfire.Tag.Web do
        pipe_through :browser
        pipe_through :user_required


      end

    end
  end
end
