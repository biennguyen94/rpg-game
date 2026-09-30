defmodule HacLong.Repo.Migrations.AddFoodCraftingFestivalAndFriends do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      # món ăn đang có tác dụng: %{id, left} (còn bao nhiêu trận)
      add :food, :map
      # kinh nghiệm nghề: %{"cook" => số, "smith" => số}
      add :crafting, :map, null: false, default: %{}
      # số lần đổi quà ở lễ hội (cho thành tựu)
      add :festival, :integer, null: false, default: 0
    end

    # bạn bè: một dòng mỗi chiều; accepted = false là lời mời kết bạn từ user_id tới friend_id
    create table(:friends, primary_key: false) do
      add :user_id, references(:users, on_delete: :delete_all), primary_key: true
      add :friend_id, references(:users, on_delete: :delete_all), primary_key: true
      add :accepted, :boolean, null: false, default: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:friends, [:friend_id])

    create table(:private_messages) do
      add :from_id, references(:users, on_delete: :delete_all), null: false
      add :to_id, references(:users, on_delete: :delete_all), null: false
      add :text, :string, null: false
      add :read_at, :utc_datetime
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:private_messages, [:to_id, :from_id, :id])
    create index(:private_messages, [:from_id, :to_id, :id])
  end
end
