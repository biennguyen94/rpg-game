defmodule HacLong.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HacLongWeb.Telemetry,
      HacLong.Repo,
      {DNSCluster, query: Application.get_env(:hac_long, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: HacLong.PubSub},
      {Registry, keys: :unique, name: HacLong.Game.Registry},
      {DynamicSupervisor, name: HacLong.Game.SessionSupervisor, strategy: :one_for_one},
      # Start to serve requests, typically the last entry
      HacLongWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HacLong.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HacLongWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
