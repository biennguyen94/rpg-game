# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :hac_long,
  ecto_repos: [HacLong.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :hac_long, HacLongWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: HacLongWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: HacLong.PubSub,
  live_view: [signing_salt: "KdkHwWg+"]

# Quái trên bản đồ thử bước một ô sau mỗi khoảng này (ms). nil: đứng yên.
config :hac_long, :wander_ms, 1200

# Trùm thế giới: xuất hiện lần đầu sau `first_after_minutes` phút, rồi cứ `every_minutes`
# phút một lần (tính từ lúc con trước gục hoặc bay đi), mỗi lần `duration_minutes` phút.
config :hac_long, :world_boss,
  first_after_minutes: 10,
  every_minutes: 120,
  duration_minutes: 30,
  hp: 20_000

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
