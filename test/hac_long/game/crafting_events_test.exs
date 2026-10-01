defmodule HacLong.Game.CraftingEventsTest do
  # đổi cấu hình sự kiện (toàn cục) nên không chạy song song
  use ExUnit.Case, async: false

  alias HacLong.Game.{Commands, Crafting, Engine, Events, Gear, Home, Rng}

  setup do
    on_exit(fn ->
      Application.put_env(:hac_long, :event, "none")
      Rng.clear()
    end)
  end

  defp player(attrs) do
    {:ok, p} = Engine.new_player("Đầu Bếp", "warrior")
    Map.merge(%{p | gold: 10_000}, attrs)
  end

  test "nấu ăn: đủ nguyên liệu, đủ cấp nghề; lên cấp nghề" do
    p = player(%{inv: %{"fish_small" => 20, "herb" => 20, "fish_eel" => 1, "herb_rare" => 1}})
    assert {%{ok: false, msg: "Chưa đủ nguyên liệu."}, _} = Crafting.cook(p, "cook_banh_mi_ca")

    assert {%{ok: false, msg: "Cần nghề Nấu ăn cấp 3."}, _} =
             Crafting.cook(p, "cook_banh_xeo_luon")

    assert {%{ok: false}, _} = Crafting.cook(p, "brew_s")

    {%{ok: true, msg: msg}, p} = Crafting.cook(p, "cook_cha_ca")
    assert msg == "Nấu được Chả Cá."
    assert p.inv["cha_ca"] == 1 and p.inv["fish_small"] == 18 and p.inv["herb"] == 19

    p = Enum.reduce(1..4, p, fn _, p -> elem(Crafting.cook(p, "cook_cha_ca"), 1) end)
    assert Crafting.xp(p, :cook) == 5 and Crafting.level(p, :cook) == 2
    assert Enum.map([0, 4, 5, 15, 30, 50, 999], &Crafting.level/1) == [1, 1, 2, 3, 4, 5, 5]

    # Bà Lang không nấu món của Bác Đầu Bếp
    herbalist = Map.put(p, :pos, %{map: "village", x: 16, y: 13})

    assert {%{ok: false, msg: "Không có công thức này."}, _} =
             Commands.run(herbalist, %{"act" => "craft", "id" => "cook_cha_ca"})
  end

  test "ăn món: cộng chỉ số trong vài trận rồi hết" do
    p = player(%{inv: %{"cha_ca" => 2}})
    base = Engine.derived(p)
    assert {%{ok: false}, _} = Crafting.eat(p, "potion_s")

    {%{ok: true}, p} = Crafting.eat(p, "cha_ca")
    assert p.food == %{id: "cha_ca", left: 5} and p.inv["cha_ca"] == 1
    assert Engine.derived(p).atk == round(base.atk * 1.1)

    # dùng qua lệnh "use" cũng được
    {%{ok: true}, p2} = Commands.run(p, %{"act" => "use", "id" => "cha_ca"})
    assert p2.food.left == 5 and not Map.has_key?(p2.inv, "cha_ca")

    p = Enum.reduce(1..4, p, fn _, p -> Crafting.tick(p) end)
    assert p.food.left == 1
    p = Crafting.tick(p)
    assert p.food == nil and Engine.derived(p) == base

    # hết trận (bỏ chạy cũng tính) thì món bớt một trận
    {_, p} = Crafting.eat(player(%{inv: %{"cha_ca" => 1}}), "cha_ca")
    {_, p} = Engine.start_battle(p, 0, false)
    Rng.put_sequence([0.0])
    {_, p} = Engine.act(p, "flee")
    assert p.battle.over and p.food.left == 4
  end

  test "rèn đồ: tốn quặng và vàng, đúng loại đồ, cấp nghề tăng tỉ lệ Sử Thi" do
    p = player(%{level: 10, inv: %{"ore" => 20, "ore_rare" => 3}})
    assert {%{ok: false, msg: "Không rèn được loại này."}, _} = Crafting.smith(p, "ring")
    assert {%{ok: false, msg: "Chưa đủ quặng."}, _} = Crafting.smith(%{p | inv: %{}}, "weapon")
    assert {%{ok: false, msg: "Cần 150 vàng."}, _} = Crafting.smith(%{p | gold: 10}, "weapon")

    {%{ok: true, gear: uid}, p2} = Crafting.smith(p, "armor")
    g = Gear.find(p2, uid)
    assert HacLong.Game.Data.item(g.base).slot == "armor" and g.rarity in 1..3
    assert p2.inv["ore"] == 15 and p2.inv["ore_rare"] == 2 and p2.gold == p.gold - 150
    assert Crafting.xp(p2, :smith) == 1

    assert Crafting.smith_weights(1) == [{3, 6}, {2, 50}, {1, 44}]
    assert Crafting.smith_weights(5) == [{3, 30}, {2, 50}, {1, 20}]
  end

  test "lịch sự kiện theo ngày, qua năm mới" do
    assert Events.on_date("2026-09-30").id == "mid_autumn"
    assert Events.on_date("2026-10-11") == nil
    assert Events.on_date("2026-12-31").id == "christmas"
    assert Events.on_date("2027-01-02").id == "christmas"
    assert Events.on_date("2027-02-01").id == "tet"
    assert {%{id: "pumpkin"}, 14} = Events.next("2026-10-11")

    assert {%{id: "tet"}, 17} = Events.next("2027-01-03")

    assert Events.current() == nil
  end

  test "trong lễ hội: quái rơi vật phẩm, thêm kinh nghiệm, đổi quà" do
    Application.put_env(:hac_long, :event, "mid_autumn")
    p = player(%{level: 5})
    {_, p} = Engine.start_battle(p, 0, false)
    m = p.battle.monster
    p = put_in(p.battle.monster.hp, 1) |> put_in([:battle, :monster, :dodge], 0)
    Rng.put_sequence([0.0])
    {_, p} = Engine.act(p, "attack")
    assert p.battle.result == "win"
    assert p.inv["moon_cake"] == 1
    assert p.battle.reward.xp == round(m.xp * 1.1)

    p = %{p | battle: nil, inv: Map.put(p.inv, "moon_cake", 45)}
    assert {%{ok: false}, _} = Events.exchange(p, "nope")
    {%{ok: true}, p} = Events.exchange(p, "decor")
    assert p.furniture["lamp_festival"] == 1 and p.inv["moon_cake"] == 15 and p.festival == 1
    before = length(p.gear)
    {%{ok: true}, p} = Events.exchange(p, "gear")
    assert length(p.gear) == before + 1
    assert {%{ok: false, msg: "Cần 6 Bánh Trung Thu."}, _} = Events.exchange(p, "potions")

    # Thợ Mộc không bán đồ lễ hội
    assert {%{ok: false, msg: "Món này chỉ đổi được ở lễ hội."}, _} = Home.buy(p, "lamp_festival")

    Application.put_env(:hac_long, :event, "none")
    assert {%{ok: false, msg: "Chưa tới mùa lễ hội."}, _} = Events.exchange(p, "gold")
  end
end
