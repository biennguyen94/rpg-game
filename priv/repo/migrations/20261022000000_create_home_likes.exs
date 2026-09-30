defmodule HacLong.Repo.Migrations.CreateHomeLikes do
  use Ecto.Migration

  def change do
    # lượt "khen nhà": mỗi người khen nhà của một người khác tối đa một lần
    create table(:home_likes, primary_key: false) do
      add :owner_id, references(:users, on_delete: :delete_all), null: false
      add :liker_id, references(:users, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:home_likes, [:owner_id, :liker_id])
  end
end
