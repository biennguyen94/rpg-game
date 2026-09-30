defmodule HacLong.LeaderboardTest do
  use HacLong.DataCase, async: true

  alias HacLong.{Accounts, Leaderboard}
  alias HacLong.Game.{Characters, Commands}

  defp hero(name, attrs) do
    {:ok, user} = Accounts.register(%{"username" => name, "password" => "matkhau1"})
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "rogue"})
    Characters.save!(user.id, Map.merge(p, attrs))
    user
  end

  test "xếp theo cấp, số quái đã hạ và ai hạ Hắc Long trước" do
    early = ~U[2026-10-01 10:00:00Z]
    a = hero("anna", %{level: 20, xp: 5, kills: 300})

    b =
      hero("binh", %{
        level: 20,
        xp: 90,
        kills: 100,
        victory: true,
        victory_at: DateTime.add(early, 60)
      })

    c = hero("chi_", %{level: 35, xp: 0, kills: 50, victory: true, victory_at: early})
    d = hero("dung", %{level: 3, xp: 0, kills: 900})

    assert Enum.map(Leaderboard.top(:level), & &1.name) == ~w(chi_ binh anna dung)
    assert Enum.map(Leaderboard.top(:kills), & &1.name) == ~w(dung anna binh chi_)
    assert Enum.map(Leaderboard.top(:dragon), & &1.name) == ~w(chi_ binh)
    assert [%{rank: 1}, %{rank: 2} | _] = Leaderboard.top(:level)
    assert length(Leaderboard.top(:level, 2)) == 2

    assert Leaderboard.level_rank(c.id) == 1
    assert Leaderboard.level_rank(b.id) == 2
    assert Leaderboard.level_rank(a.id) == 3
    assert Leaderboard.level_rank(d.id) == 4
    assert Leaderboard.level_rank(-1) == nil
  end
end
