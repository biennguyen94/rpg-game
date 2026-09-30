defmodule HacLong.Repo.Migrations.AddTutorialToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      # bước hướng dẫn người mới đang làm (0–4); nil khi đã xong, bỏ qua, hoặc nhân vật
      # tạo trước khi có hướng dẫn
      add :tutorial, :integer
    end
  end
end
