defmodule HacLong.Repo.Migrations.AddWaystonesToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      # các đá dịch chuyển đã ghi nhớ (id bản đồ)
      add :waystones, {:array, :string}, null: false, default: []
    end
  end
end
