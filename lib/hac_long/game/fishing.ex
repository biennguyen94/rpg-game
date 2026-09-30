defmodule HacLong.Game.Fishing do
  @moduledoc """
  Câu cá ở hồ nước (ô `~`). Hàm thuần, như `Engine`; thời gian truyền vào (mili giây, đồng
  hồ đơn điệu của server) để test được.

  - `cast/2`: đứng cạnh nước thì thả câu. Cá cắn câu sau `@wait` ngẫu nhiên; client nhận số
    mili giây phải chờ để hiện phao chìm.
  - `reel/2`: giật cần. Chỉ được cá nếu giật trong `@window` kể từ lúc cá cắn; giật sớm hay
    muộn thì trượt. Đi chỗ khác thì mất lượt câu.
  - Loại cá tùy vùng (`pool/1`): Làng và Rừng Mê cá thường; Đầm Lầy và Hang Rồng có Lươn Điện.
    Rất hiếm mới có Cá Chép Vàng.

  Trạng thái lượt câu (`fishing: %{bite, pos}`) chỉ giữ trong Session, không lưu database.
  Số cá đã câu được lưu ở `fish_caught` (cho thành tựu).
  """

  alias HacLong.Game.{Data, Engine, Rng}
  alias HacLong.World.Maps

  @wait 3_000..8_000
  @window 1_000

  def window, do: @window

  # {tỉ lệ, món}
  @pools %{
    default: [{8, "old_boot"}, {60, "fish_small"}, {31, "fish_carp"}, {1, "fish_gold"}],
    deep: [
      {6, "old_boot"},
      {30, "fish_small"},
      {35, "fish_carp"},
      {27, "fish_eel"},
      {2, "fish_gold"}
    ]
  }

  def pool(map_id) do
    case Maps.get(map_id) do
      %{zone: z} when is_integer(z) and z >= 4 -> @pools.deep
      _ -> @pools.default
    end
  end

  @doc "Đang đứng cạnh (4 hướng) một ô nước."
  def near_water?(%{pos: %{map: id, x: x, y: y}}) do
    case Maps.get(id) do
      nil ->
        false

      m ->
        Enum.any?([{1, 0}, {-1, 0}, {0, 1}, {0, -1}], fn {dx, dy} ->
          Maps.tile(m, x + dx, y + dy) == "~"
        end)
    end
  end

  def near_water?(_), do: false

  def cast(p, now) do
    cond do
      p.battle ->
        {%{ok: false, msg: "Đang trong trận."}, p}

      not near_water?(p) ->
        {%{ok: false, msg: "Hãy đứng cạnh hồ nước để câu."}, p}

      true ->
        lo..hi//_ = @wait
        wait = lo + floor(Rng.uniform() * (hi - lo))

        {%{ok: true, wait: wait, window: @window},
         Map.put(p, :fishing, %{bite: now + wait, pos: p.pos})}
    end
  end

  def reel(p, now) do
    f = Map.get(p, :fishing)
    p = Map.put(p, :fishing, nil)

    cond do
      f == nil -> {%{ok: false, msg: "Bạn chưa thả câu."}, p}
      f.pos != p.pos -> {%{ok: false, msg: "Bạn đã rời chỗ câu."}, p}
      now < f.bite -> {%{ok: false, msg: "Giật sớm quá, cá sợ bỏ đi mất."}, p}
      now > f.bite + @window -> {%{ok: false, msg: "Chậm tay rồi, cá ăn mất mồi."}, p}
      true -> catch_fish(p)
    end
  end

  defp catch_fish(p) do
    id = roll(pool(p.pos.map))
    p = p |> Engine.add_item(id) |> Map.put(:fish_caught, Map.get(p, :fish_caught, 0) + 1)
    name = Data.item(id).name

    msg =
      case id do
        "old_boot" -> "Câu được... #{name}. Thôi thì cũng là một món."
        "fish_gold" -> "✨ Câu được #{name}! Hiếm lắm đấy!"
        _ -> "Câu được #{name}!"
      end

    {%{ok: true, msg: msg, fish: id}, p}
  end

  defp roll(pool) do
    total = pool |> Enum.map(&elem(&1, 0)) |> Enum.sum()
    r = Rng.uniform() * total

    Enum.reduce_while(pool, 0, fn {w, id}, acc ->
      if r < acc + w, do: {:halt, id}, else: {:cont, acc + w}
    end)
  end
end
