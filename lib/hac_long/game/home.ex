defmodule HacLong.Game.Home do
  @moduledoc """
  Trang trí nhà: mua đồ trang trí ở Thợ Mộc, đặt vào các ô trống trong Nhà.
  Hàm thuần, như `Engine`.

  - `furniture: %{id => số}`: đồ đã mua còn cất trong kho; `decor: [%{id, x, y}]`: đồ đã đặt.
  - Đồ đã đặt chặn đường như NPC; không được đặt làm chắn lối (mọi ô trống trong nhà vẫn phải
    đi tới được từ cửa) hay đặt lên chỗ đứng trước cửa.
  - Tổng điểm tiện nghi (`comfort`) của đồ đã đặt: cứ 10 điểm được +1% kinh nghiệm mỗi trận,
    tối đa +5% (`xp_bonus/1`).
  """

  alias HacLong.Game.Data
  alias HacLong.World.Maps

  @max_decor 20

  def max_decor, do: @max_decor

  defp stock(p), do: Map.get(p, :furniture) || %{}
  def decor(p), do: Map.get(p, :decor) || []

  def comfort(p) do
    p
    |> decor()
    |> Enum.map(fn d -> (Data.furniture(d.id) || %{comfort: 0}).comfort end)
    |> Enum.sum()
  end

  def xp_bonus(p), do: min(0.05, div(comfort(p), 10) * 0.01)

  def at(p, x, y), do: Enum.find(decor(p), &(&1.x == x and &1.y == y))

  def buy(p, id) do
    f = Data.furniture(id)

    cond do
      f == nil ->
        {%{ok: false, msg: "Không có món này."}, p}

      p.gold < f.price ->
        {%{ok: false, msg: "Cần #{f.price} vàng."}, p}

      true ->
        p = %{p | gold: p.gold - f.price}
        p = Map.put(p, :furniture, Map.update(stock(p), id, 1, &(&1 + 1)))
        {%{ok: true, msg: "Đã mua #{f.name}. Về Nhà bấm Trang trí để đặt."}, p}
    end
  end

  defp at_home?(p), do: p.pos.map == Maps.home()

  def place(p, id, x, y) do
    f = Data.furniture(id)
    home = Maps.get(Maps.home())

    cond do
      not at_home?(p) ->
        {%{ok: false, msg: "Hãy về Nhà để trang trí."}, p}

      f == nil or Map.get(stock(p), id, 0) <= 0 ->
        {%{ok: false, msg: "Bạn không có món này trong kho."}, p}

      length(decor(p)) >= @max_decor ->
        {%{ok: false, msg: "Nhà đã đầy đồ (tối đa #{@max_decor} món)."}, p}

      not is_integer(x) or not is_integer(y) ->
        {%{ok: false, msg: "Chỗ đặt không hợp lệ."}, p}

      not free?(p, home, x, y) ->
        {%{ok: false, msg: "Không đặt được ở ô này."}, p}

      blocks_path?(p, home, x, y) ->
        {%{ok: false, msg: "Đặt ở đây sẽ chắn lối đi."}, p}

      true ->
        n = Map.get(stock(p), id)
        rest = if n > 1, do: Map.put(stock(p), id, n - 1), else: Map.delete(stock(p), id)

        p =
          p
          |> Map.put(:furniture, rest)
          |> Map.put(:decor, decor(p) ++ [%{id: id, x: x, y: y}])

        {%{ok: true, msg: "Đã đặt #{f.name}."}, p}
    end
  end

  def take(p, x, y) do
    case at_home?(p) && at(p, x, y) do
      %{id: id} = d ->
        p =
          p
          |> Map.put(:decor, List.delete(decor(p), d))
          |> Map.put(:furniture, Map.update(stock(p), id, 1, &(&1 + 1)))

        {%{ok: true, msg: "Đã cất #{Data.furniture(id).name} vào kho."}, p}

      _ ->
        {%{ok: false, msg: "Không có đồ ở ô này."}, p}
    end
  end

  # ô trống: đi được, không phải cổng, không có NPC, không có đồ, không phải chỗ đứng
  # của mình hay chỗ đứng trước cửa
  defp free?(p, home, x, y) do
    {sx, sy} = spawn_pos()

    Maps.walkable?(home, x, y) and Maps.portal_at(home, x, y) == nil and at(p, x, y) == nil and
      {x, y} != {sx, sy} and {x, y} != {p.pos.x, p.pos.y}
  end

  defp spawn_pos do
    %{x: x, y: y} = Maps.home_spawn()
    {x, y}
  end

  # sau khi đặt thêm ở (x, y), mọi ô trống còn lại phải đi tới được từ chỗ đứng trước cửa
  defp blocks_path?(p, home, x, y) do
    blocked = MapSet.new([{x, y} | Enum.map(decor(p), &{&1.x, &1.y})])
    open? = fn {cx, cy} -> Maps.walkable?(home, cx, cy) and {cx, cy} not in blocked end

    all =
      for cy <- 0..(home.height - 1), cx <- 0..(home.width - 1), open?.({cx, cy}), do: {cx, cy}

    start = spawn_pos()
    MapSet.size(flood([start], MapSet.new([start]), open?)) < length(all)
  end

  defp flood([], seen, _open?), do: seen

  defp flood([{x, y} | rest], seen, open?) do
    next =
      for {dx, dy} <- [{1, 0}, {-1, 0}, {0, 1}, {0, -1}],
          q = {x + dx, y + dy},
          open?.(q),
          q not in seen,
          do: q

    flood(next ++ rest, Enum.reduce(next, seen, &MapSet.put(&2, &1)), open?)
  end
end
