defmodule HacLong.Repo.Migrations.AddModeration do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :admin, :boolean, null: false, default: false
      # khóa tài khoản / cấm chat tới thời điểm này (nil: không bị)
      add :banned_until, :utc_datetime
      add :ban_reason, :string
      add :muted_until, :utc_datetime
    end

    # người chơi báo cáo một tin nhắn chat; nội dung lấy từ lịch sử chat trên server
    create table(:chat_reports) do
      add :reporter_id, references(:users, on_delete: :delete_all), null: false
      add :target_id, references(:users, on_delete: :delete_all), null: false
      add :text, :string, null: false
      add :resolved_at, :utc_datetime
      add :resolved_by_id, references(:users, on_delete: :nilify_all)
      add :action, :string
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:chat_reports, [:resolved_at])
    create unique_index(:chat_reports, [:reporter_id, :target_id, :text])

    # ai chặn ai (chỉ ẩn chat của người bị chặn với người chặn)
    create table(:user_blocks, primary_key: false) do
      add :user_id, references(:users, on_delete: :delete_all), null: false, primary_key: true
      add :blocked_id, references(:users, on_delete: :delete_all), null: false, primary_key: true
      timestamps(type: :utc_datetime, updated_at: false)
    end
  end
end
