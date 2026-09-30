defmodule HacLong.Game.HomePetsTest do
  use ExUnit.Case, async: true

  alias HacLong.Game.{Engine, Home, Pets}
  alias HacLong.World.Maps

  defp player(gold \\ 100_000) do
    {:ok, p} = Engine.new_player("Thử", "warrior")
    %{p | gold: gold} |> Map.put(:pos, Maps.home_spawn())
  end

  test "mua thú cưng, dắt theo thì cộng chỉ số" do
    p = player()
    base = Engine.derived(p)
    assert {%{ok: false, msg: "Cần 1500 vàng."}, _} = Pets.buy(player(10), "sheep")

    {%{ok: true}, p} = Pets.buy(p, "sheep")
    assert p.pet == "sheep" and p.pets == ["sheep"] and p.gold == 100_000 - 1500
    assert Engine.derived(p).maxHp == round(base.maxHp * 1.05)
    assert {%{ok: false, msg: "Bạn đã có Cừu Bông rồi."}, _} = Pets.buy(p, "sheep")

    {%{ok: true}, p} = Pets.buy(p, "hound")
    assert Engine.derived(p).atk == round(base.atk * 1.04)
    assert Engine.look(p).pet == "hound"
    {_, p} = Pets.choose(p, nil)
    assert Engine.derived(p) == base
    assert {%{ok: false}, _} = Pets.choose(p, "hippogriff")
  end

  test "ngoại hình theo đồ đang mặc" do
    p = player()

    assert Engine.look(p) == %{
             hair: "hair/knot_red",
             weapon: "hand1/club_slant",
             armor: "body/shirt_vest",
             shield: nil,
             pet: nil
           }
  end

  test "đặt và cất đồ trang trí; không chắn lối, không đặt chỗ đứng trước cửa" do
    p = player()
    {%{ok: true}, p} = Home.buy(p, "statue_cat")
    assert p.furniture == %{"statue_cat" => 1}

    %{x: sx, y: sy} = Maps.home_spawn()
    assert {%{ok: false, msg: "Không đặt được ở ô này."}, _} = Home.place(p, "statue_cat", sx, sy)
    # ô tường
    assert {%{ok: false}, _} = Home.place(p, "statue_cat", 0, 0)

    {%{ok: true}, p} = Home.place(p, "statue_cat", 3, 3)
    assert p.furniture == %{}
    assert [%{id: "statue_cat", x: 3, y: 3}] = p.decor
    assert Home.comfort(p) == 3

    assert {%{ok: false, msg: "Bạn không có món này trong kho."}, _} =
             Home.place(p, "statue_cat", 4, 3)

    # đồ đặt rồi thì chặn đường
    q = %{p | pos: %{map: "home", x: 3, y: 4}}
    assert {%{ok: false}, ^q} = HacLong.World.move(q, 0, "up")

    {%{ok: true}, p} = Home.take(p, 3, 3)
    assert p.decor == [] and p.furniture == %{"statue_cat" => 1}

    # không cho chắn kín một góc: quây ô (1,6) bằng hai món ở (1,5) và (2,6)
    p = p |> Home.buy("plant") |> elem(1) |> Home.buy("plant") |> elem(1)
    {%{ok: true}, p} = Home.place(p, "plant", 1, 5)
    assert {%{ok: false, msg: "Đặt ở đây sẽ chắn lối đi."}, _} = Home.place(p, "plant", 2, 6)
  end

  test "nhà tiện nghi thì thêm kinh nghiệm, tối đa 5%" do
    p = player()
    assert Home.xp_bonus(p) == 0
    p = Map.put(p, :decor, for(x <- 1..4, do: %{id: "golden_statue", x: x, y: 2}))
    assert Home.comfort(p) == 32 and Home.xp_bonus(p) == 0.03
    p = Map.put(p, :decor, for(x <- 1..8, do: %{id: "golden_statue", x: x, y: 2}))
    assert Home.xp_bonus(p) == 0.05
  end

  test "thú đi theo cắn thêm một đòn trong trận" do
    on_exit(&HacLong.Game.Rng.clear/0)
    assert Pets.bite(player(), 100, 0.0) == 0
    {_, p} = Pets.buy(player(), "hound")
    assert Pets.bite(p, 100, 0.1) == 25
    assert Pets.bite(p, 100, 0.9) == 0
    assert Pets.bite(p, 1, 0.1) == 1

    # quái trâu, không né; số ngẫu nhiên toàn 0 thì thú luôn cắn
    {_, p} = Engine.start_battle(p, 0, false)
    p = put_in(p.battle.monster.hp, 100_000) |> put_in([:battle, :monster, :dodge], 0)
    HacLong.Game.Rng.put_sequence([0.0])
    {_, p} = Engine.act(p, "attack")
    assert Enum.any?(p.battle.log, &(&1.text =~ "🐾 Chó Săn cắn thêm"))
  end

  test "thuần phục quái đã hạ đủ 100 con" do
    p = player()

    assert {%{ok: false, msg: "Cần hạ ít nhất 100 con (mới 0)."}, _} = Pets.tame(p, "bat")
    assert {%{ok: false}, _} = Pets.tame(p, "wolf")
    assert {%{ok: false}, _} = Pets.tame(p, "nope")
    assert {%{ok: false}, _} = Pets.tame(p, nil)

    p = Map.put(p, :bestiary, %{"bat" => 100})
    assert [%{id: "bat", price: 1100}] = Pets.tameable(p)
    base = Engine.derived(p)

    {%{ok: true}, p} = Pets.tame(p, "bat")
    assert p.pet == "tame:bat" and p.pets == ["tame:bat"] and p.gold == 100_000 - 1100
    assert Engine.derived(p).atk == round(base.atk * 1.03)
    assert Pets.tameable(p) == []
    assert {%{ok: false, msg: "Bạn đã thuần phục loài này rồi."}, _} = Pets.tame(p, "bat")
    assert Pets.data("tame:bat").name == "Dơi Hang (thuần)"
    assert {%{ok: true}, _} = Pets.choose(p, "tame:bat")

    # thú thuần không tính vào thành tựu sưu tầm thú ở cửa hàng
    assert HacLong.Game.Achievements.value(p, :pets) == 0
  end

  test "thú lên cấp theo số trận thắng, mạnh dần, cấp 5 học kỹ năng" do
    {_, p} = Pets.buy(player(), "sheep")
    assert Pets.level(p, "sheep") == 1 and Pets.active_skill(p) == nil
    assert Enum.map(1..10, &Pets.xp_for/1) == [0, 10, 30, 60, 100, 150, 210, 280, 360, 450]

    {p, nil} = Pets.gain(p, false)
    assert Pets.xp(p, "sheep") == 1
    {p, 2} = Enum.reduce(1..8, p, fn _, p -> elem(Pets.gain(p, false), 0) end) |> Pets.gain(false)
    # trùm tính 5 trận
    {p2, nil} = Pets.gain(p, true)
    assert Pets.xp(p2, "sheep") == 15

    base = Engine.derived(Map.put(p, :pet, nil))
    lv5 = Map.put(p, :pet_xp, %{"sheep" => 100})
    assert Pets.level(lv5, "sheep") == 5
    assert_in_delta Pets.bonus(lv5, :hp), 0.05 * 1.4, 1.0e-9
    assert Engine.derived(lv5).maxHp == round(base.maxHp * (1 + 0.05 * 1.4))
    assert %{id: "heal"} = Pets.active_skill(lv5)
    assert Pets.bite(lv5, 100, 0.42) == 33
    assert Pets.bite(lv5, 100, 0.44) == 0

    # không lên quá cấp 10; thú thuần có Cắn Xé
    assert Pets.level(Map.put(p, :pet_xp, %{"sheep" => 99_999}), "sheep") == 10
    assert %{id: "rend"} = Pets.skill("tame:bat")
    assert {p, nil} = Pets.gain(Map.put(p, :pet, nil), false)
    assert Pets.xp(p, "sheep") == 10
  end

  test "thắng trận thì thú được tính; kỹ năng Cắn Xé nhân đôi cú cắn" do
    on_exit(&HacLong.Game.Rng.clear/0)
    {_, p} = Pets.buy(player(), "hound")
    p = Map.put(p, :pet_xp, %{"hound" => 99})
    {_, p} = Engine.start_battle(p, 0, false)
    p = put_in(p.battle.monster.hp, 1) |> put_in([:battle, :monster, :dodge], 0)
    {_, p} = Engine.act(p, "attack")
    assert p.battle.result == "win"
    assert Pets.xp(p, "hound") == 100
    assert Enum.any?(p.battle.log, &(&1.text =~ "lên cấp 5, học được Cắn Xé"))

    {_, p} = %{p | battle: nil} |> Engine.start_battle(0, false)
    p = put_in(p.battle.monster.hp, 100_000) |> put_in([:battle, :monster, :dodge], 0)
    HacLong.Game.Rng.put_sequence([0.0])
    {_, p} = Engine.act(p, "attack")
    assert Enum.any?(p.battle.log, &(&1.text =~ "🐾 Chó Săn Cắn Xé: cắn thêm"))
  end

  test "thành tựu mới: việc hằng ngày, top trùm thế giới, thuần thú, cấp thú" do
    alias HacLong.Game.Achievements

    p =
      player()
      |> Map.merge(%{
        daily_done: 10,
        boss_top: 1,
        pets: ["tame:bat"],
        pet_xp: %{"tame:bat" => 100}
      })

    {p, _} = Achievements.check(p)
    got = p.achievements
    assert Enum.all?(~w(daily_10 boss_top tamer pet_skill), &(&1 in got))
    refute Enum.any?(~w(daily_100 boss_top_10 pet_master), &(&1 in got))
  end
end
