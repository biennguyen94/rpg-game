defmodule HacLong.Game.Tutorial do
  @moduledoc """
  Hướng dẫn người mới: 5 bước đầu tiên, dẫn tới việc hoàn thành nhiệm vụ "Lũ dơi hang".
  Hàm thuần, như `Engine`.

  Mỗi bước tự xong khi trạng thái nhân vật thỏa điều kiện (không cần theo dõi sự kiện
  riêng), nên người chơi làm nhanh hơn hướng dẫn hay làm lại từ database đều đúng.
  Xong bước cuối thì được quà tân thủ.

  Trạng thái trong nhân vật: `tutorial` là số thứ tự bước đang làm (0–4), `nil` khi đã xong
  hoặc bỏ qua (nhân vật tạo trước khi có hướng dẫn cũng là `nil`).
  """

  alias HacLong.Game.{Data, Engine, Quests}
  alias HacLong.World.Maps

  @quest "forest_kill"
  @forest ~w(forest_1 forest_2 forest_boss)
  @reward %{gold: 50, items: %{"potion_s" => 3}}

  @steps [
    %{text: "Ra khỏi nhà", hint: "Đi xuống cửa nhà ở phía dưới."},
    %{
      text: "Gặp Trưởng Làng, nhận việc \"Lũ dơi hang\"",
      hint: "Ông già râu ở giữa Làng, phía trên hồ nước. Bước vào ông để nói chuyện."
    },
    %{text: "Ra Rừng Mê", hint: "Cổng phía trên bên trái Làng."},
    %{text: "Hạ 5 Dơi Hang", hint: "Chạm vào con dơi để đánh. Số nhỏ cạnh quái là cấp của nó."},
    %{
      text: "Về trả việc cho Trưởng Làng",
      hint: "Quay về Làng, bước vào Trưởng Làng rồi bấm Trả."
    }
  ]

  def total, do: length(@steps)
  def reward, do: @reward

  defp done?(p, 0), do: p.pos.map != Maps.home() or done?(p, 1)
  defp done?(p, 1), do: Map.has_key?(quests(p).active, @quest) or done?(p, 4)
  defp done?(p, 2), do: p.pos.map in @forest or kills(p) > 0 or done?(p, 4)
  defp done?(p, 3), do: Quests.complete?(p, Data.quest(@quest)) or done?(p, 4)
  defp done?(p, 4), do: @quest in quests(p).done

  defp quests(p), do: Map.get(p, :quests) || Quests.empty()
  defp kills(p), do: quests(p).active[@quest] || 0

  @doc """
  Chuyển sang bước tiếp theo nếu bước hiện tại đã xong (có thể qua nhiều bước một lúc).
  Trả về `{nhân_vật, thông_báo | nil}`; xong bước cuối thì nhận quà.
  """
  def check(nil), do: {nil, nil}
  def check(%{tutorial: step} = p) when is_integer(step), do: advance(p, step, nil)
  def check(p), do: {p, nil}

  defp advance(p, step, note) when step >= length(@steps) do
    p = %{p | tutorial: nil, gold: p.gold + @reward.gold}
    p = Enum.reduce(@reward.items, p, fn {id, n}, p -> Engine.add_item(p, id, n) end)
    _ = note
    {p, "Xong phần hướng dẫn! Quà tân thủ: +#{@reward.gold} vàng, 3 Bình Máu Nhỏ."}
  end

  defp advance(p, step, note) do
    if done?(p, step) do
      next = step + 1

      msg =
        if next < length(@steps),
          do: "Hướng dẫn #{next + 1}/#{length(@steps)}: #{Enum.at(@steps, next).text}."

      advance(%{p | tutorial: next}, next, msg)
    else
      {p, note}
    end
  end

  def skip(p), do: {%{ok: true, msg: "Đã tắt hướng dẫn."}, Map.put(p, :tutorial, nil)}

  @doc "Thông tin hiện cho client: bước đang làm và ô đích trên bản đồ đang đứng (nếu có)."
  def view(%{tutorial: step} = p) when is_integer(step) do
    s = Enum.at(@steps, step)
    %{step: step + 1, total: length(@steps), text: s.text, hint: s.hint, target: target(p, step)}
  end

  def view(_p), do: nil

  # Ô cần tới ở bản đồ đang đứng: chỗ cần đến nếu ở đúng bản đồ, không thì cổng dẫn về phía đó.
  defp target(p, 0), do: toward(p, "village")
  defp target(p, 1), do: elder(p)
  defp target(p, 2), do: if(p.pos.map in @forest, do: nil, else: toward(p, "forest_1"))
  defp target(_p, 3), do: nil
  defp target(p, 4), do: elder(p)

  defp elder(%{pos: %{map: "village"}}) do
    %{at: {x, y}} = Maps.npc("village", "elder")
    %{map: "village", x: x, y: y}
  end

  defp elder(p), do: toward(p, "village")

  defp toward(%{pos: %{map: here}}, goal) do
    case Maps.get(here) do
      %{portals: portals} ->
        portal =
          Enum.find(portals, &(&1.to == goal)) ||
            Enum.find(portals, &(&1.to == "village")) ||
            Enum.find(portals, &(&1.to != here))

        portal && %{map: here, x: elem(portal.at, 0), y: elem(portal.at, 1)}

      _ ->
        nil
    end
  end
end
