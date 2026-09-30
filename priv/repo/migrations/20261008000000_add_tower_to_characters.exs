defmodule HacLong.Repo.Migrations.AddTowerToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      # lượt leo Tháp Vô Tận đang dở (nil nếu không ở trong tháp) và tầng cao nhất đã vượt
      add :tower, :map
      add :tower_best, :integer, null: false, default: 0
    end

    create index(:characters, [:tower_best])
  end
end
