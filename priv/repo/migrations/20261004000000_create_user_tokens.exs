defmodule HacLong.Repo.Migrations.CreateUserTokens do
  use Ecto.Migration

  def change do
    # Token đăng nhập: chỉ lưu mã băm SHA-256, xóa dòng là thu hồi token.
    create table(:user_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token_hash, :binary, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:user_tokens, [:token_hash])
    create index(:user_tokens, [:user_id])
  end
end
