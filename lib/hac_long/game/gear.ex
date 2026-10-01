defmodule HacLong.Game.Gear do
  @moduledoc """
  Đồ có chỉ số ngẫu nhiên (rơi từ quái). Hàm thuần, như `Engine`.

  Khác đồ thường (đếm theo loại trong `inv`), mỗi món ở đây là một bản riêng, lưu trong
  `gear: [%{uid, base, rarity, bonus}]` của nhân vật:

  - `uid`: bắt đầu bằng `#`, dùng thay id đồ ở `equip`, `sell`, `upgrades`...
  - `base`: đồ gốc trong `game_data.json` (quyết định chỗ mặc, tấn công/phòng thủ, cấp cần).
  - `rarity`: 1 Tốt, 2 Hiếm, 3 Sử Thi, bằng số dòng chỉ số cộng thêm.
  - `bonus`: `%{str | vit | agi | def => điểm}` cộng vào chỉ số khi mặc.

  Đồ đang mặc vẫn nằm trong `gear` (`equip` chỉ trỏ tới `uid`).
  """

  alias HacLong.Game.{Data, Rng}

  @max_bag 20
  @stats ~w(str vit agi def)a
  @rarity_names %{1 => "Tốt", 2 => "Hiếm", 3 => "Sử Thi"}
  @suffix %{str: "Sức Mạnh", vit: "Bền Bỉ", agi: "Nhanh Nhẹn", def: "Kiên Cố"}

  def max_bag, do: @max_bag
  def rarity_names, do: @rarity_names

  def instance?(id), do: is_binary(id) and String.starts_with?(id, "#")

  defp list(p), do: Map.get(p, :gear) || []

  def find(p, uid), do: Enum.find(list(p), &(&1.uid == uid))

  def equipped?(p, uid), do: uid in Map.values(p.equip)

  @doc "Món trong túi (không đang mặc)."
  def bag(p), do: Enum.reject(list(p), &equipped?(p, &1.uid))

  @doc """
  Thông tin món đồ `id` như `Data.item/1`: đồ thường lấy thẳng; đồ ngẫu nhiên thì lấy đồ
  gốc, đổi tên và thêm `uid`, `rarity`, `bonus`, `sell`.
  """
  def item(_p, nil), do: nil

  def item(p, id) do
    if instance?(id) do
      case find(p, id) do
        nil -> nil
        g -> resolve(g)
      end
    else
      Data.item(id)
    end
  end

  def resolve(g) do
    base = Data.item(g.base)
    main = g.bonus |> Enum.max_by(fn {_, v} -> v end, fn -> {nil, 0} end) |> elem(0)

    base
    |> Map.merge(%{
      uid: g.uid,
      base: g.base,
      name: if(main, do: "#{base.name} #{@suffix[main]}", else: base.name),
      rarity: g.rarity,
      bonus: g.bonus,
      sell: price(g)
    })
  end

  @doc "Giá bán: giá đồ gốc tăng theo độ hiếm và số điểm cộng thêm."
  def price(g) do
    base = Data.item(g.base).price
    round(base * 0.4 * (1 + 0.25 * g.rarity) + 5 * Enum.sum(Map.values(g.bonus)))
  end

  @doc "Tổng điểm chỉ số cộng thêm từ các món đang mặc."
  def bonus_stats(p) do
    p.equip
    |> Map.values()
    |> Enum.filter(&instance?/1)
    |> Enum.map(&find(p, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(%{}, fn g, acc -> Map.merge(acc, g.bonus, fn _, a, b -> a + b end) end)
  end

  # ---------- Rơi đồ ----------

  @doc "Tỉ lệ rơi đồ ngẫu nhiên khi hạ quái `m`."
  def drop_chance(m) do
    cond do
      m[:world] || m[:pvp] -> 0
      m[:elite] -> 0.5
      m[:night] -> 0.25
      m.boss -> 0.35
      true -> 0.04
    end
  end

  @doc """
  Tạo một món ngẫu nhiên hợp với quái cấp `level` (nil nếu không có đồ gốc phù hợp);
  `slot` chọn loại đồ (mặc định ngẫu nhiên).
  `weights`: tỉ lệ các độ hiếm `[{độ_hiếm, tỉ_lệ}]` (mặc định 5% Sử Thi, 25% Hiếm, 70% Tốt).
  """
  def roll(level, weights \\ [{3, 5}, {2, 25}, {1, 70}], slot \\ nil) do
    slot =
      slot ||
        (
          r = Rng.uniform()

          cond do
            r < 0.45 -> "weapon"
            r < 0.8 -> "armor"
            true -> "shield"
          end
        )

    bases =
      Data.items()
      |> Enum.filter(fn {_, it} ->
        it.slot == slot and it.price > 0 and !it[:drop] and (it[:level] || 1) <= level
      end)
      |> Enum.sort_by(fn {_, it} -> it.level end, :desc)
      |> Enum.take(2)

    case bases do
      [] ->
        nil

      _ ->
        {base, _} = Enum.at(bases, floor(Rng.uniform() * length(bases)))
        rarity = pick_weighted(weights)

        stats = shuffle(@stats) |> Enum.take(rarity)
        bonus = Map.new(stats, &{&1, 1 + floor(Rng.uniform() * (1 + level / 6))})

        %{uid: new_uid(), base: base, rarity: rarity, bonus: bonus}
    end
  end

  defp pick_weighted(weights) do
    r = Rng.uniform() * (weights |> Enum.map(&elem(&1, 1)) |> Enum.sum())

    Enum.reduce_while(weights, 0, fn {v, w}, acc ->
      if r < acc + w, do: {:halt, v}, else: {:cont, acc + w}
    end)
  end

  defp shuffle(list),
    do: list |> Enum.map(&{Rng.uniform(), &1}) |> Enum.sort() |> Enum.map(&elem(&1, 1))

  defp new_uid, do: "#" <> Base.encode32(:crypto.strong_rand_bytes(5), padding: false)

  @doc """
  Thêm món `g` vào túi. Túi đầy (#{@max_bag} món chưa mặc) thì bán luôn.
  Trả về `{nhân_vật, :kept | {:sold, vàng}}`.
  """
  def add(p, g) do
    if length(bag(p)) >= @max_bag do
      {%{p | gold: p.gold + price(g)}, {:sold, price(g)}}
    else
      {Map.put(p, :gear, list(p) ++ [g]), :kept}
    end
  end

  def remove(p, uid), do: Map.put(p, :gear, Enum.reject(list(p), &(&1.uid == uid)))

  @doc "Đọc từ database (khóa chuỗi) về dạng engine dùng."
  def load(list) when is_list(list) do
    for g <- list, Data.item(g["base"]) do
      %{
        uid: g["uid"],
        base: g["base"],
        rarity: g["rarity"],
        bonus: Map.new(g["bonus"], fn {k, v} -> {String.to_existing_atom(k), v} end)
      }
    end
  end

  def load(_), do: []
end
