defmodule HacLong.Game.SimulatorTest do
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Simulator}

  test "bot chỉ đánh quái vẫn hạ được Hắc Long" do
    r = Simulator.run("warrior")
    assert r.victory
    assert r.quests_done == 0 and r.daily_done == 0
  end

  test "bot làm nhiệm vụ và việc hằng ngày: xong gần hết nhiệm vụ, nhận thưởng hằng ngày" do
    r = Simulator.run("knight", quests: true, daily: true)
    assert r.victory

    # vài nhiệm vụ vùng cuối (thu thập, hạ quái hiếm) có thể chưa xong lúc hạ Hắc Long
    assert r.quests_done >= length(Data.quests()) - 5
    assert r.quest_gold > 0 and r.quest_xp > 0
    assert r.daily_done > 0 and r.daily_gold > 0
  end
end
