defmodule HacLong.GuildQuestsTest do
  use HacLong.DataCase, async: true

  import Ecto.Query
  alias HacLong.{Accounts, GuildQuests, Mailbox, Repo}

  defp user(name) do
    {:ok, u} = Accounts.register(%{"username" => name, "password" => "matkhau1"})
    u.id
  end

  defp guild(name, tag, members) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {1, [%{id: gid}]} =
      Repo.insert_all(
        "guilds",
        [%{name: name, name_key: String.downcase(name), tag: tag, inserted_at: now}],
        returning: [:id]
      )

    Repo.insert_all(
      "guild_members",
      for(uid <- members, do: %{user_id: uid, guild_id: gid, inserted_at: now})
    )

    gid
  end

  defp field(gid, f), do: Repo.one(from g in "guilds", where: g.id == ^gid, select: field(g, ^f))

  test "tuần theo giờ Việt Nam, đếm giờ tới thứ Hai" do
    # 2026-10-04 là Chủ nhật; 17:00 UTC là 0 giờ thứ Hai ở Việt Nam
    assert GuildQuests.week(~U[2026-10-04 16:59:00Z]) == "2026-W40"
    assert GuildQuests.week(~U[2026-10-04 17:00:00Z]) == "2026-W41"
    assert GuildQuests.seconds_left(~U[2026-10-04 16:59:00Z]) == 60
    assert GuildQuests.seconds_left(~U[2026-10-03 16:59:00Z]) == 60 + 86_400
  end

  test "việc cố định theo bang và tuần, mục tiêu theo số người" do
    assert GuildQuests.pick(1, "2026-W40", 2) == GuildQuests.pick(1, "2026-W40", 2)
    %{kind: kind, goal: goal} = GuildQuests.pick(1, "2026-W40", 5)
    per = Enum.find(GuildQuests.kinds(), &(&1.kind == kind)).per
    assert goal == per * 5
    assert GuildQuests.pick(1, "2026-W40", 1).goal == per * 3
  end

  test "cả bang góp tiến độ, đủ thì thưởng một lần cho mọi người" do
    [a, b] = [user("gqa"), user("gqb")]
    gid = guild("Bang Thử", "THU", [a, b])
    q = GuildQuests.current(gid)
    assert q.progress == 0 and not q.done and q.goal > 0
    other = Enum.find(GuildQuests.kinds(), &(&1.kind != q.kind)).kind

    # việc khác loại thì không tính
    assert :ok = GuildQuests.progress(gid, %{other => 5})
    assert GuildQuests.current(gid).progress == 0

    assert :ok = GuildQuests.progress(gid, %{q.kind => q.goal - 1, other => 3})
    assert GuildQuests.current(gid).progress == q.goal - 1
    fund = field(gid, :fund)

    assert :done = GuildQuests.progress(gid, %{q.kind => 2})
    assert GuildQuests.current(gid).done
    assert field(gid, :fund) == fund + GuildQuests.rewards().fund
    assert [%{subject: "Nhiệm vụ bang hoàn thành"}] = Mailbox.list(a)
    assert [%{gold: 800}] = Mailbox.list(b)

    # xong rồi thì không cộng, không thưởng nữa
    assert :ok = GuildQuests.progress(gid, %{q.kind => 10})
    assert length(Mailbox.list(a)) == 1

    # sang tuần mới thì việc mới
    Repo.update_all(from(g in "guilds", where: g.id == ^gid), set: [quest_week: "2000-W01"])
    assert %{progress: 0, done: false} = GuildQuests.current(gid)
  end

  test "sát thương trùm thế giới cộng vào bang, xếp hạng" do
    [a, b, c, d] = [user("gba"), user("gbb"), user("gbc"), user("gbd")]
    g1 = guild("Rồng Đỏ", "RDO", [a, b])
    g2 = guild("Hổ Xám", "HXA", [c])
    _g3 = guild("Mèo Lười", "MEO", [])

    GuildQuests.add_boss_damage(%{a => 100, b => 50, c => 300, d => 999})
    GuildQuests.add_boss_damage(%{a => 200})
    GuildQuests.add_boss_damage(%{})

    assert [
             %{id: ^g1, boss_damage: 350, rank: 1, members: 2},
             %{id: ^g2, boss_damage: 300, rank: 2, members: 1}
           ] = GuildQuests.boss_top()
  end
end
