import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :hac_long, HacLong.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "hac_long_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :hac_long, HacLongWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "B/uddAeH7UpbZT4W1w4hrpl07Jl9y3XBvyMIVQ64vFcAjIgG21gbVQGVekhDacZ/",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Băm mật khẩu nhanh trong test
config :pbkdf2_elixir, :rounds, 1

# Quái đứng yên trong test để kết quả không phụ thuộc thời gian
config :hac_long, :wander_ms, nil

# Trùm thế giới chỉ xuất hiện khi test gọi WorldBoss.spawn_now/1
config :hac_long, :world_boss,
  first_after_minutes: nil,
  every_minutes: nil,
  duration_minutes: 30,
  hp: 20_000

# sự kiện theo mùa tắt trong test (test sự kiện tự bật)
config :hac_long, :event, "none"
