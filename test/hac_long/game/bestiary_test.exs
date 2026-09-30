defmodule HacLong.Game.BestiaryTest do
  use ExUnit.Case, async: true

  alias HacLong.Game.{Bestiary, Engine, Rng}

  setup do
    on_exit(&Rng.clear/0)
  end

  test "đếm số con mỗi loài; chạm mốc thì thưởng vàng và đánh mạnh hơn" do
    {:ok, p} = Engine.new_player("Thử", "warrior")
    bat = %{id: "bat", level: 1}
    assert Bestiary.mastery(p, "bat") == 0

    p = Enum.reduce(1..24, p, fn _, p -> elem(Bestiary.record(p, bat), 0) end)
    assert Bestiary.count(p, "bat") == 24
    {p, mark} = Bestiary.record(p, bat)
    # Dơi cấp 1: vàng gốc round(3 + 2.2) = 5, thưởng ×5
    assert mark == %{kills: 25, bonus: 0.05, gold: 25}
    assert Bestiary.mastery(p, "bat") == 0.05

    p = Enum.reduce(26..99, p, fn _, p -> elem(Bestiary.record(p, bat), 0) end)
    {p, %{kills: 100}} = Bestiary.record(p, bat)
    assert Bestiary.mastery(p, "bat") == 0.10
  end

  test "thắng trận thì ghi vào sổ; mốc hiện trong nhật ký trận" do
    Rng.put_sequence([0.99])
    {:ok, p} = Engine.new_player("Thử", "warrior")
    p = %{p | stats: %{p.stats | str: 200}, bestiary: %{"bat" => 24}}
    {_, p} = Engine.start_battle(p, 0, false)
    id = p.battle.monster.id
    p = %{p | bestiary: %{id => 24}}
    gold = p.gold
    {_, p} = Engine.act(p, "attack")
    assert p.battle.result == "win"
    assert p.bestiary[id] == 25
    assert Enum.any?(p.battle.log, &(&1.text =~ "📖 Sổ tay: đã hạ 25"))
    assert p.gold > gold + p.battle.monster.gold
  end
end
