defmodule HacLong.Game.Commands do
  @moduledoc """
  Chuyển lệnh client gửi lên (`%{"act" => ..., ...}`) thành lời gọi engine.

  Trả về `{kết_quả, nhân_vật_mới}`; nhân vật là `nil` khi chưa tạo hoặc vừa xóa.
  Client chỉ gửi *ý định* (tấn công, mua món X...), mọi con số đều do server tính.
  """

  alias HacLong.Game.{
    Achievements,
    Chests,
    Crafting,
    Daily,
    Data,
    Engine,
    Events,
    Fishing,
    Home,
    Pets,
    Quests,
    Tower,
    Tutorial
  }

  alias HacLong.World
  alias HacLong.World.Maps

  def run(nil, %{"act" => "create"} = c) do
    case Engine.new_player(c["name"], c["cls"]) do
      {:ok, p} ->
        {%{ok: true, msg: "Chào mừng #{p.name}!"},
         p
         |> Map.put(:pos, Maps.home_spawn())
         |> Map.put(:waystones, [])
         |> Map.put(:quests, Quests.empty())
         |> Map.put(:victory_at, nil)
         |> Map.put(:daily, nil)
         |> Map.put(:tower, nil)
         |> Map.put(:tower_best, 0)
         |> Map.put(:tutorial, 0)}

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
        Engine.act(p, a, c["skill"])

      "leave" ->
        Engine.leave_battle(p)

      "alloc" ->
        Engine.allocate(p, c["stat"], int(c["n"] || 1))

      "equip" ->
        Engine.equip(p, c["id"])

      "unequip" ->
        Engine.unequip(p, c["slot"])

      "use" ->
        case Data.item(c["id"]) do
          %{slot: "food"} -> Crafting.eat(p, c["id"])
          _ -> Engine.use_potion(p, c["id"])
        end

      "cook" ->
        at_npc(p, ["cook"], "Bác Đầu Bếp ở Làng", fn _ -> Crafting.cook(p, c["id"]) end)

      "smith" ->
        at_npc(p, ["shop"], "Thợ Rèn ở Làng", fn _ -> Crafting.smith(p, c["slot"]) end)

      "event_exchange" ->
        at_npc(p, ["event"], "Người Tổ Chức Hội ở Làng", fn _ -> Events.exchange(p, c["id"]) end)

      "sell" ->
        sell(p, c["id"])

      "buy" ->
        buy(p, c["id"], int(c["n"] || 1))

      "craft" ->
        craft(p, c["id"])

      "title_set" ->
        Achievements.set_title(p, c["id"])

      "fish_cast" ->
        Fishing.cast(p, System.monotonic_time(:millisecond))

      "fish_reel" ->
        Fishing.reel(p, System.monotonic_time(:millisecond))

      "pet_buy" ->
        at_npc(p, ["pets"], "Người Nuôi Thú ở Làng", fn _ -> Pets.buy(p, c["id"]) end)

      "pet_tame" ->
        at_npc(p, ["pets"], "Người Nuôi Thú ở Làng", fn _ -> Pets.tame(p, c["id"]) end)

      "pet_choose" ->
        Pets.choose(p, c["id"])

      "decor_buy" ->
        at_npc(p, ["carpenter"], "Thợ Mộc ở Làng", fn _ -> Home.buy(p, c["id"]) end)

      "decor_place" ->
        Home.place(p, c["id"], int(c["x"]), int(c["y"]))

      "decor_take" ->
        Home.take(p, int(c["x"]), int(c["y"]))

      "chest_buy" ->
        at_npc(p, ["shop"], "Thợ Rèn ở Làng", fn _ -> Chests.buy(p, c["tier"]) end)

      "chest_open" ->
        at_npc(p, ["chest"], "Rương Gia Truyền ở Nhà", fn _ ->
          Chests.open_daily(p, Daily.today())
        end)

      "upgrade" ->
        at_npc(p, ["shop"], "Thợ Rèn ở Làng", fn _ -> Engine.upgrade(p, c["slot"]) end)

      "quest_accept" ->
        at_npc(p, ["quests"], "Trưởng Làng", fn _ -> Quests.accept(p, c["id"]) end)

      "quest_turnin" ->
        at_npc(p, ["quests"], "Trưởng Làng", fn _ -> Quests.turn_in(p, c["id"]) end)

      "rebirth" ->
        at_npc(p, ["quests"], "Trưởng Làng", fn _ -> Engine.rebirth(p) end)

      "tutorial_skip" ->
        Tutorial.skip(p)

      "tower_enter" ->
        at_npc(p, ["tower"], "Người Gác Tháp ở Làng", fn _ ->
          Tower.enter(p, int(c["floor"] || 1))
        end)

      "daily_claim" ->
        at_npc(p, ["daily"], "Bảng Tin ở Làng", fn _ -> Daily.claim(p, int(c["i"])) end)

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
        r when r == nil or r.npc != "herbalist" ->
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
