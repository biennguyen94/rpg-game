defmodule HacLong.Repo.Migrations.UniqueCharacterNames do
  use Ecto.Migration

  # Tên nhân vật không được trùng (không phân biệt hoa thường). `name_key` là tên đã chuẩn
  # hóa, do ứng dụng tính (xem HacLong.Game.Names.key/1). Tên đang trùng thì người tạo sau
  # được thêm số ở cuối.
  def up do
    alter table(:characters) do
      add :name_key, :string
    end

    flush()

    execute "UPDATE characters SET name_key = lower(regexp_replace(btrim(name), '\\s+', ' ', 'g'))"

    execute """
    UPDATE characters c
    SET name = left(c.name, 16 - length(c.id::text) - 1) || ' ' || c.id
    WHERE EXISTS (SELECT 1 FROM characters d WHERE d.name_key = c.name_key AND d.id < c.id)
    """

    execute "UPDATE characters SET name_key = lower(regexp_replace(btrim(name), '\\s+', ' ', 'g'))"

    alter table(:characters) do
      modify :name_key, :string, null: false
    end

    create unique_index(:characters, [:name_key])
  end

  def down do
    drop index(:characters, [:name_key])

    alter table(:characters) do
      remove :name_key
    end
  end
end
