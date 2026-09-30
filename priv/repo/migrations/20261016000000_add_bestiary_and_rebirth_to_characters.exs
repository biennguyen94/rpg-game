defmodule HacLong.Repo.Migrations.AddBestiaryAndRebirthToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      # sổ tay quái vật: %{id_quái => số con đã hạ}
      add :bestiary, :map, null: false, default: %{}
      # số lần chuyển sinh
      add :rebirths, :integer, null: false, default: 0
    end

    create index(:characters, [:rebirths, :level, :xp])
  end
end
