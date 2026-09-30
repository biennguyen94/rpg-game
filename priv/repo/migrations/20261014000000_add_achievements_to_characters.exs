defmodule HacLong.Repo.Migrations.AddAchievementsToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      add :achievements, {:array, :string}, null: false, default: []
      # danh hiệu đang dùng (id thành tựu)
      add :title, :string
    end
  end
end
