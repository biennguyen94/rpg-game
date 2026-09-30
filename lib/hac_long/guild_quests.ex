defmodule HacLong.GuildQuests do
  @moduledoc """
  Nhiệm vụ bang và bảng xếp hạng bang theo sát thương lên trùm thế giới.

  - Mỗi tuần (thứ Hai 0 giờ, giờ Việt Nam) mỗi bang có một nhiệm vụ chung, chọn cố định theo
    bang và tuần: hạ quái, hái/đào, câu cá hoặc hạ trùm canh giữ vùng. Mục tiêu tính theo số
    thành viên lúc nhận việc (ít nhất như bang 3 người).
  - Mọi thành viên cùng góp tiến độ (`progress/2`, gọi từ `HacLong.Game.Session` sau mỗi lệnh).
    Đủ mục tiêu thì quỹ bang được cộng thêm và mỗi thành viên nhận thưởng qua hộp thư. Tiến độ
    cộng bằng một câu `UPDATE` nên nhiều người góp cùng lúc không mất lượt nào, và chỉ lần
    cộng vượt mốc mới trao thưởng.
  - Sát thương lên trùm thế giới của thành viên cộng vào `boss_damage` của bang
    (`add_boss_damage/1`, gọi từ `HacLong.WorldBoss` khi trùm gục hoặc bay đi).
  """
  import Ecto.Query

  alias HacLong.{Guilds, Mailbox, Repo}
  alias HacLong.Game.Daily

  @kinds [
    %{kind: "kill", per: 60, name: "Hạ quái", unit: "con quái"},
    %{kind: "gather", per: 15, name: "Hái thuốc, đào quặng", unit: "lần hái/đào"},
    %{kind: "fish", per: 10, name: "Câu cá", unit: "con cá"},
    %{kind: "boss", per: 1, name: "Hạ trùm canh giữ vùng", unit: "lần hạ trùm"}
  ]

  @fund_reward 3000
  @gold_reward 800
  @xp_reward 1500

  def kinds, do: @kinds
  def rewards, do: %{fund: @fund_reward, gold: @gold_reward, xp: @xp_reward}

  # ---------- Tuần ----------

  @doc "Tuần hiện tại theo giờ Việt Nam, dạng \"2026-W40\"."
  def week(now \\ DateTime.utc_now()) do
    {y, w} =
      now |> Daily.today() |> Date.from_iso8601!() |> Date.to_erl() |> :calendar.iso_week_number()

    "#{y}-W#{String.pad_leading(Integer.to_string(w), 2, "0")}"
  end

  @doc "Số giây tới lúc sang tuần mới (thứ Hai 0 giờ giờ Việt Nam)."
  def seconds_left(now \\ DateTime.utc_now()) do
    today = now |> Daily.today() |> Date.from_iso8601!()
    days = 8 - Date.day_of_week(today)
    Daily.seconds_left(now) + (days - 1) * 86_400
  end

  @doc "Việc của bang `gid` trong tuần `week` (cố định theo bang và tuần)."
  def pick(gid, week, members) do
    k = Enum.at(@kinds, :erlang.phash2({gid, week}, length(@kinds)))
    %{kind: k.kind, goal: k.per * max(3, members)}
  end

  # ---------- Đọc ----------

  @doc """
  Nhiệm vụ tuần này của bang (tạo mới nếu sang tuần): `%{kind, name, unit, goal, progress,
  done, week, left, reward}`.
  """
  def current(gid) do
    ensure(gid)

    case Repo.one(
           from g in "guilds",
             where: g.id == ^gid,
             select: %{
               week: g.quest_week,
               kind: g.quest_kind,
               goal: g.quest_goal,
               progress: g.quest_progress,
               done: g.quest_done
             }
         ) do
      nil ->
        nil

      q ->
        k = Enum.find(@kinds, &(&1.kind == q.kind))

        Map.merge(q, %{
          name: k.name,
          unit: k.unit,
          left: seconds_left(),
          reward: rewards()
        })
    end
  end

  # sang tuần mới thì đặt việc mới (chỉ một lần: điều kiện tuần cũ nằm trong câu UPDATE)
  defp ensure(gid) do
    w = week()
    members = length(Guilds.member_ids(gid))
    q = pick(gid, w, members)

    from(g in "guilds", where: g.id == ^gid and (is_nil(g.quest_week) or g.quest_week != ^w))
    |> Repo.update_all(
      set: [
        quest_week: w,
        quest_kind: q.kind,
        quest_goal: q.goal,
        quest_progress: 0,
        quest_done: false
      ]
    )

    :ok
  end

  # ---------- Góp tiến độ ----------

  @doc """
  Thành viên của bang `gid` vừa làm `events` (`%{"kill" => 2, "fish" => 1}`...). Cộng vào
  nhiệm vụ tuần này nếu đúng loại; đủ mục tiêu thì trao thưởng. Trả về `:done` khi lần
  này hoàn thành nhiệm vụ, còn lại `:ok`.
  """
  def progress(gid, events) when is_map(events) do
    ensure(gid)
    w = week()

    {n, rows} =
      Enum.reduce(events, {0, []}, fn {kind, k}, acc ->
        with true <- is_integer(k) and k > 0,
             {1, _} = hit <-
               from(g in "guilds",
                 where: g.id == ^gid and g.quest_week == ^w and g.quest_kind == ^kind,
                 where: not g.quest_done,
                 select: %{progress: g.quest_progress, goal: g.quest_goal}
               )
               |> Repo.update_all(inc: [quest_progress: k]) do
          hit
        else
          _ -> acc
        end
      end)

    case n > 0 && rows do
      [%{progress: prog, goal: goal}] when prog >= goal -> complete(gid, w)
      _ -> :ok
    end
  end

  # chỉ một người "chạm vạch" được đánh dấu xong (điều kiện quest_done = false)
  defp complete(gid, w) do
    {n, _} =
      from(g in "guilds",
        where: g.id == ^gid and g.quest_week == ^w and not g.quest_done,
        where: g.quest_progress >= g.quest_goal
      )
      |> Repo.update_all(set: [quest_done: true], inc: [fund: @fund_reward])

    if n == 1 do
      for uid <- Guilds.member_ids(gid) do
        Mailbox.send(uid, %{
          subject: "Nhiệm vụ bang hoàn thành",
          body: "Cả bang đã làm xong nhiệm vụ tuần này. Quỹ bang +#{@fund_reward} vàng.",
          gold: @gold_reward,
          xp: @xp_reward
        })

        HacLong.Game.Session.refresh_guild(uid)
      end

      Guilds.system(
        gid,
        "🎉 Nhiệm vụ bang tuần này đã xong! Quỹ bang +#{@fund_reward}, mỗi người nhận quà qua hộp thư."
      )

      :done
    else
      :ok
    end
  end

  # ---------- Trùm thế giới ----------

  @doc "Cộng sát thương (`%{uid => dmg}`) lên trùm thế giới vào bang của từng người."
  def add_boss_damage(damage) when map_size(damage) == 0, do: :ok

  def add_boss_damage(damage) do
    uids = Map.keys(damage)

    Repo.all(
      from m in "guild_members",
        where: m.user_id in ^uids,
        select: {m.user_id, m.guild_id}
    )
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.each(fn {gid, members} ->
      total = members |> Enum.map(&damage[&1]) |> Enum.sum()

      from(g in "guilds", where: g.id == ^gid)
      |> Repo.update_all(inc: [boss_damage: total])
    end)
  end

  @doc "Bảng xếp hạng bang theo sát thương lên trùm thế giới."
  def boss_top(n \\ 10) do
    from(g in "guilds",
      left_join: m in "guild_members",
      on: m.guild_id == g.id,
      where: g.boss_damage > 0,
      group_by: g.id,
      order_by: [desc: g.boss_damage, asc: g.id],
      limit: ^n,
      select: %{
        id: g.id,
        name: g.name,
        tag: g.tag,
        boss_damage: g.boss_damage,
        members: count(m.user_id)
      }
    )
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {g, i} -> Map.put(g, :rank, i) end)
  end
end
