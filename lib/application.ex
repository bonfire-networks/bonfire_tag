defmodule Bonfire.Tag.Application do
  use Application

  def start(_type, _args) do
    :ets.new(:mention_prefetch_inflight, [:set, :public, :named_table])
    Supervisor.start_link([], strategy: :one_for_one, name: __MODULE__)
  end
end
