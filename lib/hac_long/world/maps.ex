defmodule HacLong.World.Maps do
  @moduledoc """
  Bản đồ ô vuông, đọc lúc biên dịch từ `priv/maps/*.json`.

  Mỗi bản đồ vẽ bằng ký tự trong `tiles` (xem `legend/0`), cộng thêm:

  - `zone`: chỉ số vùng trong `game_data.json` (quái và trùm lấy từ đó), `null` với Nhà và Làng.
  - `floor`: hình nền cho ô `.` (đường dẫn trong `priv/static/assets`, không có đuôi).
  - `portals`: `{at: [x, y], to: id_bản_đồ, spawn: [x, y]}`. Bước vào ô cổng thì sang
    bản đồ `to`, đứng ở `spawn`. Cổng vào vùng chưa mở (chưa hạ trùm vùng trước) bị khóa.
  - `spawns`: `{monster, max, respawn}`: loại quái, số con tối đa, số giây hồi lại.
  - `boss`: `{at, respawn}`: chỗ trùm của vùng đứng (trùm không đi lang thang).
  - `private: true`: bản đồ riêng của mỗi người (Nhà), không có ai khác.
  """

  @dir Path.expand("../../../priv/maps", __DIR__)
  @files Path.wildcard(Path.join(@dir, "*.json"))
  for f <- @files, do: @external_resource(f)

  # Ký tự → loại ô. Ô đi được: nền, cỏ, đường đất, hoa và các cổng.
  @legend %{
    "." => "floor",
    "," => "grass",
    ":" => "dirt",
    "*" => "flowers",
    "T" => "tree",
    "Y" => "tree_autumn",
    "K" => "tree_dead",
    "R" => "rock",
    "~" => "water",
    "#" => "brick",
    "S" => "stone",
    "I" => "column",
    "F" => "fountain",
    "D" => "door",
    "A" => "arch",
    "O" => "portal"
  }
  @walkable MapSet.new(~w(. , : * D A O))

  @maps (for f <- @files, into: %{} do
           m = f |> File.read!() |> Jason.decode!()
           rows = m["tiles"]

           map = %{
             id: m["id"],
             name: m["name"],
             zone: m["zone"],
             floor: m["floor"],
             private: m["private"] == true,
             width: String.length(hd(rows)),
             height: length(rows),
             tiles: rows,
             grid: rows |> Enum.map(&List.to_tuple(String.graphemes(&1))) |> List.to_tuple(),
             portals:
               Enum.map(m["portals"], fn p ->
                 %{at: List.to_tuple(p["at"]), to: p["to"], spawn: List.to_tuple(p["spawn"])}
               end),
             spawns:
               Enum.map(
                 m["spawns"],
                 &%{monster: &1["monster"], max: &1["max"], respawn: &1["respawn"]}
               ),
             boss:
               m["boss"] && %{at: List.to_tuple(m["boss"]["at"]), respawn: m["boss"]["respawn"]}
           }

           {map.id, map}
         end)

  @home "home"

  def get(id), do: Map.get(@maps, id)
  def ids, do: Map.keys(@maps)
  def shared_ids, do: for({id, m} <- @maps, not m.private, do: id)
  def legend, do: @legend
  def home, do: @home

  @doc "Chỗ đứng mặc định ở Nhà (nhân vật mới, gục ngã)."
  def home_spawn do
    [p | _] = get(@home).portals
    {x, y} = p.at
    %{map: @home, x: x, y: y - 1}
  end

  def tile(%{grid: g, width: w, height: h}, x, y)
      when is_integer(x) and is_integer(y) and x >= 0 and y >= 0 and x < w and y < h,
      do: g |> elem(y) |> elem(x)

  def tile(_, _, _), do: nil

  def walkable?(map, x, y), do: tile(map, x, y) in @walkable

  def portal_at(map, x, y), do: Enum.find(map.portals, &(&1.at == {x, y}))

  @doc "Dữ liệu gửi cho client để vẽ."
  def client_data do
    maps =
      Map.new(@maps, fn {id, m} ->
        {id,
         %{
           name: m.name,
           zone: m.zone,
           floor: m.floor,
           tiles: m.tiles,
           portals: Enum.map(m.portals, &%{at: Tuple.to_list(&1.at), to: &1.to})
         }}
      end)

    %{maps: maps, legend: @legend, walkable: MapSet.to_list(@walkable)}
  end
end
