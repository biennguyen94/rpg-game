defmodule HacLong.Game.Events do
  @moduledoc """
  Sự kiện theo mùa (`EVENTS` trong `game_data.json`): mỗi sự kiện có khoảng ngày trong năm
  (`from`, `to` dạng "MM-DD", giờ Việt Nam; qua năm mới được, vd. 12-15 tới 01-02).

  Trong thời gian sự kiện:
  - quái thường có 20% rơi vật phẩm lễ hội (`token`), trùm rơi 3 cái;
  - kinh nghiệm mỗi trận +10%;
  - Người Tổ Chức Hội trong Làng đổi vật phẩm lễ hội lấy quà (`exchange/2`): đồ trang trí chỉ
    có trong mùa đó, bình máu lớn, món đồ chỉ số ngẫu nhiên, vàng.

  Thử một sự kiện bất kỳ lúc nào: cấu hình `:hac_long, :event` (hoặc biến môi trường `EVENT`)
  là id sự kiện, hay `"none"` để tắt (test mặc định tắt).
  """

  alias HacLong.Game.{Daily, Data, Engine, Gear}

  @drop_chance 0.2
  @xp_bonus 0.1

  def drop_chance, do: @drop_chance
  def xp_bonus(nil), do: 0
  def xp_bonus(_event), do: @xp_bonus

  @doc "Sự kiện đang diễn ra (nil nếu không có)."
  def current(now \\ DateTime.utc_now()) do
    case Application.get_env(:hac_long, :event) || System.get_env("EVENT") do
      "none" -> nil
      nil -> on_date(Daily.today(now))
      id -> Data.event(id)
    end
  end

  @doc "Sự kiện diễn ra vào ngày `date` (\"YYYY-MM-DD\")."
  def on_date(date) do
    md = String.slice(date, 5, 5)

    Enum.find(Data.events(), fn e ->
      if e.from <= e.to, do: md >= e.from and md <= e.to, else: md >= e.from or md <= e.to
    end)
  end

  @doc "Sự kiện sắp tới tính từ ngày `date`: `{sự_kiện, số_ngày_nữa}`."
  def next(date) do
    d = Date.from_iso8601!(date)

    Enum.map(Data.events(), fn e ->
      start = start_after(d, e.from)
      {e, Date.diff(start, d)}
    end)
    |> Enum.min_by(&elem(&1, 1))
  end

  defp start_after(d, md) do
    [m, day] = md |> String.split("-") |> Enum.map(&String.to_integer/1)
    this = Date.new!(d.year, m, day)
    if Date.compare(this, d) == :lt, do: Date.new!(d.year + 1, m, day), else: this
  end

  @doc "Quà đổi được ở sự kiện `e`: `[%{id, name, cost, kind}]` (giá tính bằng vật phẩm lễ hội)."
  def shop(e, p) do
    decor = Data.furniture(e.decor)

    [
      %{
        id: "decor",
        name: decor.name,
        cost: 30,
        desc: "Đồ trang trí chỉ có trong mùa này (tiện nghi #{decor.comfort})."
      },
      %{
        id: "gear",
        name: "Túi Quà Lễ Hội",
        cost: 12,
        desc: "Một món đồ chỉ số ngẫu nhiên (dễ ra Hiếm)."
      },
      %{id: "potions", name: "3 Bình Máu Lớn", cost: 6, desc: "Hồi 650 máu mỗi bình."},
      %{id: "gold", name: "#{gold(p)} vàng", cost: 3, desc: "Vàng tăng theo cấp nhân vật."}
    ]
  end

  defp gold(p), do: 60 + p.level * 12

  @doc "Đổi vật phẩm lễ hội lấy quà `id` (đứng cạnh Người Tổ Chức Hội)."
  def exchange(p, id) do
    e = current()
    offer = e && Enum.find(shop(e, p), &(&1.id == id))

    cond do
      e == nil ->
        {%{ok: false, msg: "Chưa tới mùa lễ hội."}, p}

      offer == nil ->
        {%{ok: false, msg: "Không có quà này."}, p}

      Map.get(p.inv, e.token, 0) < offer.cost ->
        {%{ok: false, msg: "Cần #{offer.cost} #{Data.item(e.token).name}."}, p}

      id == "gear" and length(Gear.bag(p)) >= Gear.max_bag() ->
        {%{ok: false, msg: "Túi đồ hiếm đầy (#{Gear.max_bag()} món). Bán bớt đã."}, p}

      true ->
        left = p.inv[e.token] - offer.cost
        inv = if left > 0, do: Map.put(p.inv, e.token, left), else: Map.delete(p.inv, e.token)
        p = %{p | inv: inv} |> Map.put(:festival, (Map.get(p, :festival) || 0) + 1)
        {p, msg} = give(p, e, id)
        {%{ok: true, msg: msg}, p}
    end
  end

  defp give(p, e, "decor") do
    stock = Map.get(p, :furniture) || %{}
    p = Map.put(p, :furniture, Map.update(stock, e.decor, 1, &(&1 + 1)))
    {p, "Nhận #{Data.furniture(e.decor).name}! Về Nhà bấm Trang trí để đặt."}
  end

  defp give(p, _e, "gear") do
    g = Gear.roll(max(p.level, 3), [{3, 15}, {2, 60}, {1, 25}])
    {p, :kept} = Gear.add(p, g)
    it = Gear.resolve(g)
    {p, "Túi Quà Lễ Hội: #{it.name} (#{Gear.rarity_names()[g.rarity]})!"}
  end

  defp give(p, _e, "potions"), do: {Engine.add_item(p, "potion_l", 3), "Nhận 3 Bình Máu Lớn."}

  defp give(p, _e, "gold") do
    g = gold(p)
    {%{p | gold: p.gold + g}, "Nhận #{g} vàng."}
  end

  @doc "Đồ trang trí chỉ có trong sự kiện thì Thợ Mộc không bán."
  def event_decor?(id), do: Enum.any?(Data.events(), &(&1.decor == id))
end
