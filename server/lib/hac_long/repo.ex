defmodule HacLong.Repo do
  use Ecto.Repo,
    otp_app: :hac_long,
    adapter: Ecto.Adapters.Postgres
end
