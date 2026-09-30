defmodule HacLong.Repo.Migrations.AddDailyToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      # việc hằng ngày: %{"date" => "2026-10-01", "tasks" => [...]}
      add :daily, :map
    end
  end
end
