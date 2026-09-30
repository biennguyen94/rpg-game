defmodule HacLong.Game.EngineTest do
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Engine, Rng, Simulator}

  setup do
    on_exit(&Rng.clear/0)
  end

  defp player(cls \\ "warrior") do
    {:ok, p} = Engine.new_player("Thử", cls)
    p
  end

  test "chỉ số nhân vật mới" do
    p = player()
    assert p.stats == %{str: 8, vit: 7, agi: 4, def: 5}
    d = Engine.derived(p)
    # 40 + 7*12 + 1*10
    assert d.maxHp == 134 and p.hp == 134
    # 8*2.2 + 4*0.9 + gậy 3 + cấp 1
    assert d.atk == 25
    assert Engine.xp_to_next(1) == 40
  end

  test "chỉ số quái tính từ cấp, trùm mạnh hơn" do
    Rng.put_sequence([0.5])
    z = Data.zone(0)
    m = Engine.make_monster(hd(z.monsters), false)
    b = Engine.make_monster(z.boss, true)
    assert m.maxHp == round((20 + 26 + 0.6) * 0.8)
    assert b.boss and b.maxHp > 10 * m.maxHp
    assert b.special.every == 3
  end

  test "chí mạng, né, sát thương theo dãy số cố định" do
    # Thứ tự gọi ngẫu nhiên mỗi lượt đánh: chí mạng?, quái né?, sát thương, rồi tới lượt quái.
    Rng.put_sequence([0.0])
    p = player()
    {%{ok: true}, p} = Engine.start_battle(p, 0, false)
    assert p.battle.monster.id == "bat"

    Rng.put_sequence([0.99])
    {%{ok: true}, p2} = Engine.act(p, "attack")
    [_, hit, _] = p2.battle.log
    assert hit.kind == "hit"
    assert p2.battle.monster.hp < p.battle.monster.hp

    Rng.put_sequence([0.0, 0.99, 0.5, 0.99])
    {_, p3} = Engine.act(p, "attack")
    assert Enum.at(p3.battle.log, 1).kind == "crit"

    # số đầu nhỏ hơn tỉ lệ né của quái (0.031): quái né được
    Rng.put_sequence([0.99, 0.0, 0.99])
    {_, p4} = Engine.act(p, "attack")
    assert Enum.at(p4.battle.log, 1).text =~ "né được"
    assert p4.battle.monster.hp == p.battle.monster.hp
  end

  test "kỹ năng có hồi chiêu" do
    Rng.put_sequence([0.5])
    p = %{player("knight") | hp: 50}
    {_, p} = Engine.start_battle(p, 0, true)
    {%{ok: true}, p} = Engine.act(p, "skill")
    assert Engine.cooldown(p, "holy") == 4
    assert Enum.any?(p.battle.log, &(&1.text =~ "Khiên Thánh hồi"))
    assert {%{ok: false, msg: "Khiên Thánh hồi sau 4 lượt."}, ^p} = Engine.act(p, "skill")
  end

  test "kỹ năng mở theo cấp" do
    ids = fn p -> Enum.map(Engine.skills(p), & &1.id) end
    assert ids.(player()) == ["cleave"]
    assert ids.(%{player() | level: 10}) == ["cleave", "stun_bash"]
    assert ids.(%{player("rogue") | level: 25}) == ["backstab", "venom", "shadow_step"]

    Rng.put_sequence([0.5])
    {_, p} = Engine.start_battle(player(), 0, false)
    assert {%{ok: false, msg: "Chưa học kỹ năng này."}, _} = Engine.act(p, "skill", "stun_bash")
  end

  # quái thường, không né, không chí mạng: dãy 0.99 cho mọi lần ngẫu nhiên
  defp fight(cls, level, zone \\ 0) do
    Rng.put_sequence([0.99])
    p = %{player(cls) | level: level, stats: %{str: 5, vit: 200, agi: 0, def: 5}}
    p = %{p | hp: Engine.derived(p).maxHp}
    {_, p} = Engine.start_battle(p, zone, false)
    put_in(p.battle.monster.hp, 100_000) |> put_in([:battle, :monster, :maxHp], 100_000)
  end

  test "choáng làm quái mất lượt" do
    p = fight("warrior", 10)
    hp = p.hp
    {%{ok: true}, p} = Engine.act(p, "skill", "stun_bash")
    assert Enum.any?(p.battle.log, &(&1.text =~ "bị choáng, không đánh được"))
    assert p.hp == hp
    # choáng chỉ một lượt
    {_, p} = Engine.act(p, "attack")
    assert p.hp < hp
  end

  test "tẩm độc: quái mất máu cuối mỗi lượt trong 3 lượt" do
    p = fight("rogue", 10)
    {_, p} = Engine.act(p, "skill", "venom")
    assert [%{id: "poison", turns: 2, power: per}] = p.battle.effects.monster
    hp = p.battle.monster.hp
    {_, p} = Engine.act(p, "attack")
    {_, p} = Engine.act(p, "attack")
    assert p.battle.effects.monster == []
    ticks = Enum.count(p.battle.log, &(&1.text =~ "mất #{per} máu vì độc"))
    assert ticks == 3
    assert p.battle.monster.hp < hp - per
  end

  test "trùm gây bỏng; bình máu giải bỏng" do
    Rng.put_sequence([0.99])
    p = %{player() | level: 20, stats: %{str: 5, vit: 300, agi: 0, def: 5}}

    p = %{
      p
      | hp: Engine.derived(p).maxHp,
        inv: %{"potion_l" => 3},
        bosses: ["wolf", "orc_warrior"]
    }

    # Pháp Sư Bất Tử: Lửa Âm Phủ mỗi 3 lượt gây bỏng
    {_, p} = Engine.start_battle(p, 2, true)
    p = put_in(p.battle.monster.hp, 100_000)
    p = Enum.reduce(1..3, p, fn _, p -> elem(Engine.act(p, "attack"), 1) end)
    assert [%{id: "burn", power: per}] = p.battle.effects.player
    assert Enum.any?(p.battle.log, &(&1.text =~ "Bạn mất #{per} máu vì bị bỏng"))
    {_, p} = Engine.act(p, "potion")
    assert p.battle.effects.player == []
    assert Enum.any?(p.battle.log, &(&1.text == "Hết bị bỏng."))
  end

  test "hạ trùm mở vùng mới, gục ngã mất 10% vàng" do
    Rng.put_sequence([0.5])
    p = %{player() | level: 30, gold: 1000}
    refute Engine.zone_unlocked?(p, 1)
    {_, p} = Engine.start_battle(p, 0, true)
    p = put_in(p.battle.monster.hp, 1)
    {%{result: "win"}, won} = Engine.act(p, "attack")
    assert "wolf" in won.bosses
    assert Engine.zone_unlocked?(won, 1)
    assert List.last(won.battle.log).text =~ "Đã mở khu vực mới"

    p = %{p | hp: 1, stats: %{p.stats | agi: 0}}
    p = put_in(p.battle.monster.hp, 10_000)
    {%{result: "lose"}, lost} = Engine.act(p, "attack")
    assert lost.gold == 900 and lost.deaths == 1
    assert lost.hp == round(Engine.derived(lost).maxHp * 0.5)
  end

  test "lên cấp nhận điểm tiềm năng và hồi đầy máu" do
    p = %{player() | hp: 1}
    {levels, p} = Engine.gain_xp(p, 40 + Engine.xp_to_next(2))
    assert levels == 2 and p.level == 3 and p.points == 6
    assert p.stats.str == 8 + 2 * 3
    assert p.hp == Engine.derived(p).maxHp
  end

  test "Thợ Rèn nâng cấp đồ đang mặc bằng quặng và vàng" do
    p = %{player() | gold: 10_000}
    atk = Engine.derived(p).atk

    assert {%{ok: false, msg: "Thiếu nguyên liệu: Quặng Sắt 0/1."}, _} =
             Engine.upgrade(p, "weapon")

    p = Engine.add_item(p, "ore", 20)
    {%{ok: true, msg: "Đã nâng Gậy Gỗ lên +1."}, p} = Engine.upgrade(p, "weapon")
    # gậy gỗ tấn công 3: mỗi cấp ít nhất +1
    assert Engine.derived(p).atk == atk + 1
    assert p.inv["ore"] == 19 and p.gold == 10_000 - 8

    p = Enum.reduce(1..3, p, fn _, p -> elem(Engine.upgrade(p, "weapon"), 1) end)
    assert Engine.upgrade_level(p, "club") == 4
    # +5 cần Vảy Cổ Long
    assert {%{ok: false, msg: "Thiếu nguyên liệu: Vảy Cổ Long 0/1."}, _} =
             Engine.upgrade(p, "weapon")

    {%{ok: true}, p} = p |> Engine.add_item("dragon_scale") |> Engine.upgrade("weapon")
    assert {%{ok: false, msg: "Gậy Gỗ đã nâng cấp tối đa."}, _} = Engine.upgrade(p, "weapon")
    assert Engine.view(p).bonus == %{"club" => 5}
    assert Engine.view(p).forge.weapon == %{id: "club", level: 5, cost: nil}

    # đồ cấp cao dùng Mithril; cấp nâng giữ theo món khi tháo ra mặc lại
    assert Engine.upgrade_cost("waraxe", 0) == %{gold: 600, items: %{"ore_rare" => 1}}
    p = %{p | level: 10} |> Engine.add_item("broadsword")
    {_, p} = Engine.equip(p, "broadsword")
    assert Engine.upgrade_level(p, "broadsword") == 0
    {_, p} = Engine.equip(p, "club")
    assert Engine.derived(p).atk == Engine.derived(%{p | upgrades: %{}}).atk + 5

    # bán món cuối cùng thì mất cấp nâng
    {_, p} = Engine.equip(p, "broadsword")
    {_, p} = Engine.sell(p, "club")
    assert p.upgrades == %{}
    assert {%{ok: false, msg: "Chưa mặc đồ ở chỗ này."}, _} = Engine.upgrade(p, "shield")
  end

  test "chuyển sinh ở cấp tối đa: về cấp 1, giữ đồ và vàng, nhận điểm cộng thêm" do
    p = %{player() | gold: 5000, bosses: ["wolf"]}
    assert {%{ok: false, msg: "Cần đạt cấp 50 mới chuyển sinh được."}, _} = Engine.rebirth(p)

    p = %{p | level: 50, stats: %{str: 150, vit: 60, agi: 4, def: 5}, points: 2}
    {%{ok: true, msg: msg}, q} = Engine.rebirth(p)
    assert msg =~ "Chuyển sinh lần 1"
    assert q.level == 1 and q.xp == 0 and q.rebirths == 1
    assert q.stats == %{str: 8, vit: 7, agi: 4, def: 5}
    assert q.points == Engine.rebirth_points()
    assert q.gold == 5000 and q.bosses == ["wolf"] and q.equip == p.equip
    assert q.hp == Engine.derived(q).maxHp

    {_, q2} = Engine.rebirth(%{q | level: 50})
    assert q2.rebirths == 2 and q2.points == 2 * Engine.rebirth_points()
    assert {%{ok: false}, _} = Engine.rebirth(%{q2 | level: 50, rebirths: Engine.max_rebirths()})
  end

  test "bot chơi hết game với mỗi lớp nhân vật" do
    for cls <- ~w(warrior rogue knight) do
      r = Simulator.run(cls)
      assert r.victory, "#{cls} không thắng: #{inspect(r)}"
      assert r.fights in 300..700
    end
  end
end
