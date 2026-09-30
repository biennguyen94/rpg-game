defmodule HacLong.Game.Crafting do
  @moduledoc """
  Nghề: nấu ăn (Bác Đầu Bếp) và rèn đồ (Thợ Rèn). Hàm thuần, như `Engine`.

  - **Nấu ăn** (`cook/2`): công thức `npc: "cook"` trong `RECIPES`, một số cần cấp nghề
    (`level`). Món ăn (`slot: "food"`) ăn ngoài trận (`eat/2`) thì có tác dụng trong một số
    trận (`food.battles`): cộng phần trăm máu/tấn công/phòng thủ/kinh nghiệm/vàng
    (`food_bonus/2`). Mỗi lúc chỉ một món; ăn món khác thì thay món cũ.
  - **Rèn đồ** (`smith/2`): chọn vũ khí, giáp hoặc khiên; tốn quặng và vàng, ra một món đồ chỉ
    số ngẫu nhiên hợp cấp. Cấp nghề rèn càng cao càng dễ ra đồ Sử Thi.
  - Mỗi lần nấu/rèn được 1 kinh nghiệm nghề; cấp nghề 1–5 (`level/1`).

  Trạng thái trong nhân vật: `crafting: %{cook: số, smith: số}`, `food: %{id, left} | nil`.
  """

  alias HacLong.Game.{Data, Engine, Gear}

  @levels [0, 5, 15, 30, 50]
  @names %{cook: "Nấu ăn", smith: "Rèn đồ"}
  # nguyên liệu mỗi lần rèn theo loại đồ; vàng = cấp nhân vật × 15
  @smith_costs %{
    "weapon" => %{"ore" => 6, "ore_rare" => 1},
    "armor" => %{"ore" => 5, "ore_rare" => 1},
    "shield" => %{"ore" => 4, "ore_rare" => 1}
  }

  def levels, do: @levels
  def max_level, do: length(@levels)
  def smith_costs, do: @smith_costs
  def smith_gold(p), do: p.level * 15

  def xp(p, skill), do: Map.get(Map.get(p, :crafting) || %{}, skill, 0)
  def level(xp) when is_integer(xp), do: Enum.count(@levels, &(xp >= &1))
  def level(p, skill), do: level(xp(p, skill))

  @doc "Tỉ lệ độ hiếm khi rèn ở cấp nghề `lv`: Sử Thi 6% + 6% mỗi cấp, Hiếm 50%, còn lại Tốt."
  def smith_weights(lv), do: [{3, 6 * lv}, {2, 50}, {1, 50 - 6 * lv}]

  defp gain(p, skill) do
    before = level(p, skill)
    all = Map.get(p, :crafting) || %{cook: 0, smith: 0}
    p = Map.put(p, :crafting, Map.put(all, skill, xp(p, skill) + 1))
    now = level(p, skill)

    note =
      if now > before, do: " Nghề #{@names[skill]} lên cấp #{now}!", else: ""

    {p, note}
  end

  defp has_all?(p, needs), do: Enum.all?(needs, fn {id, n} -> Map.get(p.inv, id, 0) >= n end)

  defp take_all(p, needs) do
    inv =
      Enum.reduce(needs, p.inv, fn {id, n}, inv ->
        if inv[id] > n, do: Map.put(inv, id, inv[id] - n), else: Map.delete(inv, id)
      end)

    %{p | inv: inv}
  end

  # ---------- Nấu ăn ----------

  def cook(p, id) do
    r = Data.recipe(id)

    cond do
      r == nil or r.npc != "cook" ->
        {%{ok: false, msg: "Không có món này."}, p}

      level(p, :cook) < (r[:level] || 1) ->
        {%{ok: false, msg: "Cần nghề Nấu ăn cấp #{r.level}."}, p}

      not has_all?(p, r.needs) ->
        {%{ok: false, msg: "Chưa đủ nguyên liệu."}, p}

      true ->
        p = p |> take_all(r.needs) |> Engine.add_item(r.out)
        {p, note} = gain(p, :cook)
        {%{ok: true, msg: "Nấu được #{Data.item(r.out).name}.#{note}"}, p}
    end
  end

  @doc "Ăn món `id` (ngoài trận): có tác dụng trong `food.battles` trận tới."
  def eat(p, id) do
    it = Data.item(id)

    cond do
      p.battle ->
        {%{ok: false, msg: "Không ăn được trong trận."}, p}

      it == nil or it.slot != "food" or Map.get(p.inv, id, 0) <= 0 ->
        {%{ok: false, msg: "Không có món này."}, p}

      true ->
        p = take_all(p, %{id => 1}) |> Map.put(:food, %{id: id, left: it.food.battles})
        {%{ok: true, msg: "Ăn #{it.name}: #{it.desc}"}, p}
    end
  end

  @doc "Phần trăm cộng thêm của món đang ăn cho chỉ số `key` (hp, atk, def, xp, gold)."
  def food_bonus(p, key) do
    case Map.get(p, :food) do
      %{id: id, left: left} when left > 0 ->
        case Data.item(id) do
          %{food: %{buff: b}} -> Map.get(b, key, 0)
          _ -> 0
        end

      _ ->
        0
    end
  end

  @doc "Hết một trận: món ăn bớt một trận tác dụng."
  def tick(p) do
    case Map.get(p, :food) do
      %{left: left} when left > 1 -> put_in(p.food.left, left - 1)
      %{} -> Map.put(p, :food, nil)
      nil -> p
    end
  end

  # ---------- Rèn đồ ----------

  def smith(p, slot) do
    cost = @smith_costs[slot]
    gold = smith_gold(p)

    cond do
      cost == nil ->
        {%{ok: false, msg: "Không rèn được loại này."}, p}

      p.battle ->
        {%{ok: false, msg: "Đang trong trận."}, p}

      not has_all?(p, cost) ->
        {%{ok: false, msg: "Chưa đủ quặng."}, p}

      p.gold < gold ->
        {%{ok: false, msg: "Cần #{gold} vàng."}, p}

      length(Gear.bag(p)) >= Gear.max_bag() ->
        {%{ok: false, msg: "Túi đồ hiếm đầy (#{Gear.max_bag()} món). Bán bớt đã."}, p}

      true ->
        g = Gear.roll(max(p.level, 3), smith_weights(level(p, :smith)), slot)
        p = %{take_all(p, cost) | gold: p.gold - gold}
        {p, :kept} = Gear.add(p, g)
        {p, note} = gain(p, :smith)
        it = Gear.resolve(g)

        {%{
           ok: true,
           msg: "Rèn được #{it.name} (#{Gear.rarity_names()[g.rarity]})!#{note}",
           gear: g.uid
         }, p}
    end
  end
end
