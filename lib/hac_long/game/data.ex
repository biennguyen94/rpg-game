defmodule HacLong.Game.Data do
  @moduledoc """
  Dữ liệu game, đọc lúc biên dịch từ `priv/game_data.json` (sửa file đó để thêm
  quái, vùng đất, vật phẩm; biên dịch lại là có hiệu lực). Client nhận cùng dữ liệu
  này qua `window.GAME_DATA` (xem `HacLongWeb.PageController`).

  - `CLASSES`: lớp nhân vật với chỉ số gốc (`base`), tăng mỗi cấp (`growth`) và kỹ năng.
  - `ZONES`: vùng đất theo thứ tự mở khóa; mỗi vùng có quái thường và một trùm.
    Quái chỉ khai báo `level`, `mult` (hệ số sức mạnh, mặc định 1) và `special`
    (đòn đặc biệt của trùm, dùng mỗi `every` lượt với sát thương ×`mult`);
    chỉ số còn lại tính trong `HacLong.Game.Engine.make_monster/2`.
  - `ITEMS`: `slot` là weapon | armor | shield | potion; `drop: true` là đồ chỉ rơi từ trùm.
  - `BOSS_DROPS`: đồ trùm rơi ra lần đầu bị hạ. `SHOP`: những món cửa hàng bán.

  Khóa của các trường được chuyển thành atom; id (lớp, vật phẩm, trùm) giữ nguyên là chuỗi
  vì chúng đến từ client và được lưu trong database.
  """

  @path Path.expand("../../../priv/game_data.json", __DIR__)
  @external_resource @path

  atomize = fn atomize, v ->
    cond do
      is_map(v) -> Map.new(v, fn {k, x} -> {String.to_atom(k), atomize.(atomize, x)} end)
      is_list(v) -> Enum.map(v, &atomize.(atomize, &1))
      true -> v
    end
  end

  raw = @path |> File.read!() |> Jason.decode!()
  by_id = fn m -> Map.new(m, fn {id, x} -> {id, atomize.(atomize, x)} end) end

  @classes by_id.(raw["CLASSES"])
  @zones atomize.(atomize, raw["ZONES"])
  @items by_id.(raw["ITEMS"])
  @boss_drops raw["BOSS_DROPS"]
  @shop raw["SHOP"]

  def classes, do: @classes
  def class(id), do: Map.get(@classes, id)
  def zones, do: @zones
  def zone(i) when is_integer(i) and i >= 0, do: Enum.at(@zones, i)
  def zone(_), do: nil
  def zone_count, do: length(@zones)
  def items, do: @items
  def item(id), do: Map.get(@items, id)
  def boss_drop(boss_id), do: Map.get(@boss_drops, boss_id)
  def shop, do: @shop
end
