defmodule HacLong.Game.Tower do
  @moduledoc """
  Tháp Vô Tận: leo từng tầng, mỗi tầng một bản đồ nhỏ sinh ngẫu nhiên, riêng cho mỗi người.
  Hàm thuần, như `Engine`.

  - Tầng N có quái cấp N (hình lấy theo vùng tương ứng, tầng 1–10 như Rừng Mê, 11–20 như
    Trại Goblin...); từ tầng 37 quái mạnh thêm 4% mỗi tầng, nên tháp không có đỉnh.
  - Hạ hết quái trên tầng thì cầu thang lên (`>`) mở; lên tầng thì nhận thưởng. Tầng chia
    hết cho 5 có trùm tầng.
  - Máu không tự hồi giữa các tầng (chỉ có bình máu). Gục ngã thì lượt leo kết thúc; đi cầu
    thang xuống (`<`) ở đầu tầng để về Làng lúc nào cũng được.
  - Kỷ lục `tower_best` là tầng cao nhất đã vượt qua. Lần sau có thể bắt đầu ở tầng 1, 11,
    21... miễn là không quá kỷ lục + 1.

  Trạng thái trong nhân vật: `tower: nil | %{floor, tiles, stairs, exit, monsters}` và
  `tower_best`.
  """

  alias HacLong.Game.{Data, Engine}

  @w 13
  @h 11
  @map "tower"

  def map_id, do: @map

  @doc "Các tầng được chọn để bắt đầu: 1, 11, 21... không quá kỷ lục + 1."
  def starts(best), do: Enum.take_every(1..(best + 1)//1, 10) |> Enum.to_list()

  # ---------- Sinh tầng ----------

  @doc "Dựng tầng `floor`. `salt` làm mỗi lượt leo có bản đồ khác nhau."
  def build(floor, salt) do
    <<a::32, b::32, c::32, _::binary>> = :crypto.hash(:sha256, "tower|#{floor}|#{salt}")
    rng = :rand.seed_s(:exsss, {a, b, c})
    {tiles, stairs, exit, rng} = layout(rng)

    {monsters, _rng} =
      monsters(floor, tiles, [stairs, exit, {elem(exit, 0), elem(exit, 1) - 1}], rng)

    %{
      floor: floor,
      tiles: tiles,
      stairs: Tuple.to_list(stairs),
      exit: Tuple.to_list(exit),
      monsters: monsters
    }
  end

  defp layout(rng) do
    {sx, rng} = uniform(@w - 4, rng)
    stairs = {sx + 1, 1}
    exit = {div(@w, 2), @h - 2}

    {grid, rng} =
      Enum.reduce(1..(@h - 2), {%{}, rng}, fn y, {g, rng} ->
        Enum.reduce(1..(@w - 2), {g, rng}, fn x, {g, rng} ->
          {r, rng} = :rand.uniform_s(rng)
          {Map.put(g, {x, y}, if(r < 0.14, do: "I", else: ".")), rng}
        end)
      end)

    # giữ trống quanh hai cầu thang và một lối đi thẳng giữa chúng
    {ex, ey} = exit
    clear = [{ex, ey - 1}, {ex - 1, ey - 1}, {ex + 1, ey - 1}, {sx + 1, 2}]
    path = for y <- 2..(ey - 1), do: {ex, y}
    path = path ++ for x <- min(ex, sx + 1)..max(ex, sx + 1), do: {x, 2}
    grid = Enum.reduce(clear ++ path, grid, &Map.put(&2, &1, "."))
    grid = grid |> Map.put(stairs, ">") |> Map.put(exit, "<")
    grid = fill_unreachable(grid, {ex, ey - 1})

    tiles =
      for y <- 0..(@h - 1) do
        for(x <- 0..(@w - 1), into: "", do: Map.get(grid, {x, y}, "S"))
      end

    {tiles, stairs, exit, rng}
  end

  # ô trống không tới được từ lối vào thì lấp lại
  defp fill_unreachable(grid, start) do
    seen = flood(grid, [start], MapSet.new([start]))

    Map.new(grid, fn {pos, c} ->
      if c == "." and pos not in seen, do: {pos, "I"}, else: {pos, c}
    end)
  end

  defp flood(_grid, [], seen), do: seen

  defp flood(grid, [{x, y} | rest], seen) do
    next =
      for {dx, dy} <- [{1, 0}, {-1, 0}, {0, 1}, {0, -1}],
          p = {x + dx, y + dy},
          Map.get(grid, p) in [".", ">", "<"],
          p not in seen,
          do: p

    flood(grid, next ++ rest, Enum.reduce(next, seen, &MapSet.put(&2, &1)))
  end

  defp tier(floor), do: min(Data.zone_count() - 1, div(floor - 1, 10))

  def theme(floor), do: "floors/" <> Data.zone(tier(floor)).id

  defp monsters(floor, tiles, avoid, rng) do
    zone = Data.zone(tier(floor))
    boss? = rem(floor, 5) == 0
    count = if boss?, do: 2, else: min(6, 3 + div(floor, 10))

    free =
      for {row, y} <- Enum.with_index(tiles),
          {c, x} <- Enum.with_index(String.graphemes(row)),
          c == ".",
          {x, y} not in avoid,
          do: {x, y}

    {spots, rng} = shuffle(free, rng)

    {list, rng} =
      Enum.reduce(1..count, {[], rng}, fn i, {acc, rng} ->
        {m, rng} = pick(zone.monsters, rng)
        {x, y} = Enum.at(spots, i)
        {[%{id: i, kind: m.id, name: m.name, level: floor, x: x, y: y, elite: false} | acc], rng}
      end)

    list =
      if boss? do
        {x, y} = hd(spots)

        [
          %{
            id: 0,
            kind: zone.boss.id,
            name: zone.boss.name,
            level: floor + 2,
            x: x,
            y: y,
            elite: true
          }
          | list
        ]
      else
        list
      end

    {Enum.reverse(list), rng}
  end

  defp uniform(n, rng), do: :rand.uniform_s(n, rng)

  defp pick(list, rng) do
    {i, rng} = uniform(length(list), rng)
    {Enum.at(list, i - 1), rng}
  end

  defp shuffle(list, rng) do
    {keyed, rng} =
      Enum.map_reduce(list, rng, fn x, rng ->
        {r, rng} = :rand.uniform_s(rng)
        {{r, x}, rng}
      end)

    {keyed |> Enum.sort() |> Enum.map(&elem(&1, 1)), rng}
  end

  # ---------- Quái ----------

  @doc "Quái dùng trong trận với con `m` trên tầng."
  def battle_monster(m) do
    mult = 1 + max(0, m.level - 36) * 0.04
    base = if m.elite, do: Enum.find(Data.zones(), &(&1.boss.id == m.kind)).boss, else: %{}

    spec = %{
      id: m.kind,
      name: m.name,
      level: m.level,
      mult: if(m.elite, do: mult * 1.3, else: mult),
      special: base[:special]
    }

    q = Engine.make_monster(spec, false)
    q = if m.elite, do: %{q | maxHp: q.maxHp * 2, xp: q.xp * 3, gold: q.gold * 3}, else: q
    Map.merge(q, %{hp: q.maxHp, tower: true, elite: m.elite})
  end

  # ---------- Vào, lên tầng, rời tháp ----------

  def enter(p, floor) do
    best = Map.get(p, :tower_best, 0)

    cond do
      p.battle -> {%{ok: false, msg: "Đang trong trận đấu."}, p}
      floor not in starts(best) -> {%{ok: false, msg: "Chưa mở tầng này."}, p}
      p.hp <= 0 -> {%{ok: false, msg: "Bạn cần hồi máu trước."}, p}
      true -> {%{ok: true, msg: "Vào Tháp Vô Tận, tầng #{floor}."}, go_floor(p, floor)}
    end
  end

  defp go_floor(p, floor) do
    t = build(floor, "#{p.name}|#{System.unique_integer([:positive])}")
    [ex, ey] = t.exit
    %{p | pos: %{map: @map, x: ex, y: ey - 1}} |> Map.put(:tower, t)
  end

  @doc "Thưởng khi vượt qua tầng `floor`."
  def floor_reward(floor) do
    boss? = rem(floor, 5) == 0
    k = if boss?, do: 3, else: 1

    pot =
      cond do
        floor >= 20 -> "potion_l"
        floor >= 9 -> "potion_m"
        true -> "potion_s"
      end

    %{
      gold: round((3 + floor * 2.2) * 3 * k),
      xp: round((8 + floor * 6 + floor * floor * 0.5) * k),
      items: if(boss?, do: %{pot => 2}, else: %{})
    }
  end

  @doc "Bước lên cầu thang: nhận thưởng, cập nhật kỷ lục, sang tầng mới."
  def climb(%{tower: t} = p) do
    left = length(t.monsters)

    if left > 0 do
      {%{ok: false, msg: "Hạ hết quái để mở cầu thang (còn #{left})."}, p}
    else
      r = floor_reward(t.floor)
      p = %{p | gold: p.gold + r.gold}
      p = Enum.reduce(r.items, p, fn {id, n}, p -> Engine.add_item(p, id, n) end)
      {_levels, p} = Engine.gain_xp(p, r.xp)
      p = Map.put(p, :tower_best, max(Map.get(p, :tower_best, 0), t.floor))
      extra = if r.items == %{}, do: "", else: ", bình máu"

      {%{ok: true, msg: "Vượt tầng #{t.floor}! +#{r.gold} vàng, +#{r.xp} kinh nghiệm#{extra}."},
       go_floor(p, t.floor + 1)}
    end
  end

  @doc "Trận trong tháp vừa kết thúc."
  def after_battle(
        %{tower: t, battle: %{over: true, result: result, encounter: %{tower: id}}} = p
      )
      when t != nil do
    case result do
      "win" -> %{p | tower: %{t | monsters: Enum.reject(t.monsters, &(&1.id == id))}}
      "lose" -> %{p | tower: nil}
      _ -> p
    end
  end

  def after_battle(p), do: p
end
