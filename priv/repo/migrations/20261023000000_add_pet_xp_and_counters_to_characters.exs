defmodule HacLong.Repo.Migrations.AddPetXpAndCountersToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      # số trận thắng của từng thú khi được dắt theo (%{id => số}), để tính cấp thú
      add :pet_xp, :map, null: false, default: %{}

      # số việc hằng ngày đã nhận thưởng; số lần lọt top 3 sát thương trùm thế giới
      add :daily_done, :integer, null: false, default: 0
      add :boss_top, :integer, null: false, default: 0
    end
  end
end
