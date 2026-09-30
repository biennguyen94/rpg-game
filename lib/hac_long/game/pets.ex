defmodule HacLong.Game.Pets do
  @moduledoc """
  Thú cưng: mua ở Người Nuôi Thú trong Làng, đi theo sau nhân vật trên bản đồ (người khác
  cũng thấy) và cộng một ít chỉ số (`bonus` trong `PETS` của `game_data.json`).
  Hàm thuần, như `Engine`.

  Trạng thái trong nhân vật: `pets: [id]` (đã mua), `pet: id | nil` (đang dắt theo).
  """

  alias HacLong.Game.Data

  @doc "Phần trăm cộng thêm của thú đang dắt theo cho chỉ số `key` (hp, atk, def, gold, xp)."
  def bonus(p, key) do
    case Map.get(p, :pet) && Data.pet(p.pet) do
      %{bonus: b} -> Map.get(b, key, 0)
      _ -> 0
    end
  end

  defp owned(p), do: Map.get(p, :pets) || []

  def buy(p, id) do
    pet = Data.pet(id)

    cond do
      pet == nil ->
        {%{ok: false, msg: "Không có con thú này."}, p}

      id in owned(p) ->
        {%{ok: false, msg: "Bạn đã có #{pet.name} rồi."}, p}

      p.gold < pet.price ->
        {%{ok: false, msg: "Cần #{pet.price} vàng."}, p}

      true ->
        p = %{p | gold: p.gold - pet.price}
        p = p |> Map.put(:pets, owned(p) ++ [id]) |> Map.put(:pet, id)
        {%{ok: true, msg: "#{pet.name} về nhà với bạn! (#{pet.desc})"}, p}
    end
  end

  @doc "Dắt theo thú `id` (đã mua), hoặc `nil` để cho ở nhà."
  def choose(p, nil), do: {%{ok: true, msg: "Thú cưng ở nhà."}, Map.put(p, :pet, nil)}

  def choose(p, id) do
    if id in owned(p),
      do: {%{ok: true, msg: "Dắt theo #{Data.pet(id).name}."}, Map.put(p, :pet, id)},
      else: {%{ok: false, msg: "Bạn chưa có con thú này."}, p}
  end
end
