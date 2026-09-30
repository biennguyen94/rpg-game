defmodule HacLong.Repo.Migrations.CreateMails do
  use Ecto.Migration

  def change do
    # hộp thư: thư hệ thống kèm quà (vàng, kinh nghiệm, đồ)
    create table(:mails) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :subject, :string, null: false
      add :body, :text, null: false, default: ""
      add :gold, :integer, null: false, default: 0
      add :xp, :integer, null: false, default: 0
      add :items, :map, null: false, default: %{}
      # đã mở/nhận quà (nil: chưa)
      add :claimed_at, :utc_datetime
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:mails, [:user_id, :inserted_at])
  end
end
