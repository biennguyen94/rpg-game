defmodule HacLong.Repo.Migrations.CreateUsersAndCharacters do
  use Ecto.Migration

  def change do
    create table(:users) do
      # luôn lưu chữ thường để đăng nhập không phân biệt hoa thường
      add :username, :string, null: false
      add :password_hash, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:username])

    # Mỗi tài khoản có một nhân vật. Các cột khớp với trạng thái `P` của engine.
    create table(:characters) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :cls, :string, null: false
      add :level, :integer, null: false
      add :xp, :integer, null: false
      add :gold, :integer, null: false
      add :hp, :integer, null: false
      add :points, :integer, null: false
      add :stats, :map, null: false
      add :equip, :map, null: false
      add :inv, :map, null: false
      add :bosses, {:array, :string}, null: false, default: []
      add :kills, :integer, null: false, default: 0
      add :deaths, :integer, null: false, default: 0
      add :victory, :boolean, null: false, default: false

      # trận đấu đang diễn ra (nil nếu đang ở làng), lưu để thoát ra vào lại không mất trận
      add :battle, :map
      timestamps(type: :utc_datetime)
    end

    create unique_index(:characters, [:user_id])
    create index(:characters, [:level])
  end
end
