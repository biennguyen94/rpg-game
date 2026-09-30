defmodule HacLong.Game.CommandsTest do
  use ExUnit.Case, async: true

  alias HacLong.Game.{Commands, Engine, Rng}

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
          %{"act" => "hunt", "zone" => 3},
          %{"act" => "hunt", "zone" => 99},
          %{"act" => "hunt", "zone" => -1},
          %{"act" => "hunt", "zone" => "0; drop"},
          %{"act" => "boss", "zone" => nil},
          %{"act" => "equip", "id" => "relic"},
          %{"act" => "sell", "id" => "relic"},
          %{"act" => "use", "id" => "club"},
          %{"act" => "attack"},
          %{"act" => "again"},
          %{"act" => "hack"},
          %{"nothing" => true}
        ] do
      assert {%{ok: false}, ^p} = Commands.run(p, cmd), inspect(cmd)
    end
  end

  test "mua, bán, trang bị" do
    p = player()
    {%{ok: true}, p} = Commands.run(p, %{"act" => "buy", "id" => "potion_s", "n" => 2})
    assert p.gold == 0 and p.inv["potion_s"] == 5

    {%{ok: false, msg: "Không đủ vàng."}, _} =
      Commands.run(p, %{"act" => "buy", "id" => "potion_s"})

    p = %{p | gold: 500, level: 3}
    {%{ok: true}, p} = Commands.run(p, %{"act" => "buy", "id" => "dagger"})
    {%{ok: true}, p} = Commands.run(p, %{"act" => "equip", "id" => "dagger"})
    assert p.equip.weapon == "dagger" and p.inv["club"] == 1
    {%{ok: true}, p} = Commands.run(p, %{"act" => "sell", "id" => "club"})
    assert p.gold == 500 - 60 + 80
  end

  test "một trận đấu đầy đủ trên server" do
    Rng.put_sequence([0.5, 0.01, 0.99, 0.3])
    p = player()
    {%{ok: true}, p} = Commands.run(p, %{"act" => "hunt", "zone" => "0"})
    assert p.battle.monster.level <= 2

    p =
      Enum.reduce_while(1..100, p, fn _, p ->
        {_, p} = Commands.run(p, %{"act" => "attack"})
        if p.battle.over, do: {:halt, p}, else: {:cont, p}
      end)

    assert p.battle.over
    assert {%{ok: false}, _} = Commands.run(p, %{"act" => "hunt", "zone" => 0})
    {%{ok: true}, p2} = Commands.run(p, %{"act" => "leave"})
    assert p2.battle == nil
  after
    Rng.clear()
  end
end
