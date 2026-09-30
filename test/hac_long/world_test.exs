defmodule HacLong.WorldTest do
  # Các bản đồ dùng chung là tiến trình toàn cục nên không chạy song song.
  use ExUnit.Case, async: false

  alias HacLong.Game.{Commands, Engine}
  alias HacLong.World
  alias HacLong.World.{Maps, MapServer}

  setup do
    MapServer.clear_monsters("forest")
    MapServer.clear_monsters("camp")
    uid = System.unique_integer([:positive])
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Đi Bộ", "cls" => "warrior"})

    on_exit(fn ->
      for id <- ~w(village forest camp), do: MapServer.leave(id, uid)
    end)

    %{uid: uid, p: p}
  end

  defp at(p, map, x, y), do: %{p | pos: %{map: map, x: x, y: y}}

  # Một ô đi được trong bản đồ mà ô bên phải và ô bên trên cũng đi được (không phải cổng).
  defp open_spot(map_id) do
    map = Maps.get(map_id)
    ok? = fn x, y -> Maps.walkable?(map, x, y) and Maps.portal_at(map, x, y) == nil end

    hd(
      for y <- 1..(map.height - 2),
          x <- 1..(map.width - 2),
          ok?.(x, y) and ok?.(x + 1, y) and ok?.(x, y - 1),
          do: {x, y}
    )
  end

  test "các bản đồ hợp lệ: cổng nối hai chiều, chỗ đứng đi được" do
    for id <- Maps.ids(), map = Maps.get(id), portal <- map.portals do
      target = Maps.get(portal.to)
      assert target, "#{id}: cổng tới #{portal.to} không tồn tại"
      {x, y} = portal.spawn
      assert Maps.walkable?(target, x, y) and Maps.portal_at(target, x, y) == nil
      assert Enum.any?(target.portals, &(&1.to == id)), "#{portal.to} không có cổng về #{id}"
    end

    home = Maps.home_spawn()
    assert Maps.walkable?(Maps.get("home"), home.x, home.y)
  end

  test "đi trong nhà, tường chặn, giếng hồi máu", %{uid: uid, p: p} do
    assert p.pos == %{map: "home", x: 5, y: 6}
    {%{ok: true}, p} = World.move(p, uid, "up")
    assert p.pos.y == 5

    {%{ok: false}, ^p} =
      World.move(at(p, "home", 1, 1), uid, "left") |> then(fn {r, _} -> {r, p} end)

    {%{ok: false, msg: "Hướng đi không hợp lệ."}, _} = World.move(p, uid, "bay")

    p = at(%{p | hp: 5}, "home", 8, 1)
    {%{ok: true, msg: msg}, p} = World.move(p, uid, "right")
    assert msg =~ "nước giếng"
    assert p.hp == Engine.derived(p).maxHp and p.pos.x == 8
  end

  test "cổng vào vùng chưa mở bị khóa", %{uid: uid, p: p} do
    p = at(p, "village", 18, 1)
    World.enter(p, uid)

    assert {%{ok: false, msg: "Hạ Sói Xám Đầu Đàn để mở Trại Goblin."}, ^p} =
             World.move(p, uid, "up")

    {%{ok: true}, p2} = World.move(%{p | bosses: ["wolf"]}, uid, "up")
    assert p2.pos.map == "camp"
    snap = MapServer.snapshot("camp")
    assert Enum.any?(snap.players, &(&1.id == uid))
    refute Enum.any?(MapServer.snapshot("village").players, &(&1.id == uid))
  end

  test "chạm quái thì vào trận, người khác không tranh được", %{uid: uid, p: p} do
    {x, y} = open_spot("forest")
    p = at(p, "forest", x, y)
    World.enter(p, uid)
    m = MapServer.put_monster("forest", "spider", {x + 1, y})

    {%{ok: true}, fighting} = World.move(p, uid, "right")
    assert fighting.battle.monster.id == "spider"
    assert fighting.pos == p.pos

    other = System.unique_integer([:positive])
    q = at(p, "forest", x + 2, y)
    World.enter(q, other)
    assert {%{ok: false, msg: msg}, ^q} = World.move(q, other, "left")
    assert msg =~ "đang giao chiến"
    MapServer.leave("forest", other)

    # bỏ chạy: quái được nhả ra
    done = put_in(fighting.battle, %{fighting.battle | over: true, result: "fled"})
    World.finish_encounter(done, uid)
    assert [%{id: id, busy: false}] = MapServer.snapshot("forest").monsters
    assert id == m.id

    # thắng: quái biến mất
    {_, fighting} = World.move(p, uid, "right")
    won = put_in(fighting.battle, %{fighting.battle | over: true, result: "win"})
    assert World.finish_encounter(won, uid).pos == p.pos
    assert MapServer.snapshot("forest").monsters == []
  end

  test "gục ngã thì về nhà và rời bản đồ", %{uid: uid, p: p} do
    {x, y} = open_spot("forest")
    p = at(p, "forest", x, y)
    World.enter(p, uid)
    MapServer.put_monster("forest", "bat", {x, y - 1})
    {_, fighting} = World.move(p, uid, "up")
    lost = put_in(fighting.battle, %{fighting.battle | over: true, result: "lose"})
    p2 = World.finish_encounter(lost, uid)
    assert p2.pos == Maps.home_spawn()
    assert MapServer.snapshot("forest").players == []
    assert [%{busy: false}] = MapServer.snapshot("forest").monsters
  end

  test "trùm đứng ở chỗ riêng; quái sinh ra theo cấu hình" do
    # bản đồ Rừng Mê mới dựng có đủ quái theo `spawns` và trùm ở đúng chỗ
    map = Maps.get("forest")
    {:ok, s} = MapServer.init("forest")
    total = Enum.sum(Enum.map(map.spawns, & &1.max))
    assert map_size(s.monsters) == total + 1
    boss = Enum.find(Map.values(s.monsters), & &1.boss)
    assert boss.kind == "wolf" and boss.pos == map.boss.at

    for {_, m} <- s.monsters, not m.boss do
      {x, y} = m.pos
      assert Maps.walkable?(map, x, y) and Maps.portal_at(map, x, y) == nil
    end
  end
end
