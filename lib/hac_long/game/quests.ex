defmodule HacLong.Game.Quests do
  @moduledoc """
  Nhiệm vụ (dữ liệu ở `QUESTS` trong `priv/game_data.json`). Hàm thuần, như `Engine`.

  Trạng thái trong nhân vật: `quests: %{active: %{id => số_đã_hạ}, done: [id]}`.

  - `kill`: đếm số con `target` hạ được kể từ lúc nhận (`on_kill/2`).
  - `collect`: đủ `count` nguyên liệu trong túi lúc trả thì nộp (bị trừ khỏi túi).
  - `boss`: đã hạ trùm `target` (có trong `bosses`).
  """

  alias HacLong.Game.{Data, Engine}

  def empty, do: %{active: %{}, done: []}

  defp state(p), do: Map.get(p, :quests) || empty()

  @doc "Nhiệm vụ nhận được lúc này (vùng đã mở, xong nhiệm vụ yêu cầu, chưa nhận/chưa xong)."
  def available(p) do
    q = state(p)

    Enum.filter(Data.quests(), fn quest ->
      not Map.has_key?(q.active, quest.id) and quest.id not in q.done and
        Engine.zone_unlocked?(p, quest.zone) and Enum.all?(quest.requires, &(&1 in q.done))
    end)
  end

  @doc "Tiến độ `{đã_có, cần}` của một nhiệm vụ đang làm."
  def progress(p, %{type: "kill"} = quest),
    do: {min(state(p).active[quest.id] || 0, quest.count), quest.count}

  def progress(p, %{type: "collect"} = quest),
    do: {min(Map.get(p.inv, quest.target, 0), quest.count), quest.count}

  def progress(p, %{type: "boss"} = quest), do: {if(quest.target in p.bosses, do: 1, else: 0), 1}

  def complete?(p, quest) do
    {have, need} = progress(p, quest)
    have >= need
  end

  def accept(p, id) do
    quest = Data.quest(id)

    cond do
      quest == nil ->
        {%{ok: false, msg: "Không có nhiệm vụ này."}, p}

      quest not in available(p) ->
        {%{ok: false, msg: "Chưa nhận được nhiệm vụ này."}, p}

      true ->
        q = state(p)

        {%{ok: true, msg: "Đã nhận: #{quest.name}."},
         Map.put(p, :quests, %{q | active: Map.put(q.active, id, 0)})}
    end
  end

  def turn_in(p, id) do
    quest = Data.quest(id)
    q = state(p)

    cond do
      quest == nil or not Map.has_key?(q.active, id) ->
        {%{ok: false, msg: "Bạn chưa nhận nhiệm vụ này."}, p}

      not complete?(p, quest) ->
        {%{ok: false, msg: "Chưa hoàn thành."}, p}

      true ->
        {%{
           ok: true,
           msg:
             "Hoàn thành: #{quest.name}! +#{quest.reward.gold} vàng, +#{quest.reward.xp} kinh nghiệm."
         }, reward(p, quest)}
    end
  end

  defp reward(p, quest) do
    p =
      if quest.type == "collect",
        do: %{p | inv: take(p.inv, quest.target, quest.count)},
        else: p

    q = state(p)
    p = %{p | gold: p.gold + quest.reward.gold}
    p = Enum.reduce(quest.reward.items, p, fn {id, n}, p -> Engine.add_item(p, id, n) end)
    p = Map.put(p, :quests, %{active: Map.delete(q.active, quest.id), done: q.done ++ [quest.id]})
    {_levels, p} = Engine.gain_xp(p, quest.reward.xp)
    p
  end

  defp take(inv, id, n) do
    case Map.get(inv, id, 0) - n do
      left when left > 0 -> Map.put(inv, id, left)
      _ -> Map.delete(inv, id)
    end
  end

  @doc "Vừa hạ một con quái `monster_id`: cộng tiến độ các nhiệm vụ `kill` đang làm."
  def on_kill(p, monster_id) do
    q = state(p)

    active =
      Map.new(q.active, fn {id, n} ->
        quest = Data.quest(id)
        if quest.type == "kill" and quest.target == monster_id, do: {id, n + 1}, else: {id, n}
      end)

    Map.put(p, :quests, %{q | active: active})
  end
end
