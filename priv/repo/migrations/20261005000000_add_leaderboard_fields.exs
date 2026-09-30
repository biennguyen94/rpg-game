defmodule HacLong.Repo.Migrations.AddLeaderboardFields do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      # lúc hạ Hắc Long lần đầu, cho bảng "Diệt rồng" (ai hạ trước xếp trên)
      add :victory_at, :utc_datetime
    end

    create index(:characters, [:level, :xp])
    create index(:characters, [:kills])
    create index(:characters, [:victory_at])
  end
end
