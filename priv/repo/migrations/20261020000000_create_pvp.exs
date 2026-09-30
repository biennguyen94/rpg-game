defmodule HacLong.Repo.Migrations.CreatePvp do
  use Ecto.Migration

  def change do
    # điểm đấu trường (Elo); để riêng khỏi bảng characters vì người bị thách đấu có thể đang
    # online và Session của họ ghi đè cả dòng nhân vật
    create table(:pvp, primary_key: false) do
      add :user_id, references(:users, on_delete: :delete_all), primary_key: true
      add :rating, :integer, null: false, default: 1000
      add :wins, :integer, null: false, default: 0
      add :losses, :integer, null: false, default: 0
      # số trận đã đấu trong ngày `day` (giờ Việt Nam)
      add :day, :string
      add :today, :integer, null: false, default: 0
    end

    create index(:pvp, [:rating])
  end
end
