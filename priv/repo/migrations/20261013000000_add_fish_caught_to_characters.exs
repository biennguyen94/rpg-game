defmodule HacLong.Repo.Migrations.AddFishCaughtToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      add :fish_caught, :integer, null: false, default: 0
    end
  end
end
