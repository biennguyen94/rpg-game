defmodule Mix.Tasks.HacLong.Simulate do
  @shortdoc "Mô phỏng người chơi để kiểm tra cân bằng game"
  @moduledoc """
  Cho bot chơi từ đầu tới khi hạ Hắc Long với mỗi lớp nhân vật, in số trận
  trung bình, cấp cuối, số lần chết và cấp lúc hạ từng trùm.

      mix hac_long.simulate      # 5 lần mỗi lớp
      mix hac_long.simulate 20
  """
  use Mix.Task

  alias HacLong.Game.Simulator

  @impl true
  def run(args) do
    Mix.Task.run("compile")
    n = with [s | _] <- args, {v, ""} <- Integer.parse(s), do: v, else: (_ -> 5)

    for cls <- ~w(warrior rogue knight) do
      rs = for _ <- 1..n, do: Simulator.run(cls)
      avg = fn k -> round(Enum.sum(Enum.map(rs, & &1[k])) / n) end
      wins = Enum.count(rs, & &1.victory)

      Mix.shell().info(
        "#{cls}: trận=#{avg.(:fights)} cấp cuối=#{avg.(:level)} chết=#{avg.(:deaths)} " <>
          "vàng=#{avg.(:gold)} thắng=#{wins}/#{n}"
      )

      first = hd(rs)
      Mix.shell().info("  " <> Enum.join(first.milestones, " → "))
      for l <- first.boss_losses, do: Mix.shell().info("  thua #{l}")
    end
  end
end
