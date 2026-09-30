defmodule HacLong.Game.Commands do
  @moduledoc """
  Chuyển lệnh client gửi lên (`%{"act" => ..., ...}`) thành lời gọi engine.

  Trả về `{kết_quả, nhân_vật_mới}`; nhân vật là `nil` khi chưa tạo hoặc vừa xóa.
  Client chỉ gửi *ý định* (tấn công, mua món X...), mọi con số đều do server tính.
  """

  alias HacLong.Game.Engine
  alias HacLong.World
  alias HacLong.World.Maps

  def run(nil, %{"act" => "create"} = c) do
    case Engine.new_player(c["name"], c["cls"]) do
      {:ok, p} -> {%{ok: true, msg: "Chào mừng #{p.name}!"}, Map.put(p, :pos, Maps.home_spawn())}
      {:error, msg} -> {%{ok: false, msg: msg}, nil}
    end
  end

  def run(nil, _), do: {%{ok: false, msg: "Chưa có nhân vật."}, nil}
  def run(p, %{"act" => "create"}), do: {%{ok: false, msg: "Đã có nhân vật."}, p}
  def run(_p, %{"act" => "reset"}), do: {%{ok: true}, nil}

  def run(p, %{"act" => act} = c) do
    case act do
      "rest" -> rest(p)
      a when a in ~w(attack skill potion flee) -> Engine.act(p, a)
      "leave" -> Engine.leave_battle(p)
      "alloc" -> Engine.allocate(p, c["stat"], int(c["n"] || 1))
      "equip" -> Engine.equip(p, c["id"])
      "unequip" -> Engine.unequip(p, c["slot"])
      "use" -> Engine.use_potion(p, c["id"])
      "sell" -> Engine.sell(p, c["id"])
      "buy" -> Engine.buy(p, c["id"], int(c["n"] || 1))
      _ -> invalid(p)
    end
  end

  def run(p, _), do: invalid(p)

  defp invalid(p), do: {%{ok: false, msg: "Thao tác không hợp lệ."}, p}

  defp rest(p) do
    if World.can_rest?(p),
      do: Engine.rest(p),
      else: {%{ok: false, msg: "Chỉ nghỉ được ở Làng hoặc ở Nhà."}, p}
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
