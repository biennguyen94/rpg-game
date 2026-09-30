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
  - `ITEMS` có `slot: "material"`: nguyên liệu (thu thập trên bản đồ), `sprite` là hình của nó.
  - `RECIPES`: công thức pha chế ở NPC `npc`: `needs` (nguyên liệu → số lượng) ra một `out`.
  - `QUESTS`: nhiệm vụ nhận ở Trưởng Làng. `type`: `kill` (hạ `count` con `target`),
    `collect` (nộp `count` nguyên liệu `target`), `boss` (hạ trùm `target`). Nhận được khi
    vùng `zone` đã mở và đã xong các nhiệm vụ trong `requires`.

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
  @recipes atomize.(atomize, raw["RECIPES"])
           |> Enum.map(
             &Map.update!(&1, :needs, fn n ->
               Map.new(n, fn {k, v} -> {Atom.to_string(k), v} end)
             end)
           )
  @quests atomize.(atomize, raw["QUESTS"])
          |> Enum.map(fn q ->
            Map.update!(q, :reward, fn r ->
              Map.update!(r, :items, fn i ->
                Map.new(i, fn {k, v} -> {Atom.to_string(k), v} end)
              end)
            end)
          end)

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
  def recipes, do: @recipes
  def recipe(id), do: Enum.find(@recipes, &(&1.id == id))
  def quests, do: @quests
  def quest(id), do: Enum.find(@quests, &(&1.id == id))
end
