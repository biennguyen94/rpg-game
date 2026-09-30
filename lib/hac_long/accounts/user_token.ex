defmodule HacLong.Accounts.UserToken do
  use Ecto.Schema

  schema "user_tokens" do
    belongs_to :user, HacLong.Accounts.User
    field :token_hash, :binary
    timestamps(type: :utc_datetime, updated_at: false)
  end
end
