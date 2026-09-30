defmodule HacLong.Game.Bestiary do
  @moduledoc """
  Sổ tay quái vật: đếm số con đã hạ của từng loài (`bestiary: %{id_quái => số}`).
  Hàm thuần, như `Engine`.

  Hạ đủ mốc thì hiểu loài đó hơn: được thưởng vàng một lần và đánh loài đó mạnh hơn
  vĩnh viễn (`mastery/2`).
  """

  alias HacLong.Game.Data

  # {số con, sát thương cộng thêm lên loài đó, thưởng vàng = số lần vàng rơi của loài}
  @marks [{25, 0.05, 5}, {100, 0.10, 20}]

  def marks, do: @marks

  @doc "Mọi loài có trong sổ: quái thường và trùm của các vùng."
  def species do
    Enum.flat_map(Data.zones(), fn z -> z.monsters ++ [z.boss] end) |> Enum.map(& &1.id)
  end

  def count(p, id), do: Map.get(Map.get(p, :bestiary) || %{}, id, 0)

  @doc "Sát thương cộng thêm lên loài `id` (0, 0.05 hoặc 0.10)."
  def mastery(p, id) do
    n = count(p, id)

    @marks
    |> Enum.filter(fn {k, _, _} -> n >= k end)
    |> Enum.map(fn {_, b, _} -> b end)
    |> Enum.max(fn -> 0 end)
  end

  @doc """
  Vừa hạ con `m`: cộng vào sổ. Nếu vừa chạm mốc thì trả thêm `{mốc, thưởng_vàng}`.
  """
  def record(p, m) do
    n = count(p, m.id) + 1
    p = Map.put(p, :bestiary, Map.put(Map.get(p, :bestiary) || %{}, m.id, n))

    case Enum.find(@marks, fn {k, _, _} -> k == n end) do
      nil -> {p, nil}
      {k, bonus, times} -> {p, %{kills: k, bonus: bonus, gold: base_gold(m) * times}}
    end
  end

  # vàng rơi trung bình của loài ở cấp gốc (không tính may rủi)
  defp base_gold(m), do: round(3 + m.level * 2.2)
end
