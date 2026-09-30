defmodule HacLong.Game.Simulator do
  @moduledoc """
  Mô phỏng một người chơi "hợp lý" từ đầu tới khi hạ Hắc Long, để kiểm tra cân bằng
  sau khi đổi số liệu. Chạy: `mix hac_long.simulate [số lần]`.
  """

  alias HacLong.Game.{Data, Engine}

  @alloc %{
    "warrior" => ~w(str str vit),
    "rogue" => ~w(agi str vit),
    "knight" => ~w(vit def str)
  }
  @max_fights 5000

  @doc "Chơi một ván. Trả về số trận, cấp, số lần chết, vàng và các mốc hạ trùm."
  def run(cls) do
    {:ok, p} = Engine.new_player("Bot", cls)
    loop(p, %{fights: 0, rest_gold: 0, cooldown: 0, milestones: [], boss_losses: []})
  end

  defp loop(%{victory: true} = p, st), do: result(p, st)
  defp loop(p, %{fights: f} = st) when f >= @max_fights, do: result(p, st)

  defp loop(p, st) do
    p = p |> allocate_all() |> shop_up()

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

    {_, p} = Engine.leave_battle(p)
    loop(p, st)
  end

  defp fight(%{battle: %{over: true}} = p), do: p

  defp fight(p) do
    d = Engine.derived(p)

    action =
      cond do
        p.hp < d.maxHp * 0.35 and Engine.best_potion(p, d.maxHp - p.hp) -> "potion"
        p.battle.skillCd == 0 -> "skill"
        true -> "attack"
      end

    {_, p} = Engine.act(p, action)
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

  defp shop_up(p) do
    p =
      Enum.reduce(~w(weapon armor shield), p, fn slot, p ->
        cur = p.equip[String.to_existing_atom(slot)]

        # đồ rơi trong túi tốt hơn thì mặc luôn
        owned =
          Enum.find(Map.keys(p.inv), fn id ->
            it = Data.item(id)
            it.slot == slot and it.level <= p.level and value(id) > value(cur)
          end)

        best =
          Data.shop()
          |> Enum.filter(fn id ->
            it = Data.item(id)

            it.slot == slot and it.level <= p.level and it.price <= p.gold - 40 and
              value(id) > value(cur)
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
      boss_losses: st.boss_losses
    }
  end
end
