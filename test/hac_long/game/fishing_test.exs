defmodule HacLong.Game.FishingTest do
  use ExUnit.Case, async: true

  alias HacLong.Game.{Engine, Fishing, Rng}

  setup do
    on_exit(&Rng.clear/0)
  end

  # Làng: hồ nước ở giữa, ô (10, 5) nằm ngay trên ô nước (10, 6)
  defp angler(pos \\ %{map: "village", x: 10, y: 5}) do
    {:ok, p} = Engine.new_player("Cần Thủ", "rogue")
    Map.put(p, :pos, pos)
  end

  test "phải đứng cạnh nước mới câu được" do
    assert Fishing.near_water?(angler())
    far = angler(%{map: "village", x: 3, y: 14})
    refute Fishing.near_water?(far)
    assert {%{ok: false, msg: "Hãy đứng cạnh hồ nước để câu."}, _} = Fishing.cast(far, 0)
  end

  test "giật đúng lúc cá cắn thì được cá, sớm hay muộn thì trượt" do
    # chờ 3000 + 0.5*5000 = 5500 ms; lần ngẫu nhiên sau chọn cá (0.5 * 100 → Cá Diếc)
    Rng.put_sequence([0.5])
    {%{ok: true, wait: 5500}, p} = Fishing.cast(angler(), 1_000)

    assert {%{ok: false, msg: "Giật sớm quá, cá sợ bỏ đi mất."}, p2} = Fishing.reel(p, 6_000)
    assert p2.fishing == nil
    assert {%{ok: false, msg: "Chậm tay rồi, cá ăn mất mồi."}, _} = Fishing.reel(p, 7_600)

    assert {%{ok: true, fish: "fish_small"}, p3} = Fishing.reel(p, 6_900)
    assert p3.inv["fish_small"] == 1 and p3.fish_caught == 1
    # một lượt câu chỉ giật được một lần
    assert {%{ok: false, msg: "Bạn chưa thả câu."}, _} = Fishing.reel(p3, 6_950)
  end

  test "đi chỗ khác thì mất lượt câu" do
    Rng.put_sequence([0.0])
    {_, p} = Fishing.cast(angler(), 0)
    p = %{p | pos: %{p.pos | x: 11}}
    assert {%{ok: false, msg: "Bạn đã rời chỗ câu."}, _} = Fishing.reel(p, 3_500)
  end

  test "Lươn Điện chỉ có ở vùng sâu" do
    ids = fn map -> Enum.map(Fishing.pool(map), &elem(&1, 1)) end
    refute "fish_eel" in ids.("village")
    assert "fish_eel" in ids.("swamp_1")
  end
end
