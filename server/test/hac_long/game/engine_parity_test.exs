defmodule HacLong.Game.EngineParityTest do
  @moduledoc """
  Chơi một ván tự động bằng engine Elixir, rồi phát lại đúng chuỗi lệnh đó trên
  `js/engine.js` (qua Node) với cùng dãy số ngẫu nhiên. Trạng thái sau mỗi lệnh
  phải giống hệt nhau. Bỏ qua nếu máy không có `node`.
  """
  use ExUnit.Case, async: true

  alias HacLong.Game.{Data, Engine, Rng}

  @script Path.expand("../../support/parity.js", __DIR__)
  @moduletag skip: if(System.find_executable("node"), do: false, else: "cần node")

  for cls <- ~w(warrior rogue knight) do
    test "engine Elixir khớp engine JS (#{cls})" do
      compare(unquote(cls), 1500)
    end
  end

  defp compare(cls, steps) do
    :rand.seed(:exsss, {1, 2, String.length(unquote(__MODULE__) |> inspect())})
    rng = for _ <- 1..5000, do: :rand.uniform()
    Rng.put_sequence(rng)

    {:ok, p} = Engine.new_player("Bot", cls)
    {commands, states} = play(p, steps, [], [])
    Rng.clear()

    input = Jason.encode!(%{rng: rng, name: "Bot", cls: cls, commands: commands})
    tmp = Path.join(System.tmp_dir!(), "parity-#{cls}-#{System.unique_integer([:positive])}.json")
    File.write!(tmp, input)
    {out, 0} = System.cmd("sh", ["-c", "node #{@script} < #{tmp}"])
    File.rm(tmp)

    js = Jason.decode!(out)
    assert length(js) == length(states)

    Enum.zip([commands, states, js])
    |> Enum.with_index()
    |> Enum.each(fn {{cmd, {res, player}, %{"result" => jres, "player" => jp}}, i} ->
      ex = normalize(%{result: res, player: player})

      assert ex == normalize(%{result: jres, player: jp}),
             "lệch ở bước #{i}: #{inspect(cmd)}"
    end)

    # ván chơi phải đủ dài để đi qua nhiều khu vực
    {_, last} = List.last(states)
    assert last.level >= 10
  end

  # Chuyển về JSON rồi decode lại để so sánh hai phía cùng một dạng.
  # JS bỏ khóa `msg`/`result` khi không có; Elixir cũng vậy, nên so sánh trực tiếp được.
  defp normalize(x), do: x |> Jason.encode!() |> Jason.decode!() |> drop_nils()

  defp drop_nils(m) when is_map(m),
    do: m |> Enum.reject(fn {_, v} -> v == nil end) |> Map.new(fn {k, v} -> {k, drop_nils(v)} end)

  defp drop_nils(l) when is_list(l), do: Enum.map(l, &drop_nils/1)
  defp drop_nils(v), do: v

  # Bot đơn giản giống tools/simulate.js: cộng điểm, mua đồ, nghỉ, đánh quái, đánh trùm.
  defp play(_p, 0, cmds, states), do: {Enum.reverse(cmds), Enum.reverse(states)}

  defp play(p, n, cmds, states) do
    # Lệnh trước bị từ chối (vd. kỹ năng đang hồi chiêu) thì đánh thường cho khỏi lặp.
    cmd =
      case states do
        [{%{ok: false}, _} | _] when p.battle != nil and not p.battle.over ->
          %{op: "act", action: "attack"}

        _ ->
          next_command(p)
      end

    {res, p2} = run(p, cmd)
    play(p2, n - 1, [cmd | cmds], [{res, p2} | states])
  end

  defp run(p, %{op: "start", zone: z, boss: b}), do: Engine.start_battle(p, z, b)
  defp run(p, %{op: "act", action: a}), do: Engine.act(p, a)
  defp run(p, %{op: "leave"}), do: Engine.leave_battle(p)
  defp run(p, %{op: "buy", id: id, n: n}), do: Engine.buy(p, id, n)
  defp run(p, %{op: "sell", id: id}), do: Engine.sell(p, id)
  defp run(p, %{op: "equip", id: id}), do: Engine.equip(p, id)
  defp run(p, %{op: "use", id: id}), do: Engine.use_potion(p, id)
  defp run(p, %{op: "rest"}), do: Engine.rest(p)
  defp run(p, %{op: "alloc", stat: s, n: n}), do: Engine.allocate(p, s, n)

  defp next_command(%{battle: %{over: true}}), do: %{op: "leave"}

  defp next_command(%{battle: b} = p) when b != nil do
    d = Engine.derived(p)

    action =
      cond do
        p.hp < d.maxHp * 0.35 and Engine.best_potion(p, d.maxHp - p.hp) -> "potion"
        b.skillCd == 0 -> "skill"
        # thỉnh thoảng thử bỏ chạy và bấm kỹ năng khi đang hồi chiêu
        rem(b.turn, 7) == 6 -> "flee"
        rem(b.turn, 5) == 4 -> "skill"
        true -> "attack"
      end

    %{op: "act", action: action}
  end

  defp next_command(p) do
    d = Engine.derived(p)
    stat = Enum.at(~w(str vit agi def), rem(p.level + p.points, 4))
    sellable = p.inv |> Map.keys() |> Enum.find(&(&1 in ~w(club vest)))

    cond do
      p.points > 0 -> %{op: "alloc", stat: stat, n: min(p.points, 2)}
      sellable -> %{op: "sell", id: sellable}
      upgrade = upgrade(p) -> upgrade
      p.hp < d.maxHp * 0.6 and p.gold >= Engine.rest_cost(p) -> %{op: "rest"}
      p.hp < d.maxHp * 0.6 and Map.get(p.inv, "potion_s", 0) > 0 -> %{op: "use", id: "potion_s"}
      Map.get(p.inv, "potion_s", 0) < 3 and p.gold > 60 -> %{op: "buy", id: "potion_s", n: 2}
      true -> fight(p)
    end
  end

  defp upgrade(p) do
    val = fn id -> if id, do: (Data.item(id)[:atk] || 0) + (Data.item(id)[:def] || 0), else: 0 end

    Enum.find_value(~w(weapon armor shield), fn slot ->
      cur = p.equip[String.to_atom(slot)]

      owned =
        Enum.find(Map.keys(p.inv), fn id ->
          it = Data.item(id)
          it.slot == slot and it.level <= p.level and val.(id) > val.(cur)
        end)

      shop =
        Enum.find(Enum.reverse(Data.shop()), fn id ->
          it = Data.item(id)

          it.slot == slot and it.level <= p.level and it.price <= p.gold - 40 and
            val.(id) > val.(cur)
        end)

      cond do
        owned -> %{op: "equip", id: owned}
        shop -> %{op: "buy", id: shop, n: 1}
        true -> nil
      end
    end)
  end

  defp fight(p) do
    zi =
      0..(Data.zone_count() - 1)
      |> Enum.filter(&Engine.zone_unlocked?(p, &1))
      |> List.last()

    z = Data.zone(zi)
    boss = p.level >= z.boss.level - 1 and z.boss.id not in p.bosses and rem(p.kills, 4) == 0
    %{op: "start", zone: zi, boss: boss}
  end
end
