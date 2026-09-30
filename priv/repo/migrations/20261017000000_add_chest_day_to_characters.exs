defmodule HacLong.Repo.Migrations.AddChestDayToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      # ngày (giờ Việt Nam) đã mở Rương Gia Truyền ở Nhà
      add :chest_day, :string
    end
  end
end
