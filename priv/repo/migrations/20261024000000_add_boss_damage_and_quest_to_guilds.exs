defmodule HacLong.Repo.Migrations.AddBossDamageAndQuestToGuilds do
  use Ecto.Migration

  def change do
    alter table(:guilds) do
      # tổng sát thương thành viên gây lên trùm thế giới (bảng xếp hạng bang)
      add :boss_damage, :bigint, null: false, default: 0

      # nhiệm vụ bang trong tuần `quest_week` (vd. "2026-W40"): làm `quest_goal` lần việc `quest_kind`
      add :quest_week, :string
      add :quest_kind, :string
      add :quest_goal, :integer, null: false, default: 0
      add :quest_progress, :integer, null: false, default: 0
      add :quest_done, :boolean, null: false, default: false
    end

    create index(:guilds, [:boss_damage])
  end
end
