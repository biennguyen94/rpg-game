defmodule HacLong.Repo.Migrations.AddQuestsToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      # %{"active" => %{id => tiến độ}, "done" => [id]}
      add :quests, :map, null: false, default: %{"active" => %{}, "done" => []}
    end
  end
end
