defmodule HacLong.Repo.Migrations.AddUpgradesToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      # cấp nâng cấp ở Thợ Rèn: %{id_món_đồ => cấp}
      add :upgrades, :map, null: false, default: %{}
    end
  end
end
