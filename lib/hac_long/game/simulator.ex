defmodule HacLong.Game.Simulator do
  @moduledoc """
  Mô phỏng một người chơi "hợp lý" từ đầu tới khi hạ Hắc Long, để kiểm tra cân bằng
  sau khi đổi số liệu. Chạy: `mix hac_long.simulate [số lần]`.

  Tùy chọn của `run/2`:

  - `quests: true` — nhận mọi nhiệm vụ Trưởng Làng đang có, trả ngay khi xong.
  - `daily: true` — làm việc hằng ngày; cứ `day_fights` trận (mặc định 60) tính là một ngày.
  - `gather_every: n` — cứ n trận thì hái/đào được một nguyên liệu của vùng đang đánh
    (mặc định 3, `nil` là không hái). Nguyên liệu không cần cho nhiệm vụ thì bán luôn.
  - `upgrade: true` — giữ quặng để Thợ Rèn nâng cấp đồ đang mặc (không tính cấp +5 vì cần
    Vảy Cổ Long của trùm thế giới).
  """

  alias HacLong.Game.{Daily, Data, Engine, Quests}

  @alloc %{
    "warrior" => ~w(str str vit),
    "rogue" => ~w(agi str vit),
    "knight" => ~w(vit def str)
  }
  @max_fights 5000

  @doc "Chơi một ván. Trả về số trận, cấp, số lần chết, vàng và các mốc hạ trùm."
  def run(cls, opts \\ []) do
    opts =
      Map.merge(
        %{quests: false, daily: false, upgrade: false, day_fights: 60, gather_every: 3},
        Map.new(opts)
      )

    {:ok, p} = Engine.new_player("Bot#{System.unique_integer([:positive])}", cls)
    p = Map.put(p, :quests, Quests.empty())

    loop(p, %{
      opts: opts,
      fights: 0,
      rest_gold: 0,
      cooldown: 0,
      milestones: [],
      boss_losses: [],
      quest_gold: 0,
      quest_xp: 0,
      quests_done: 0,
      daily_gold: 0,
      daily_xp: 0,
      daily_done: 0
    })
  end

  defp loop(%{victory: true} = p, st), do: result(p, st)
  defp loop(p, %{fights: f} = st) when f >= @max_fights, do: result(p, st)

  defp loop(p, st) do
    p =
      if st.opts.daily, do: Daily.ensure(p, "ngay-#{div(st.fights, st.opts.day_fights)}"), else: p

    {p, st} = p |> accept_quests(st) |> turn_in(st)
    {p, st} = claim_daily(p, st)
    p = p |> allocate_all() |> shop_up() |> forge(st)

    {p, st} =
      if p.hp < Engine.derived(p).maxHp * 0.6 do
        cost = Engine.rest_cost(p)
        {_, p} = Engine.rest(p)
        {p, %{st | rest_gold: st.rest_gold + cost}}
      else
        {p, st}
      end

    zi = 0..(Data.zone_count() - 1) |> Enum.filter(&Engine.zone_unlocked?(p, &1)) |> List.last()
    z = Data.zone(zi)
    boss? = st.cooldown <= 0 and p.level >= z.boss.level - 1 and z.boss.id not in p.bosses
    st = %{st | cooldown: st.cooldown - 1, fights: st.fights + 1}
    # lùi một khu nếu còn quá yếu
    zi = if not boss? and p.level < hd(z.monsters).level - 1 and zi > 0, do: zi - 1, else: zi

    {_, p} = Engine.start_battle(p, zi, boss?)
    p = fight(p)
    won? = p.battle.result == "win"

    st =
      cond do
        boss? and won? ->
          %{st | milestones: st.milestones ++ ["#{z.boss.name}@Lv#{p.level}(trận #{st.fights})"]}

        boss? ->
          lost = if p.battle.result == "lose", do: ["#{z.boss.name}@Lv#{p.level}"], else: []
          %{st | cooldown: 15, boss_losses: st.boss_losses ++ lost}

        true ->
          st
      end

    p =
      if won?,
        do: p |> Quests.on_kill(p.battle.monster.id) |> Daily.on_kill(p.battle.monster.id, zi),
        else: p

    p = gather(p, zi, st)
    {_, p} = Engine.leave_battle(p)
    loop(p, st)
  end

  # ---------- Nhiệm vụ, việc hằng ngày, thu thập ----------

  defp accept_quests(p, %{opts: %{quests: false}}), do: p

  defp accept_quests(p, _st) do
    Enum.reduce(Quests.available(p), p, fn q, p -> elem(Quests.accept(p, q.id), 1) end)
  end

  defp turn_in(p, %{opts: %{quests: false}} = st), do: {p, st}

  defp turn_in(p, st) do
    Enum.reduce(Map.keys(p.quests.active), {p, st}, fn id, {p, st} ->
      quest = Data.quest(id)

      if Quests.complete?(p, quest) do
        {_, p} = Quests.turn_in(p, id)

        {p,
         %{
           st
           | quest_gold: st.quest_gold + quest.reward.gold,
             quest_xp: st.quest_xp + quest.reward.xp,
             quests_done: st.quests_done + 1
         }}
      else
        {p, st}
      end
    end)
  end

  defp claim_daily(p, %{opts: %{daily: false}} = st), do: {p, st}

  defp claim_daily(p, st) do
    p.daily.tasks
    |> Enum.with_index()
    |> Enum.reduce({p, st}, fn {t, i}, {p, st} ->
      if t.progress >= t.count and not t.claimed do
        {_, p} = Daily.claim(p, i)

        {p,
         %{
           st
           | daily_gold: st.daily_gold + t.reward.gold,
             daily_xp: st.daily_xp + t.reward.xp,
             daily_done: st.daily_done + 1
         }}
      else
        {p, st}
      end
    end)
  end

  defp gather(p, _zi, %{opts: %{gather_every: nil}}), do: p

  defp gather(p, zi, %{fights: f, opts: %{gather_every: n}} = st) when rem(f, n) == 0 do
    kinds = if zi < 3, do: ~w(herb ore), else: ~w(herb_rare ore_rare)
    item = Enum.at(kinds, rem(div(f, n), 2))
    p = p |> Engine.add_item(item) |> Daily.on_gather(item)

    keep =
      needed(p, item) + if(st.opts.upgrade and String.starts_with?(item, "ore"), do: 99, else: 0)

    if Map.get(p.inv, item) > keep, do: elem(Engine.sell(p, item), 1), else: p
  end

  defp gather(p, _zi, _st), do: p

  # số nguyên liệu `item` cần giữ cho các nhiệm vụ thu thập đang làm
  defp needed(p, item) do
    p.quests.active
    |> Map.keys()
    |> Enum.map(&Data.quest/1)
    |> Enum.filter(&(&1.type == "collect" and &1.target == item))
    |> Enum.map(& &1.count)
    |> Enum.sum()
  end

  defp fight(%{battle: %{over: true}} = p), do: p

  defp fight(p) do
    d = Engine.derived(p)

    # kỹ năng mạnh nhất (mở muộn nhất) đang sẵn sàng
    skill = p |> Engine.skills() |> Enum.reverse() |> Enum.find(&(Engine.cooldown(p, &1.id) == 0))

    action =
      cond do
        p.hp < d.maxHp * 0.35 and Engine.best_potion(p, d.maxHp - p.hp) -> "potion"
        skill -> "skill"
        true -> "attack"
      end

    {_, p} = Engine.act(p, action, skill && skill.id)
    fight(p)
  end

  defp allocate_all(%{points: 0} = p), do: p

  defp allocate_all(p) do
    stat = Enum.at(@alloc[p.cls], rem(p.points, 3))
    {_, p} = Engine.allocate(p, stat, 1)
    allocate_all(p)
  end

  defp value(nil), do: 0
  defp value(id), do: (Data.item(id)[:atk] || 0) + (Data.item(id)[:def] || 0)

  # nâng cấp đồ đang mặc khi đủ quặng, còn dư vàng mua bình máu (tới +4)
  defp forge(p, %{opts: %{upgrade: false}}), do: p

  defp forge(p, st) do
    Enum.reduce(~w(weapon armor shield), p, fn slot, p ->
      id = p.equip[String.to_existing_atom(slot)]
      cost = id && Engine.upgrade_cost(id, Engine.upgrade_level(p, id))

      spare? =
        cost && not Map.has_key?(cost.items, "dragon_scale") && p.gold >= cost.gold + 100 &&
          Enum.all?(cost.items, fn {m, n} -> Map.get(p.inv, m, 0) - needed(p, m) >= n end)

      if spare? do
        case Engine.upgrade(p, slot) do
          {%{ok: true}, p} -> forge(p, st)
          _ -> p
        end
      else
        p
      end
    end)
  end

  defp worn(_p, nil), do: 0
  defp worn(p, id), do: value(id) + Engine.upgrade_bonus(p, id)

  defp shop_up(p) do
    p =
      Enum.reduce(~w(weapon armor shield), p, fn slot, p ->
        cur = p.equip[String.to_existing_atom(slot)]

        # đồ rơi trong túi tốt hơn thì mặc luôn
        owned =
          Enum.find(Map.keys(p.inv), fn id ->
            it = Data.item(id)
            it.slot == slot and it.level <= p.level and value(id) > worn(p, cur)
          end)

        best =
          Data.shop()
          |> Enum.filter(fn id ->
            it = Data.item(id)

            it.slot == slot and it.level <= p.level and it.price <= p.gold - 40 and
              value(id) > worn(p, cur)
          end)
          |> Enum.max_by(&value/1, fn -> nil end)

        cond do
          owned ->
            elem(Engine.equip(p, owned), 1)

          best ->
            {_, p} = Engine.buy(p, best)
            elem(Engine.equip(p, best), 1)

          true ->
            p
        end
      end)

    pot =
      cond do
        p.level >= 20 -> "potion_l"
        p.level >= 9 -> "potion_m"
        true -> "potion_s"
      end

    buy_potions(p, pot)
  end

  defp buy_potions(p, pot) do
    if Map.get(p.inv, pot, 0) < 5 and p.gold >= Data.item(pot).price + 20 do
      {_, p} = Engine.buy(p, pot)
      buy_potions(p, pot)
    else
      p
    end
  end

  defp result(p, st) do
    %{
      cls: p.cls,
      victory: p.victory,
      fights: st.fights,
      level: p.level,
      deaths: p.deaths,
      gold: p.gold,
      rest_gold: st.rest_gold,
      milestones: st.milestones,
      boss_losses: st.boss_losses,
      quest_gold: st.quest_gold,
      quest_xp: st.quest_xp,
      quests_done: st.quests_done,
      daily_gold: st.daily_gold,
      daily_xp: st.daily_xp,
      daily_done: st.daily_done
    }
  end
end
