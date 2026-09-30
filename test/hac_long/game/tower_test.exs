defmodule HacLong.Game.TowerTest do
  use ExUnit.Case, async: false

  alias HacLong.Game.{Commands, Tower}
  alias HacLong.World

  defp player(attrs \\ %{}) do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Leo Tháp", "cls" => "warrior"})
    Map.merge(p, attrs)
  end

  # các ô đi tới được từ chỗ bắt đầu (không đi xuyên quái)
  defp reachable(t) do
    [ex, ey] = t.exit

    grid =
      for {row, y} <- Enum.with_index(t.tiles),
          {c, x} <- Enum.with_index(String.graphemes(row)),
          into: %{},
          do: {{x, y}, c}

    walk(grid, [{ex, ey - 1}], MapSet.new([{ex, ey - 1}]))
  end

  defp walk(_g, [], seen), do: seen

  defp walk(g, [{x, y} | rest], seen) do
    next =
      for {dx, dy} <- [{1, 0}, {-1, 0}, {0, 1}, {0, -1}],
          p = {x + dx, y + dy},
          g[p] in [".", ">", "<"],
          p not in seen,
          do: p

    walk(g, next ++ rest, Enum.reduce(next, seen, &MapSet.put(&2, &1)))
  end

  test "mỗi tầng: cầu thang và mọi con quái đều tới được; trùm tầng mỗi 5 tầng" do
    for floor <- 1..40, salt <- ["a", "b"] do
      t = Tower.build(floor, salt)
      seen = reachable(t)
      assert List.to_tuple(t.stairs) in seen, "tầng #{floor}: không tới được cầu thang"

      for m <- t.monsters do
        near = for {dx, dy} <- [{1, 0}, {-1, 0}, {0, 1}, {0, -1}], do: {m.x + dx, m.y + dy}
        assert Enum.any?(near, &(&1 in seen)), "tầng #{floor}: không tới được #{m.kind}"
        assert m.level >= floor
      end

      assert Enum.any?(t.monsters, & &1.elite) == (rem(floor, 5) == 0)
    end

    assert Tower.build(7, "a") == Tower.build(7, "a")
    assert Tower.build(7, "a") != Tower.build(7, "b")
    # càng lên cao quái càng mạnh, không có trần
    weak = Tower.battle_monster(%{kind: "bat", name: "Dơi", level: 30, elite: false})
    strong = Tower.battle_monster(%{kind: "bat", name: "Dơi", level: 60, elite: false})
    assert strong.maxHp > weak.maxHp * 3
  end

  test "mốc bắt đầu theo kỷ lục" do
    assert Tower.starts(0) == [1]
    assert Tower.starts(9) == [1]
    assert Tower.starts(10) == [1, 11]
    assert Tower.starts(23) == [1, 11, 21]
  end

  test "vào tháp ở Người Gác Tháp, không vào tầng chưa mở" do
    guard = %{map: "village", x: 21, y: 9}
    p = player(%{pos: guard})

    assert {%{ok: false, msg: "Chưa mở tầng này."}, _} =
             Commands.run(p, %{"act" => "tower_enter", "floor" => 11})

    assert {%{ok: false}, _} =
             Commands.run(%{p | pos: %{guard | y: 13}}, %{"act" => "tower_enter"})

    {%{ok: true}, p} = Commands.run(p, %{"act" => "tower_enter"})
    assert p.pos.map == "tower" and p.tower.floor == 1

    assert {%{ok: true}, p2} =
             Commands.run(%{p | tower_best: 12, pos: guard, tower: nil}, %{
               "act" => "tower_enter",
               "floor" => 11
             })

    assert p2.tower.floor == 11
  end

  test "hạ hết quái thì lên tầng, nhận thưởng, lập kỷ lục; gục ngã thì hết lượt" do
    {%{ok: true}, p} =
      Commands.run(player(%{pos: %{map: "village", x: 21, y: 9}}), %{"act" => "tower_enter"})

    t = p.tower
    [sx, sy] = t.stairs
    at_stairs = %{p | pos: %{map: "tower", x: sx, y: sy + 1}}
    uid = System.unique_integer([:positive])

    assert {%{ok: false, msg: msg}, _} = World.move(at_stairs, uid, "up")
    assert msg =~ "Hạ hết quái"

    # đánh con quái đầu tiên: đặt nó ngay trước mặt
    [m | _] = t.monsters
    [ex, ey] = t.exit
    start = {ex, ey - 1}
    p = %{p | tower: %{t | monsters: [%{m | x: elem(start, 0), y: elem(start, 1) - 1}]}}
    {%{ok: true}, fighting} = World.move(p, uid, "up")
    assert fighting.battle.monster.tower and fighting.battle.encounter == %{tower: m.id}

    won =
      put_in(fighting.battle, %{fighting.battle | over: true, result: "win"})
      |> Tower.after_battle()

    assert won.tower.monsters == []

    ready = %{won | battle: nil, pos: at_stairs.pos}
    {%{ok: true, msg: msg}, up} = World.move(ready, uid, "up")
    assert msg =~ "Vượt tầng 1"
    assert up.tower.floor == 2 and up.tower_best == 1
    assert up.gold == ready.gold + Tower.floor_reward(1).gold

    lost =
      put_in(fighting.battle, %{fighting.battle | over: true, result: "lose"})
      |> Tower.after_battle()

    assert lost.tower == nil
  end

  test "đi cầu thang xuống thì về Làng cạnh Người Gác Tháp" do
    {%{ok: true}, p} =
      Commands.run(player(%{pos: %{map: "village", x: 21, y: 9}}), %{"act" => "tower_enter"})

    uid = System.unique_integer([:positive])
    {%{ok: true, msg: msg}, out} = World.move(p, uid, "down")
    assert msg =~ "Rời Tháp"
    assert out.pos == %{map: "village", x: 21, y: 9} and out.tower == nil
    HacLong.World.MapServer.leave("village", uid)
  end
end
