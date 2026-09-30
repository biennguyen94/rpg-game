defmodule HacLong.Game.Pets do
  @moduledoc """
  Thú cưng: mua ở Người Nuôi Thú trong Làng, đi theo sau nhân vật trên bản đồ (người khác
  cũng thấy) và cộng một ít chỉ số (`bonus` trong `PETS` của `game_data.json`).
  Hàm thuần, như `Engine`.

  Thú đi theo cũng thỉnh thoảng cắn thêm một đòn trong trận (`bite/2`).

  Hạ đủ 100 con một loài quái thường thì có thể thuần phục loài đó ở Người Nuôi Thú:
  thú thuần có id `"tame:<id quái>"`, cộng 3% tấn công.

  Thú lên cấp (tối đa 10) theo số trận thắng khi được dắt theo (`gain/2`): mỗi cấp tăng
  chỉ số cộng thêm, tỷ lệ và sức cắn; từ cấp 5 thú dùng kỹ năng riêng khi cắn (`skill` trong
  `PETS`; thú thuần dùng Cắn Xé).

  Trạng thái trong nhân vật: `pets: [id]` (đã có), `pet: id | nil` (đang dắt theo),
  `pet_xp: %{id => số trận}`.
  """

  alias HacLong.Game.{Bestiary, Data}

  @tame_kills 100
  @tame_bonus 0.03
  @bite_chance 0.35
  @bite_power 0.25

  @max_level 10
  @skill_level 5
  @tame_skill %{id: "rend", name: "Cắn Xé", desc: "Cú cắn gây gấp đôi sát thương."}

  def tame_kills, do: @tame_kills
  def max_level, do: @max_level
  def skill_level, do: @skill_level

  # ---------- Cấp của thú ----------

  @doc "Số trận thắng cần để thú lên cấp `level`: 5 × cấp × (cấp - 1)."
  def xp_for(level), do: 5 * level * (level - 1)

  def xp(p, id), do: Map.get(Map.get(p, :pet_xp) || %{}, id, 0)

  def level(p, id) do
    n = xp(p, id)
    Enum.find(@max_level..1//-1, &(xp_for(&1) <= n))
  end

  defp active_level(p), do: level(p, p.pet)

  @doc "Kỹ năng riêng của thú `id` (mở ở cấp 5)."
  def skill(id) do
    case data(id) do
      %{tame: _} -> @tame_skill
      %{skill: sk} -> sk
      _ -> nil
    end
  end

  @doc """
  Thú đang dắt theo được tính một trận thắng (trùm: 5 trận). Trả về
  `{nhân_vật, cấp_mới | nil}`.
  """
  def gain(p, boss?) do
    case Map.get(p, :pet) && data(p.pet) do
      nil ->
        {p, nil}

      _ ->
        id = p.pet
        before = level(p, id)
        all = Map.get(p, :pet_xp) || %{}
        p = Map.put(p, :pet_xp, Map.put(all, id, xp(p, id) + if(boss?, do: 5, else: 1)))
        now = level(p, id)
        {p, if(now > before, do: now)}
    end
  end

  @doc "Thông tin thú `id`: thú bán ở cửa hàng hoặc thú đã thuần (`tame:<quái>`)."
  def data("tame:" <> mid = id) do
    case wild(mid) do
      nil ->
        nil

      m ->
        %{
          id: id,
          name: "#{m.name} (thuần)",
          price: tame_price(m),
          bonus: %{atk: @tame_bonus},
          desc: "Tấn công +#{round(@tame_bonus * 100)}%.",
          tame: mid
        }
    end
  end

  def data(id), do: Data.pet(id)

  # chỉ quái thường (không phải trùm) mới thuần phục được
  defp wild(mid) do
    Enum.find_value(Data.zones(), fn z -> Enum.find(z.monsters, &(&1.id == mid)) end)
  end

  defp tame_price(m), do: 1000 + m.level * 100

  @doc "Những loài quái thường có thể thuần phục (đã hạ đủ số con, chưa thuần)."
  def tameable(p) do
    for z <- Data.zones(),
        m <- z.monsters,
        Bestiary.count(p, m.id) >= @tame_kills,
        "tame:#{m.id}" not in owned(p),
        do: %{id: m.id, name: m.name, price: tame_price(m)}
  end

  @doc "Thuần phục loài `mid` (đã hạ ít nhất #{@tame_kills} con)."
  def tame(p, mid) do
    id = "tame:#{mid}"
    pet = is_binary(mid) && data(id)

    cond do
      !pet ->
        {%{ok: false, msg: "Không thuần phục được loài này."}, p}

      id in owned(p) ->
        {%{ok: false, msg: "Bạn đã thuần phục loài này rồi."}, p}

      Bestiary.count(p, mid) < @tame_kills ->
        {%{ok: false, msg: "Cần hạ ít nhất #{@tame_kills} con (mới #{Bestiary.count(p, mid)})."},
         p}

      p.gold < pet.price ->
        {%{ok: false, msg: "Cần #{pet.price} vàng."}, p}

      true ->
        p = %{p | gold: p.gold - pet.price}
        p = p |> Map.put(:pets, owned(p) ++ [id]) |> Map.put(:pet, id)
        {%{ok: true, msg: "🐾 Đã thuần phục #{pet.name}! (#{pet.desc})"}, p}
    end
  end

  @doc """
  Thú đang dắt theo cắn thêm: trả về số sát thương (0 nếu không cắn) theo sát thương
  một đòn thường `base` của nhân vật. `roll` là số ngẫu nhiên trong [0, 1).
  Cấp càng cao càng hay cắn và cắn càng đau (mỗi cấp +2% tỷ lệ, +2% sức cắn).
  """
  def bite(p, base, roll) do
    if Map.get(p, :pet) && data(p.pet) do
      lv = active_level(p) - 1

      if roll < @bite_chance + lv * 0.02,
        do: max(1, round(base * (@bite_power + lv * 0.02))),
        else: 0
    else
      0
    end
  end

  @doc "Kỹ năng riêng của thú đang dắt (nil nếu thú chưa tới cấp 5)."
  def active_skill(p) do
    if Map.get(p, :pet) && data(p.pet) && active_level(p) >= @skill_level, do: skill(p.pet)
  end

  def name(p), do: data(p.pet).name

  @doc """
  Phần trăm cộng thêm của thú đang dắt theo cho chỉ số `key` (hp, atk, def, gold, xp);
  mỗi cấp trên 1 tăng thêm 10% (cấp 10: gần gấp đôi).
  """
  def bonus(p, key) do
    case Map.get(p, :pet) && data(p.pet) do
      %{bonus: b} -> Map.get(b, key, 0) * (1 + (active_level(p) - 1) * 0.1)
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
      do: {%{ok: true, msg: "Dắt theo #{data(id).name}."}, Map.put(p, :pet, id)},
      else: {%{ok: false, msg: "Bạn chưa có con thú này."}, p}
  end
end
