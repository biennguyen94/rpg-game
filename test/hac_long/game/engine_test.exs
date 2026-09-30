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
    assert p.battle.skillCd == 4
    assert Enum.any?(p.battle.log, &(&1.text =~ "Khiên Thánh hồi"))
    assert {%{ok: false, msg: "Kỹ năng hồi sau 4 lượt."}, ^p} = Engine.act(p, "skill")
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

  test "bot chơi hết game với mỗi lớp nhân vật" do
    for cls <- ~w(warrior rogue knight) do
      r = Simulator.run(cls)
      assert r.victory, "#{cls} không thắng: #{inspect(r)}"
      assert r.fights in 300..700
    end
  end
end
