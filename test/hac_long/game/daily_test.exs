defmodule HacLong.Game.DailyTest do
  use ExUnit.Case, async: true

  alias HacLong.Game.{Commands, Daily, Data}

  defp player(attrs \\ %{}) do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Chăm Chỉ", "cls" => "warrior"})
    Map.merge(p, attrs)
  end

  test "ngày theo giờ Việt Nam; đếm giờ tới lúc có việc mới" do
    assert Daily.today(~U[2026-10-01 16:59:59Z]) == "2026-10-01"
    assert Daily.today(~U[2026-10-01 17:00:00Z]) == "2026-10-02"
    assert Daily.seconds_left(~U[2026-10-01 16:59:00Z]) == 60
  end

  test "mỗi ngày 4 việc cố định theo tên và ngày, lấy từ vùng đã mở" do
    p = Daily.ensure(player(), "2026-10-01")

    assert [%{kind: "kill"}, %{kind: "zone"}, %{kind: "gather"}, %{kind: "fish"}] =
             p.daily.tasks

    assert Enum.all?(p.daily.tasks, &(&1.zone == 0 and &1.progress == 0 and not &1.claimed))
    assert Enum.all?(p.daily.tasks, &(&1.reward.gold > 0 and &1.reward.xp > 0))
    kill = hd(p.daily.tasks)
    assert kill.target in Enum.map(Data.zone(0).monsters, & &1.id)
    assert Enum.at(p.daily.tasks, 2).target in ~w(herb ore)

    # cùng ngày thì giữ nguyên (kể cả tiến độ), ngày khác thì đổi
    p2 = Daily.on_kill(p, kill.target, 0)
    assert Daily.ensure(p2, "2026-10-01") == p2
    assert Daily.ensure(p2, "2026-10-02").daily.date == "2026-10-02"
    assert Daily.generate(p, "2026-10-01") == p.daily.tasks

    # đã mở nhiều vùng thì việc ở hai vùng cao nhất
    strong = player(%{bosses: ~w(wolf orc_warrior lich hill_giant)})

    zones =
      strong |> Daily.ensure("2026-10-01") |> get_in([:daily, :tasks]) |> Enum.map(& &1.zone)

    assert Enum.all?(zones, &(&1 in [3, 4]))
  end

  test "tiến độ, nhận thưởng một lần ở Bảng Tin" do
    p = Daily.ensure(player(), "2026-10-01")
    [kill, zone, gather, fish] = p.daily.tasks

    p = Enum.reduce(1..kill.count, p, fn _, p -> Daily.on_kill(p, kill.target, 0) end)

    # hạ quái vừa tính cho việc "hạ loại quái" vừa tính cho việc "hạ quái ở vùng"
    assert Enum.at(p.daily.tasks, 1).progress == min(kill.count, zone.count)
    p = Enum.reduce(1..20, p, fn _, p -> Daily.on_gather(p, gather.target) end)
    assert Enum.at(p.daily.tasks, 2).progress == gather.count
    assert Daily.ready?(p)

    # câu cá: cá thật mới tính, giày cũ thì không
    p = Enum.reduce(1..fish.count, p, fn _, p -> Daily.on_fish(p) end)
    assert Enum.at(p.daily.tasks, 3).progress == fish.count
    assert fish.reward.gold > 0

    board = %{p | pos: %{map: "village", x: 14, y: 4}}
    far = %{p | pos: %{map: "village", x: 12, y: 15}}

    assert {%{ok: false, msg: "Hãy đến gặp Bảng Tin ở Làng."}, _} =
             Commands.run(far, %{"act" => "daily_claim", "i" => 0})

    {%{ok: true}, claimed} = Commands.run(board, %{"act" => "daily_claim", "i" => 0})
    assert claimed.gold == p.gold + kill.reward.gold
    assert claimed.daily_done == 1

    assert {%{ok: false, msg: "Đã nhận thưởng rồi."}, _} =
             Commands.run(claimed, %{"act" => "daily_claim", "i" => 0})

    assert {%{ok: false, msg: "Chưa làm xong."}, _} =
             Commands.run(
               %{
                 board
                 | daily: %{board.daily | tasks: [%{kill | progress: 0} | tl(board.daily.tasks)]}
               },
               %{"act" => "daily_claim", "i" => 0}
             )

    assert {%{ok: false}, _} = Commands.run(board, %{"act" => "daily_claim", "i" => 7})
    assert {%{ok: false}, _} = Commands.run(board, %{"act" => "daily_claim", "i" => "x"})
  end

  test "câu được cá thì tính việc hằng ngày, vớt giày cũ thì không" do
    p = Daily.ensure(player(), HacLong.Game.Daily.today(DateTime.utc_now()))
    fish = Enum.find(p.daily.tasks, &(&1.kind == "fish"))
    assert fish.progress == 0
    {%{ok: true}, p1} = HacLong.Game.Fishing.land(p, "fish_small")
    assert Enum.find(p1.daily.tasks, &(&1.kind == "fish")).progress == 1
    {%{ok: true}, p2} = HacLong.Game.Fishing.land(p, "old_boot")
    assert Enum.find(p2.daily.tasks, &(&1.kind == "fish")).progress == 0
  end
end
