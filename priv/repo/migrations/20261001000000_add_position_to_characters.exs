defmodule HacLong.Repo.Migrations.AddPositionToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      # vị trí trên bản đồ; nil thì đặt ở Nhà khi nạp
      add :map_id, :string
      add :x, :integer
      add :y, :integer
    end
  end
end
