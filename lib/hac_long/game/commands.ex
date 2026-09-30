defmodule HacLong.Game.Commands do
  @moduledoc """
  Chuyển lệnh client gửi lên (`%{"act" => ..., ...}`) thành lời gọi engine.

  Trả về `{kết_quả, nhân_vật_mới}`; nhân vật là `nil` khi chưa tạo hoặc vừa xóa.
  Client chỉ gửi *ý định* (tấn công, mua món X...), mọi con số đều do server tính.
  """

  alias HacLong.Game.{Data, Engine, Quests}
  alias HacLong.World
  alias HacLong.World.Maps

  def run(nil, %{"act" => "create"} = c) do
    case Engine.new_player(c["name"], c["cls"]) do
      {:ok, p} ->
        {%{ok: true, msg: "Chào mừng #{p.name}!"},
         p
         |> Map.put(:pos, Maps.home_spawn())
         |> Map.put(:waystones, [])
         |> Map.put(:quests, Quests.empty())}

      {:error, msg} ->
        {%{ok: false, msg: msg}, nil}
    end
  end

  def run(nil, _), do: {%{ok: false, msg: "Chưa có nhân vật."}, nil}
  def run(p, %{"act" => "create"}), do: {%{ok: false, msg: "Đã có nhân vật."}, p}
  def run(_p, %{"act" => "reset"}), do: {%{ok: true}, nil}

  def run(p, %{"act" => act} = c) do
    case act do
      "rest" ->
        rest(p)

      a when a in ~w(attack skill potion flee) ->
        Engine.act(p, a)

      "leave" ->
        Engine.leave_battle(p)

      "alloc" ->
        Engine.allocate(p, c["stat"], int(c["n"] || 1))

      "equip" ->
        Engine.equip(p, c["id"])

      "unequip" ->
        Engine.unequip(p, c["slot"])

      "use" ->
        Engine.use_potion(p, c["id"])

      "sell" ->
        sell(p, c["id"])

      "buy" ->
        buy(p, c["id"], int(c["n"] || 1))

      "craft" ->
        craft(p, c["id"])

      "quest_accept" ->
        at_npc(p, ["quests"], "Trưởng Làng", fn _ -> Quests.accept(p, c["id"]) end)

      "quest_turnin" ->
        at_npc(p, ["quests"], "Trưởng Làng", fn _ -> Quests.turn_in(p, c["id"]) end)

      _ ->
        invalid(p)
    end
  end

  def run(p, _), do: invalid(p)

  defp invalid(p), do: {%{ok: false, msg: "Thao tác không hợp lệ."}, p}

  @merchants ["shop", "herbalist"]

  # Chạy `fun` nếu đang đứng cạnh NPC có vai trò phù hợp.
  defp at_npc(p, roles, who, fun) do
    case World.near_npc(p, roles) do
      nil -> {%{ok: false, msg: "Hãy đến gặp #{who}."}, p}
      npc -> fun.(npc)
    end
  end

  defp rest(p), do: at_npc(p, ["inn"], "Chủ Quán Trọ ở Làng", fn _ -> Engine.rest(p) end)

  defp buy(p, id, n) do
    at_npc(p, @merchants, "Thợ Rèn hoặc Bà Lang", fn npc ->
      if id in npc.stock,
        do: Engine.buy(p, id, n),
        else: {%{ok: false, msg: "#{npc.name} không bán món này."}, p}
    end)
  end

  defp sell(p, id),
    do: at_npc(p, @merchants, "Thợ Rèn hoặc Bà Lang", fn _ -> Engine.sell(p, id) end)

  defp craft(p, id) do
    at_npc(p, ["herbalist"], "Bà Lang", fn _ ->
      case Data.recipe(id) do
        nil ->
          {%{ok: false, msg: "Không có công thức này."}, p}

        r ->
          if Enum.all?(r.needs, fn {item, n} -> Map.get(p.inv, item, 0) >= n end) do
            inv =
              Enum.reduce(r.needs, p.inv, fn {item, n}, inv ->
                if inv[item] > n,
                  do: Map.put(inv, item, inv[item] - n),
                  else: Map.delete(inv, item)
              end)

            {%{ok: true, msg: "Pha được #{Data.item(r.out).name}."},
             Engine.add_item(%{p | inv: inv}, r.out)}
          else
            {%{ok: false, msg: "Chưa đủ nguyên liệu."}, p}
          end
      end
    end)
  end

  defp int(n) when is_integer(n), do: n

  defp int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp int(_), do: nil
end
