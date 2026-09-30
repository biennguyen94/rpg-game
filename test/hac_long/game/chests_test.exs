defmodule HacLong.Game.ChestsTest do
  use ExUnit.Case, async: true

  alias HacLong.Game.{Chests, Engine, Gear, Rng}

  setup do
    on_exit(&Rng.clear/0)
  end

  defp player(level, gold) do
    {:ok, p} = Engine.new_player("Thử", "warrior")
    %{p | level: level, gold: gold}
  end

  test "mua rương báu: trừ vàng theo cấp, được một món đồ ngẫu nhiên" do
    p = player(20, 100_000)
    # vũ khí tốt nhất ở cấp 20 là Rìu Chiến (1600 vàng, bán lại 640)
    assert Chests.price(Chests.tier("gold"), 20) == 640 * 8
    {%{ok: true, msg: msg, gear: uid}, p} = Chests.buy(p, "gold")
    assert msg =~ "Mở Rương Vàng"
    assert p.gold == 100_000 - 640 * 8
    # Rương Vàng: ít nhất là Hiếm
    assert Gear.find(p, uid).rarity >= 2

    assert {%{ok: false, msg: "Cần 2560 vàng."}, _} = Chests.buy(%{p | gold: 10}, "silver")
    assert {%{ok: false}, _} = Chests.buy(p, "kim_cuong")
  end

  test "túi đồ hiếm đầy thì không mua được rương" do
    p = player(20, 100_000)

    p =
      Enum.reduce(1..Gear.max_bag(), p, fn i, p ->
        elem(Gear.add(p, %{uid: "##{i}", base: "mace", rarity: 1, bonus: %{str: 1}}), 0)
      end)

    assert {%{ok: false, msg: "Túi đồ hiếm đầy" <> _}, ^p} = Chests.buy(p, "wood")
  end

  test "rương ở Nhà mở mỗi ngày một lần" do
    Rng.put_sequence([0.9])
    p = player(10, 0)
    {%{ok: true, msg: msg}, p} = Chests.open_daily(p, "2026-10-01")
    assert msg =~ "Rương Gia Truyền"
    assert p.gold == 20 + 10 * 8 and p.inv["potion_m"] == 2

    assert {%{ok: false, msg: "Hôm nay đã mở rồi. Mai quay lại nhé."}, _} =
             Chests.open_daily(p, "2026-10-01")

    assert {%{ok: true}, _} = Chests.open_daily(p, "2026-10-02")
  end
end
