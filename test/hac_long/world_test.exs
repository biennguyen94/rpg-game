defmodule HacLong.WorldTest do
  # Các bản đồ dùng chung là tiến trình toàn cục nên không chạy song song.
  use ExUnit.Case, async: false

  alias HacLong.Game.{Commands, Engine}
  alias HacLong.World
  alias HacLong.World.{Maps, MapServer}

  setup do
    for id <- ~w(forest_1 forest_2 forest_boss camp_1), do: MapServer.clear_monsters(id)
    uid = System.unique_integer([:positive])
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Đi Bộ", "cls" => "warrior"})

    on_exit(fn ->
      for id <- ~w(village forest_1 forest_2 forest_boss camp_1), do: MapServer.leave(id, uid)
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
    assert p2.pos.map == "camp_1"
    snap = MapServer.snapshot("camp_1")
    assert Enum.any?(snap.players, &(&1.id == uid))
    refute Enum.any?(MapServer.snapshot("village").players, &(&1.id == uid))
  end

  test "chạm quái thì vào trận, người khác không tranh được", %{uid: uid, p: p} do
    {x, y} = open_spot("forest_1")
    p = at(p, "forest_1", x, y)
    World.enter(p, uid)
    m = MapServer.put_monster("forest_1", "spider", {x + 1, y})

    {%{ok: true}, fighting} = World.move(p, uid, "right")
    assert fighting.battle.monster.id == "spider"
    assert fighting.pos == p.pos

    other = System.unique_integer([:positive])
    q = at(p, "forest_1", x + 2, y)
    World.enter(q, other)
    assert {%{ok: false, msg: msg}, ^q} = World.move(q, other, "left")
    assert msg =~ "đang giao chiến"
    MapServer.leave("forest_1", other)

    # bỏ chạy: quái được nhả ra
    done = put_in(fighting.battle, %{fighting.battle | over: true, result: "fled"})
    World.finish_encounter(done, uid)
    assert [%{id: id, busy: false}] = MapServer.snapshot("forest_1").monsters
    assert id == m.id

    # thắng: quái biến mất
    {_, fighting} = World.move(p, uid, "right")
    won = put_in(fighting.battle, %{fighting.battle | over: true, result: "win"})
    assert World.finish_encounter(won, uid).pos == p.pos
    assert MapServer.snapshot("forest_1").monsters == []
  end

  test "gục ngã thì về nhà và rời bản đồ", %{uid: uid, p: p} do
    {x, y} = open_spot("forest_1")
    p = at(p, "forest_1", x, y)
    World.enter(p, uid)
    MapServer.put_monster("forest_1", "bat", {x, y - 1})
    {_, fighting} = World.move(p, uid, "up")
    lost = put_in(fighting.battle, %{fighting.battle | over: true, result: "lose"})
    p2 = World.finish_encounter(lost, uid)
    assert p2.pos == Maps.home_spawn()
    assert MapServer.snapshot("forest_1").players == []
    assert [%{busy: false}] = MapServer.snapshot("forest_1").monsters
  end

  test "trùm đứng trong phòng riêng; quái sinh ra theo cấu hình" do
    # bản đồ mới dựng có đủ quái theo `spawns`, đứng ở ô đi được
    map = Maps.get("forest_1")
    {:ok, s} = MapServer.init("forest_1")
    assert map_size(s.monsters) == Enum.sum(Enum.map(map.spawns, & &1.max))
    refute Enum.any?(Map.values(s.monsters), & &1.boss)

    for {_, m} <- s.monsters do
      {x, y} = m.pos
      assert Maps.walkable?(map, x, y) and Maps.portal_at(map, x, y) == nil
    end

    room = Maps.get("forest_boss")
    {:ok, s} = MapServer.init("forest_boss")
    assert [boss] = Map.values(s.monsters)
    assert boss.kind == "wolf" and boss.boss and boss.pos == room.boss.at
  end

  test "mỗi vùng: bản đồ 1 → bản đồ 2 → phòng trùm; quái bản đồ 2 mạnh hơn" do
    for {z, zi} <- Enum.with_index(HacLong.Game.Data.zones()) do
      one = Maps.get("#{z.id}_1")
      two = Maps.get("#{z.id}_2")
      room = Maps.get("#{z.id}_boss")
      assert one.zone == zi and two.zone == zi and room.zone == zi
      assert Enum.map(one.portals, & &1.to) |> Enum.sort() == Enum.sort(["village", two.id])
      assert Enum.map(two.portals, & &1.to) |> Enum.sort() == Enum.sort([one.id, room.id])
      assert two.waystone
      level = fn m -> Enum.find(z.monsters, &(&1.id == m.monster)).level end
      assert Enum.max(Enum.map(two.spawns, level)) >= Enum.max(Enum.map(one.spawns, level))
    end
  end

  test "trùm: hỏi xác nhận trước khi đấu", %{uid: uid, p: p} do
    room = Maps.get("forest_boss")
    {bx, by} = room.boss.at
    MapServer.put_monster("forest_boss", "wolf", {bx, by}, true)
    p = at(p, "forest_boss", bx, by + 1)
    World.enter(p, uid)

    assert {%{ok: false, confirm: "boss", boss: %{name: "Sói Xám Đầu Đàn", level: 6}}, ^p} =
             World.move(p, uid, "up")

    assert [%{busy: false}] = MapServer.snapshot("forest_boss").monsters
    {%{ok: true}, fighting} = World.move(p, uid, "up", true)
    assert fighting.battle.monster.boss
  end

  test "đá dịch chuyển: ghi nhớ khi chạm, chỉ dùng được khi đứng cạnh", %{uid: uid, p: p} do
    two = Maps.get("forest_2")
    {wx, wy} = two.waystone.at
    {sx, sy} = two.waystone.spawn
    p = at(p, "forest_2", sx, sy)
    World.enter(p, uid)
    assert World.waystones(p) == ["village"]

    dir = if sy > wy, do: "up", else: "down"
    assert sx == wx
    {%{ok: true, waystone: true, msg: msg}, p} = World.move(p, uid, dir)
    assert msg =~ "Đã ghi nhớ"
    assert World.waystones(p) == ["village", "forest_2"]

    {%{ok: true}, in_village} = World.teleport(p, uid, "village")
    v = Maps.get("village").waystone
    assert in_village.pos == %{map: "village", x: elem(v.spawn, 0), y: elem(v.spawn, 1)}

    # từ Làng quay lại Rừng Mê 2 được vì đã ghi nhớ; nơi chưa tới thì không
    {%{ok: true}, back} = World.teleport(in_village, uid, "forest_2")
    assert back.pos.map == "forest_2"

    assert {%{ok: false, msg: "Bạn chưa tới đá dịch chuyển đó."}, _} =
             World.teleport(in_village, uid, "camp_2")

    assert {%{ok: false}, _} = World.teleport(in_village, uid, "home")

    far = at(in_village, "village", 12, 15)

    assert {%{ok: false, msg: "Hãy đứng cạnh đá dịch chuyển."}, _} =
             World.teleport(far, uid, "forest_2")
  end
end
