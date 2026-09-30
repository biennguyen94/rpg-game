defmodule HacLong.Repo.Migrations.CreateGuilds do
  use Ecto.Migration

  def change do
    create table(:guilds) do
      add :name, :string, null: false
      # tên chuẩn hóa (chữ thường) để không trùng
      add :name_key, :string, null: false
      # ký hiệu 2–4 chữ in hoa, hiện cạnh tên thành viên
      add :tag, :string, null: false
      add :leader_id, references(:users, on_delete: :nilify_all)
      # tổng vàng đã góp (quyết định cấp bang)
      add :fund, :integer, null: false, default: 0
      # ai cũng vào được ngay, hay phải xin
      add :open, :boolean, null: false, default: true
      add :notice, :string, null: false, default: ""
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:guilds, [:name_key])
    create unique_index(:guilds, [:tag])
    create index(:guilds, [:fund])

    create table(:guild_members, primary_key: false) do
      add :user_id, references(:users, on_delete: :delete_all), primary_key: true
      add :guild_id, references(:guilds, on_delete: :delete_all), null: false
      # leader | officer | member
      add :role, :string, null: false, default: "member"
      add :contributed, :integer, null: false, default: 0
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:guild_members, [:guild_id])

    create table(:guild_requests, primary_key: false) do
      add :user_id, references(:users, on_delete: :delete_all), primary_key: true
      add :guild_id, references(:guilds, on_delete: :delete_all), primary_key: true
      timestamps(type: :utc_datetime, updated_at: false)
    end
  end
end
