defmodule HacLong.Game.Achievements do
  @moduledoc """
  Thành tựu và danh hiệu. Hàm thuần, như `Engine`.

  - Mỗi thành tựu có điều kiện tính từ trạng thái nhân vật (`value/2` so với `goal`), nên nhân
    vật cũ vào game là nhận luôn những thành tựu đã đủ điều kiện.
  - Một số thành tựu cho danh hiệu (`title`); người chơi chọn một danh hiệu để hiện cạnh tên
    trong chat và bảng xếp hạng.

  Trạng thái trong nhân vật: `achievements: [id]` (theo thứ tự đạt được), `title: id | nil`.
  """

  alias HacLong.Game.{Bestiary, Data, Engine}
  alias HacLong.World.Maps

  @list [
    %{
      id: "first_blood",
      name: "Chiến Công Đầu",
      desc: "Hạ con quái đầu tiên.",
      stat: :kills,
      goal: 1
    },
    %{
      id: "hunter",
      name: "Thợ Săn",
      desc: "Hạ 100 quái.",
      stat: :kills,
      goal: 100,
      title: "Thợ Săn"
    },
    %{
      id: "slayer",
      name: "Đồ Tể",
      desc: "Hạ 1.000 quái.",
      stat: :kills,
      goal: 1000,
      title: "Đồ Tể"
    },
    %{
      id: "legend_hunter",
      name: "Săn Không Nghỉ",
      desc: "Hạ 5.000 quái.",
      stat: :kills,
      goal: 5000,
      title: "Thợ Săn Huyền Thoại"
    },
    %{
      id: "first_boss",
      name: "Trùm Đầu Tiên",
      desc: "Hạ một trùm canh giữ vùng đất.",
      stat: :bosses,
      goal: 1
    },
    %{
      id: "dragon",
      name: "Diệt Rồng",
      desc: "Hạ Hắc Long.",
      stat: :victory,
      goal: 1,
      title: "Kẻ Diệt Rồng"
    },
    %{id: "level_10", name: "Có Nghề", desc: "Đạt cấp 10.", stat: :level, goal: 10},
    %{
      id: "level_25",
      name: "Lão Luyện",
      desc: "Đạt cấp 25.",
      stat: :level,
      goal: 25,
      title: "Lão Luyện"
    },
    %{
      id: "level_max",
      name: "Đỉnh Cao",
      desc: "Đạt cấp tối đa.",
      stat: :level,
      goal: :max_level,
      title: "Bậc Thầy"
    },
    %{
      id: "villager",
      name: "Cánh Tay Phải",
      desc: "Hoàn thành mọi nhiệm vụ của Trưởng Làng.",
      stat: :quests,
      goal: :all_quests,
      title: "Người Của Làng"
    },
    %{
      id: "traveler",
      name: "Lữ Khách",
      desc: "Chạm vào mọi đá dịch chuyển.",
      stat: :waystones,
      goal: :all_waystones,
      title: "Lữ Khách"
    },
    %{
      id: "tower_10",
      name: "Leo Tháp",
      desc: "Vượt tầng 10 Tháp Vô Tận.",
      stat: :tower,
      goal: 10
    },
    %{
      id: "tower_30",
      name: "Trên Mây",
      desc: "Vượt tầng 30 Tháp Vô Tận.",
      stat: :tower,
      goal: 30,
      title: "Kẻ Leo Tháp"
    },
    %{
      id: "tower_50",
      name: "Không Có Đỉnh",
      desc: "Vượt tầng 50 Tháp Vô Tận.",
      stat: :tower,
      goal: 50,
      title: "Chúa Tể Tháp"
    },
    %{id: "fisher", name: "Buông Cần", desc: "Câu được 10 con cá.", stat: :fish, goal: 10},
    %{
      id: "angler",
      name: "Cần Thủ",
      desc: "Câu được 100 con cá.",
      stat: :fish,
      goal: 100,
      title: "Cần Thủ"
    },
    %{
      id: "golden_fish",
      name: "Cá Chép Hóa Rồng",
      desc: "Câu được Cá Chép Vàng.",
      stat: :gold_fish,
      goal: 1,
      title: "Vua Câu Cá"
    },
    %{
      id: "forged",
      name: "Thần Binh",
      desc: "Rèn một món đồ lên +5.",
      stat: :forge,
      goal: 5,
      title: "Thần Binh"
    },
    %{
      id: "reborn",
      name: "Tái Sinh",
      desc: "Chuyển sinh lần đầu.",
      stat: :rebirths,
      goal: 1,
      title: "Người Tái Sinh"
    },
    %{
      id: "naturalist",
      name: "Nhà Sinh Vật Học",
      desc: "Hạ ít nhất một con mỗi loài trong sổ tay quái vật.",
      stat: :species,
      goal: :all_species,
      title: "Nhà Sinh Vật Học"
    },
    %{
      id: "epic",
      name: "Của Hiếm",
      desc: "Nhặt được một món đồ Sử Thi.",
      stat: :epic,
      goal: 1,
      title: "Kẻ May Mắn"
    },
    %{
      id: "scale",
      name: "Vảy Cổ Long",
      desc: "Có Vảy Cổ Long từ trùm thế giới.",
      stat: :scale,
      goal: 1,
      title: "Săn Cổ Long"
    },
    %{
      id: "rich",
      name: "Đại Gia",
      desc: "Có 20.000 vàng trong túi.",
      stat: :gold,
      goal: 20_000,
      title: "Đại Gia"
    },
    %{
      id: "stubborn",
      name: "Lì Đòn",
      desc: "Gục ngã 10 lần mà vẫn chiến.",
      stat: :deaths,
      goal: 10,
      title: "Kẻ Lì Đòn"
    }
  ]

  def all, do: Enum.map(@list, &Map.put(&1, :goal, goal(&1)))
  def get(id), do: Enum.find(all(), &(&1.id == id))

  defp goal(%{goal: :max_level}), do: Engine.max_level()
  defp goal(%{goal: :all_quests}), do: length(Data.quests())
  defp goal(%{goal: :all_species}), do: length(Bestiary.species())
  defp goal(%{goal: :all_waystones}), do: length(Maps.waystone_ids())
  defp goal(%{goal: g}), do: g

  @doc "Giá trị hiện tại của chỉ số `stat` để so với mục tiêu."
  def value(p, :kills), do: p.kills
  def value(p, :bosses), do: length(p.bosses)
  def value(p, :victory), do: if(p.victory, do: 1, else: 0)
  def value(p, :level), do: p.level
  def value(p, :quests), do: length((Map.get(p, :quests) || %{done: []}).done)
  def value(p, :waystones), do: length(Map.get(p, :waystones) || [])
  def value(p, :tower), do: Map.get(p, :tower_best) || 0
  def value(p, :fish), do: Map.get(p, :fish_caught) || 0
  def value(p, :gold_fish), do: min(1, Map.get(p.inv, "fish_gold", 0))
  def value(p, :scale), do: min(1, Map.get(p.inv, "dragon_scale", 0))
  def value(p, :gold), do: p.gold
  def value(p, :rebirths), do: Map.get(p, :rebirths) || 0

  def value(p, :species),
    do: Enum.count(Bestiary.species(), &(Bestiary.count(p, &1) > 0))

  def value(p, :epic), do: min(1, Enum.count(Map.get(p, :gear) || [], &(&1.rarity == 3)))
  def value(p, :deaths), do: p.deaths

  def value(p, :forge),
    do: (Map.get(p, :upgrades) || %{}) |> Map.values() |> Enum.max(fn -> 0 end)

  defp have(p), do: Map.get(p, :achievements) || []

  @doc """
  Thêm các thành tựu vừa đủ điều kiện. Trả về `{nhân_vật, thông_báo | nil}`.
  """
  def check(nil), do: {nil, nil}

  def check(p) do
    got = have(p)
    new = Enum.filter(all(), &(&1.id not in got and value(p, &1.stat) >= &1.goal))

    case new do
      [] ->
        {p, nil}

      _ ->
        p = Map.put(p, :achievements, got ++ Enum.map(new, & &1.id))
        titles = new |> Enum.map(& &1[:title]) |> Enum.filter(& &1)

        msg =
          "🏅 Thành tựu mới: #{Enum.map_join(new, ", ", & &1.name)}." <>
            if(titles == [],
              do: "",
              else: " Danh hiệu mới: #{Enum.join(titles, ", ")} (chọn ở tab Nhân vật)."
            )

        {p, msg}
    end
  end

  @doc "Chọn danh hiệu (`nil` hoặc \"\" để bỏ)."
  def set_title(p, id) when id in [nil, ""],
    do: {%{ok: true, msg: "Đã bỏ danh hiệu."}, Map.put(p, :title, nil)}

  def set_title(p, id) do
    a = get(id)

    cond do
      a == nil or a[:title] == nil -> {%{ok: false, msg: "Không có danh hiệu này."}, p}
      id not in have(p) -> {%{ok: false, msg: "Bạn chưa đạt thành tựu \"#{a.name}\"."}, p}
      true -> {%{ok: true, msg: "Danh hiệu: #{a.title}."}, Map.put(p, :title, id)}
    end
  end

  @doc "Tên danh hiệu của id (nil nếu không có)."
  def title_name(nil), do: nil
  def title_name(id), do: get(id)[:title]

  @doc "Tiến độ mọi thành tựu, gửi cho client: `[%{id, done, have}]`."
  def view(p) do
    got = have(p)
    Enum.map(all(), &%{id: &1.id, done: &1.id in got, have: min(value(p, &1.stat), &1.goal)})
  end

  @doc "Danh sách cho client (không có hàm tính)."
  def client_data, do: Enum.map(all(), &Map.take(&1, [:id, :name, :desc, :title, :goal]))
end
