defmodule Mix.Tasks.HacLong.Simulate do
  @shortdoc "Mô phỏng người chơi để kiểm tra cân bằng game"
  @moduledoc """
  Cho bot chơi từ đầu tới khi hạ Hắc Long với mỗi lớp nhân vật, theo ba cách chơi:

  - `chỉ đánh`: chỉ đánh quái, hái nguyên liệu thì bán;
  - `+nhiệm vụ`: làm thêm nhiệm vụ Trưởng Làng;
  - `+hằng ngày`: làm thêm cả việc hằng ngày (60 trận tính là một ngày).

  In số trận trung bình, cấp cuối, số lần chết, vàng, phần vàng/kinh nghiệm đến từ
  nhiệm vụ và việc hằng ngày, và cấp lúc hạ từng trùm (của ván đầu).

      mix hac_long.simulate      # 5 lần mỗi lớp mỗi cách chơi
      mix hac_long.simulate 20
  """
  use Mix.Task

  alias HacLong.Game.Simulator

  @modes [
    {"chỉ đánh", []},
    {"+nhiệm vụ", [quests: true]},
    {"+hằng ngày", [quests: true, daily: true]}
  ]

  @impl true
  def run(args) do
    Mix.Task.run("compile")
    n = with [s | _] <- args, {v, ""} <- Integer.parse(s), do: v, else: (_ -> 5)

    for cls <- ~w(warrior rogue knight) do
      Mix.shell().info(cls)

      for {label, opts} <- @modes do
        rs = for _ <- 1..n, do: Simulator.run(cls, opts)
        avg = fn k -> round(Enum.sum(Enum.map(rs, & &1[k])) / n) end
        wins = Enum.count(rs, & &1.victory)

        extra =
          if opts[:quests],
            do:
              " | nhiệm vụ #{avg.(:quests_done)}: +#{avg.(:quest_gold)}v +#{avg.(:quest_xp)}kn" <>
                if(opts[:daily],
                  do:
                    " | hằng ngày #{avg.(:daily_done)}: +#{avg.(:daily_gold)}v +#{avg.(:daily_xp)}kn",
                  else: ""
                ),
            else: ""

        Mix.shell().info(
          "  #{String.pad_trailing(label, 10)} trận=#{avg.(:fights)} cấp=#{avg.(:level)} " <>
            "chết=#{avg.(:deaths)} vàng=#{avg.(:gold)} thắng=#{wins}/#{n}#{extra}"
        )

        Mix.shell().info("    " <> Enum.join(hd(rs).milestones, " → "))
      end
    end
  end
end
