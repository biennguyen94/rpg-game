defmodule HacLong.Game.Chests do
  @moduledoc """
  Rương: chỗ tiêu vàng và quà mỗi ngày. Hàm thuần, như `Engine` (trừ ngày hôm nay).

  - Rương Báu bán ở Thợ Rèn (`buy/2`): mở ra một món đồ chỉ số ngẫu nhiên hợp cấp người chơi.
    Giá bằng mấy lần giá bán lại vũ khí tốt nhất ở cấp đó, nên mua rương về bán lại luôn lỗ;
    rương đắt hơn thì dễ ra đồ hiếm hơn.
  - Rương Gia Truyền ở Nhà (`open_daily/2`): mỗi ngày (giờ Việt Nam) mở miễn phí một lần,
    được vàng, bình máu, nguyên liệu và đôi khi một món đồ.

  Ngày đã mở rương ở Nhà lưu trong `chest_day`.
  """

  alias HacLong.Game.{Data, Engine, Gear, Rng}

  @tiers [
    %{id: "wood", name: "Rương Gỗ", times: 2, weights: [{3, 2}, {2, 18}, {1, 80}]},
    %{id: "silver", name: "Rương Bạc", times: 4, weights: [{3, 10}, {2, 50}, {1, 40}]},
    %{id: "gold", name: "Rương Vàng", times: 8, weights: [{3, 30}, {2, 70}]}
  ]

  def tiers, do: @tiers
  def tier(id), do: Enum.find(@tiers, &(&1.id == id))

  @doc "Giá rương theo cấp người chơi."
  def price(%{times: k}, level) do
    best =
      Data.items()
      |> Enum.filter(fn {_, it} ->
        it.slot == "weapon" and it.price > 0 and !it[:drop] and it.level <= max(level, 3)
      end)
      |> Enum.map(fn {_, it} -> it.price end)
      |> Enum.max()

    round(best * 0.4 * k)
  end

  # đồ trong rương hợp cấp người chơi (ít nhất cấp 3 để có đồ gốc)
  defp roll(p, weights), do: Gear.roll(max(p.level, 3), weights)

  def buy(p, id) do
    t = tier(id)
    cost = t && price(t, p.level)

    cond do
      t == nil ->
        {%{ok: false, msg: "Không có loại rương này."}, p}

      p.gold < cost ->
        {%{ok: false, msg: "Cần #{cost} vàng."}, p}

      length(Gear.bag(p)) >= Gear.max_bag() ->
        {%{ok: false, msg: "Túi đồ hiếm đầy (#{Gear.max_bag()} món). Bán bớt đã."}, p}

      true ->
        g = roll(p, t.weights)
        {p, :kept} = Gear.add(%{p | gold: p.gold - cost}, g)
        it = Gear.resolve(g)

        {%{
           ok: true,
           msg: "Mở #{t.name}: #{it.name} (#{Gear.rarity_names()[g.rarity]})!",
           gear: g.uid
         }, p}
    end
  end

  @doc "Mở Rương Gia Truyền ở Nhà (mỗi ngày một lần). `today`: ngày giờ Việt Nam."
  def open_daily(p, today) do
    if Map.get(p, :chest_day) == today do
      {%{ok: false, msg: "Hôm nay đã mở rồi. Mai quay lại nhé."}, p}
    else
      gold = 20 + p.level * 8

      pot =
        cond do
          p.level >= 20 -> "potion_l"
          p.level >= 9 -> "potion_m"
          true -> "potion_s"
        end

      mat =
        Enum.at(
          ~w(herb ore herb_rare ore_rare),
          floor(Rng.uniform() * 2) + if(p.level >= 18, do: 2, else: 0)
        )

      p = %{p | gold: p.gold + gold} |> Engine.add_item(pot, 2) |> Engine.add_item(mat, 2)
      p = Map.put(p, :chest_day, today)
      parts = ["#{gold} vàng", "#{Data.item(pot).name} ×2", "#{Data.item(mat).name} ×2"]

      {p, parts} =
        with true <- Rng.uniform() < 0.2,
             %{} = g <- roll(p, [{3, 2}, {2, 18}, {1, 80}]),
             {p, :kept} <- Gear.add(p, g) do
          {p, parts ++ [Gear.resolve(g).name]}
        else
          _ -> {p, parts}
        end

      {%{ok: true, msg: "Rương Gia Truyền: #{Enum.join(parts, ", ")}."}, p}
    end
  end
end
