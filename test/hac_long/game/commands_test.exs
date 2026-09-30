defmodule HacLong.Game.CommandsTest do
  use ExUnit.Case, async: true

  alias HacLong.Game.{Commands, Data, Engine, Quests, Rng}

  defp player do
    {_, p} =
      Commands.run(nil, %{"act" => "create", "name" => "  Lãng Khách  ", "cls" => "warrior"})

    p
  end

  test "tạo nhân vật" do
    p = player()
    assert p.name == "Lãng Khách"
    assert p.hp == Engine.derived(p).maxHp

    assert {%{ok: false}, nil} =
             Commands.run(nil, %{"act" => "create", "name" => "x", "cls" => "mage"})

    assert {%{ok: false}, nil} = Commands.run(nil, %{"act" => "rest"})

    assert {%{ok: false}, ^p} =
             Commands.run(p, %{"act" => "create", "name" => "x", "cls" => "rogue"})
  end

  test "từ chối dữ liệu gian lận hoặc sai kiểu" do
    p = player()

    for cmd <- [
          %{"act" => "buy", "id" => "potion_s", "n" => -10},
          %{"act" => "buy", "id" => "potion_s", "n" => 1000},
          %{"act" => "buy", "id" => "potion_s", "n" => "abc"},
          # đồ khởi đầu giá 0 không được mua (trước đây mua 0 vàng rồi bán 80 vàng)
          %{"act" => "buy", "id" => "club"},
          %{"act" => "buy", "id" => "relic"},
          %{"act" => "buy", "id" => %{"x" => 1}},
          %{"act" => "alloc", "stat" => "str", "n" => -5},
          %{"act" => "alloc", "stat" => "hp", "n" => 1},
          %{"act" => "equip", "id" => "relic"},
          %{"act" => "sell", "id" => "relic"},
          %{"act" => "use", "id" => "club"},
          %{"act" => "attack"},
          %{"act" => "hack"},
          %{"nothing" => true}
        ] do
      assert {%{ok: false}, ^p} = Commands.run(p, cmd), inspect(cmd)
    end
  end

  # chỗ đứng cạnh các NPC trong Làng
  @smith %{map: "village", x: 8, y: 11}
  @herbalist %{map: "village", x: 16, y: 13}
  @inn %{map: "village", x: 16, y: 1}
  @elder %{map: "village", x: 12, y: 4}

  test "mua, bán ở Thợ Rèn/Bà Lang; mỗi người bán hàng của mình" do
    p = %{player() | pos: @herbalist}
    {%{ok: true}, p} = Commands.run(p, %{"act" => "buy", "id" => "potion_s", "n" => 2})
    assert p.gold == 0 and p.inv["potion_s"] == 5

    {%{ok: false, msg: "Không đủ vàng."}, _} =
      Commands.run(p, %{"act" => "buy", "id" => "potion_s"})

    assert {%{ok: false, msg: "Bà Lang không bán món này."}, _} =
             Commands.run(%{p | gold: 500, level: 3}, %{"act" => "buy", "id" => "dagger"})

    p = %{p | gold: 500, level: 3, pos: @smith}
    {%{ok: true}, p} = Commands.run(p, %{"act" => "buy", "id" => "dagger"})
    {%{ok: true}, p} = Commands.run(p, %{"act" => "equip", "id" => "dagger"})
    assert p.equip.weapon == "dagger" and p.inv["club"] == 1
    {%{ok: true}, p} = Commands.run(p, %{"act" => "sell", "id" => "club"})
    assert p.gold == 500 - 60 + 80

    # xa NPC thì không mua bán được
    far = %{p | pos: %{map: "village", x: 12, y: 15}}

    assert {%{ok: false, msg: "Hãy đến gặp Thợ Rèn hoặc Bà Lang."}, _} =
             Commands.run(far, %{"act" => "buy", "id" => "dagger"})

    assert {%{ok: false}, _} = Commands.run(far, %{"act" => "sell", "id" => "dagger"})
  end

  test "pha thuốc ở Bà Lang" do
    p = %{player() | pos: @herbalist, inv: %{"herb" => 5}}

    {%{ok: true, msg: "Pha được Bình Máu Nhỏ."}, p2} =
      Commands.run(p, %{"act" => "craft", "id" => "brew_s"})

    assert p2.inv == %{"herb" => 3, "potion_s" => 1}
    {%{ok: true}, p3} = Commands.run(p, %{"act" => "craft", "id" => "brew_m"})
    assert p3.inv == %{"potion_m" => 1}

    assert {%{ok: false, msg: "Chưa đủ nguyên liệu."}, _} =
             Commands.run(p, %{"act" => "craft", "id" => "brew_l"})

    assert {%{ok: false}, _} =
             Commands.run(%{p | pos: @smith}, %{"act" => "craft", "id" => "brew_s"})
  end

  test "nhận, làm và trả nhiệm vụ ở Trưởng Làng" do
    p = %{player() | pos: @elder}

    # nhiệm vụ trùm cần xong nhiệm vụ diệt quái trước; vùng chưa mở thì chưa nhận được
    assert {%{ok: false}, _} = Commands.run(p, %{"act" => "quest_accept", "id" => "forest_boss"})
    assert {%{ok: false}, _} = Commands.run(p, %{"act" => "quest_accept", "id" => "camp_kill"})
    {%{ok: true}, p} = Commands.run(p, %{"act" => "quest_accept", "id" => "forest_kill"})
    {%{ok: true}, p} = Commands.run(p, %{"act" => "quest_accept", "id" => "forest_collect"})

    assert {%{ok: false, msg: "Chưa hoàn thành."}, _} =
             Commands.run(p, %{"act" => "quest_turnin", "id" => "forest_kill"})

    p = Enum.reduce(1..5, p, fn _, p -> Quests.on_kill(p, "bat") end)
    p = Quests.on_kill(p, "jackal")
    assert Quests.progress(p, Data.quest("forest_kill")) == {5, 5}

    gold = p.gold
    {%{ok: true}, p} = Commands.run(p, %{"act" => "quest_turnin", "id" => "forest_kill"})
    assert p.gold == gold + Data.quest("forest_kill").reward.gold
    assert p.inv["potion_s"] == 3 + 2
    assert p.quests.done == ["forest_kill"]
    assert {%{ok: false}, _} = Commands.run(p, %{"act" => "quest_accept", "id" => "forest_kill"})

    # nộp nguyên liệu thì bị trừ khỏi túi
    p = Engine.add_item(p, "herb", 6)
    {%{ok: true}, p} = Commands.run(p, %{"act" => "quest_turnin", "id" => "forest_collect"})
    assert p.inv["herb"] == 1

    # xa Trưởng Làng thì không nhận được
    assert {%{ok: false, msg: "Hãy đến gặp Trưởng Làng."}, _} =
             Commands.run(%{p | pos: @smith}, %{"act" => "quest_accept", "id" => "forest_boss"})

    {%{ok: true}, _} = Commands.run(p, %{"act" => "quest_accept", "id" => "forest_boss"})
  end

  test "một trận đấu đầy đủ trên server" do
    Rng.put_sequence([0.5, 0.01, 0.99, 0.3])
    {%{ok: true}, p} = Engine.start_battle(player(), 0, false)
    assert p.battle.monster.level <= 2

    p =
      Enum.reduce_while(1..100, p, fn _, p ->
        {_, p} = Commands.run(p, %{"act" => "attack"})
        if p.battle.over, do: {:halt, p}, else: {:cont, p}
      end)

    assert p.battle.over
    {%{ok: true}, p2} = Commands.run(p, %{"act" => "leave"})
    assert p2.battle == nil
  after
    Rng.clear()
  end

  test "không còn săn quái bằng nút; nghỉ trọ ở Chủ Quán Trọ" do
    p = %{player() | hp: 10}

    for act <- ~w(hunt boss again),
        do: assert({%{ok: false}, ^p} = Commands.run(p, %{"act" => act, "zone" => 0}))

    assert {%{ok: true}, _} = Commands.run(%{p | pos: @inn}, %{"act" => "rest"})

    assert {%{ok: false, msg: "Hãy đến gặp Chủ Quán Trọ ở Làng."}, _} =
             Commands.run(%{p | pos: %{map: "village", x: 12, y: 15}}, %{"act" => "rest"})
  end
end
