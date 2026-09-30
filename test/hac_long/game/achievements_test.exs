defmodule HacLong.Game.AchievementsTest do
  use ExUnit.Case, async: true

  alias HacLong.Game.{Achievements, Engine}

  defp player do
    {:ok, p} = Engine.new_player("Thử", "knight")
    p
  end

  test "đủ điều kiện thì nhận thành tựu, mỗi cái một lần" do
    p = player()
    assert {^p, nil} = Achievements.check(p)

    {p, msg} = Achievements.check(%{p | kills: 100})
    assert p.achievements == ["first_blood", "hunter"]

    assert msg ==
             "🏅 Thành tựu mới: Chiến Công Đầu, Thợ Săn. Danh hiệu mới: Thợ Săn (chọn ở tab Nhân vật)."

    assert {^p, nil} = Achievements.check(p)

    {p, _} = Achievements.check(%{p | upgrades: %{"club" => 5}, inv: %{"fish_gold" => 1}})
    assert "forged" in p.achievements and "golden_fish" in p.achievements
  end

  test "chọn danh hiệu đã đạt" do
    {p, _} = Achievements.check(%{player() | kills: 100})

    assert {%{ok: false, msg: "Bạn chưa đạt thành tựu \"Đồ Tể\"."}, _} =
             Achievements.set_title(p, "slayer")

    assert {%{ok: false}, _} = Achievements.set_title(p, "first_blood")
    {%{ok: true, msg: "Danh hiệu: Thợ Săn."}, p} = Achievements.set_title(p, "hunter")
    assert Achievements.title_name(p.title) == "Thợ Săn"
    {%{ok: true}, p} = Achievements.set_title(p, nil)
    assert p.title == nil
  end

  test "tiến độ gửi cho client" do
    v = Achievements.view(%{player() | kills: 250})
    assert %{id: "slayer", done: false, have: 250} = Enum.find(v, &(&1.id == "slayer"))
    assert Enum.find(Achievements.all(), &(&1.id == "level_max")).goal == Engine.max_level()
  end
end
