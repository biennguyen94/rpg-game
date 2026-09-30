defmodule HacLong.Game.Commands do
  @moduledoc """
  Chuyển lệnh client gửi lên (`%{"act" => ..., ...}`) thành lời gọi engine.

  Trả về `{kết_quả, nhân_vật_mới}`; nhân vật là `nil` khi chưa tạo hoặc vừa xóa.
  Client chỉ gửi *ý định* (tấn công, mua món X...), mọi con số đều do server tính.
  """

  alias HacLong.Game.Engine

  def run(nil, %{"act" => "create"} = c) do
    case Engine.new_player(c["name"], c["cls"]) do
      {:ok, p} -> {%{ok: true, msg: "Chào mừng #{p.name}!"}, p}
      {:error, msg} -> {%{ok: false, msg: msg}, nil}
    end
  end

  def run(nil, _), do: {%{ok: false, msg: "Chưa có nhân vật."}, nil}
  def run(p, %{"act" => "create"}), do: {%{ok: false, msg: "Đã có nhân vật."}, p}
  def run(_p, %{"act" => "reset"}), do: {%{ok: true}, nil}

  def run(p, %{"act" => act} = c) do
    case act do
      "rest" -> Engine.rest(p)
      "hunt" -> Engine.start_battle(p, int(c["zone"]), false)
      "boss" -> Engine.start_battle(p, int(c["zone"]), true)
      a when a in ~w(attack skill potion flee) -> Engine.act(p, a)
      "again" -> again(p)
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

  # Đánh tiếp ở cùng khu vực sau khi trận quái thường kết thúc.
  defp again(%{battle: %{over: true, result: r, monster: %{boss: false}, zone: zi}} = p)
       when r != "lose" do
    {_, p} = Engine.leave_battle(p)
    Engine.start_battle(p, zi, false)
  end

  defp again(p), do: invalid(p)

  defp int(n) when is_integer(n), do: n

  defp int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp int(_), do: nil
end
