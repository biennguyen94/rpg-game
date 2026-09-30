defmodule HacLong.Repo.Migrations.AddPetsAndDecorToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      # thú cưng đang dắt theo và các con đã mua
      add :pet, :string
      add :pets, {:array, :string}, null: false, default: []
      # đồ trang trí còn trong kho (%{id => số}) và đã đặt trong nhà ([%{id, x, y}])
      add :furniture, :map, null: false, default: %{}
      add :decor, {:array, :map}, null: false, default: []
    end
  end
end
