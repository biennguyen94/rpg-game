defmodule HacLong.Repo.Migrations.AddGearToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      # đồ có chỉ số ngẫu nhiên: [%{uid, base, rarity, bonus}]
      add :gear, {:array, :map}, null: false, default: []
    end
  end
end
