defmodule HacLong.World do
  @moduledoc """
  Di chuyển trên bản đồ, gọi từ `HacLong.Game.Session` (tiến trình của người chơi).

  Vị trí nằm trong trạng thái nhân vật: `player.pos = %{map: id, x: x, y: y}`.
  Nhà là bản đồ riêng nên chỉ cần kiểm tra địa hình; các bản đồ khác dùng chung,
  đi qua `HacLong.World.MapServer` để biết ô nào có quái và ai đang ở đâu.

  Session luôn gọi MapServer, không bao giờ ngược lại, nên không thể bị treo chờ nhau.
  """

  alias HacLong.Game.{Daily, Data, Engine}
  alias HacLong.World.{Maps, MapServer}

  @dirs %{"up" => {0, -1}, "down" => {0, 1}, "left" => {-1, 0}, "right" => {1, 0}}

  def dirs, do: Map.keys(@dirs)

  @doc "Vị trí hợp lệ (bản đồ tồn tại, ô đi được), nếu không thì về Nhà."
  def valid_pos(%{map: id, x: x, y: y} = pos) do
    case Maps.get(id) do
      nil -> Maps.home_spawn()
      map -> if Maps.walkable?(map, x, y), do: pos, else: Maps.home_spawn()
    end
  end

  def valid_pos(_), do: Maps.home_spawn()

  defp shared?(%{map: id}), do: not Maps.get(id).private

  defp info(p), do: %{name: p.name, cls: p.cls, level: p.level}

  @doc "Có mặt trên bản đồ hiện tại (khi người chơi mở game)."
  def enter(%{pos: pos} = p, uid) do
    if shared?(pos), do: MapServer.enter(pos.map, uid, info(p), {pos.x, pos.y})
    :ok
  end

  def enter(_p, _uid), do: :ok

  @doc "Rời bản đồ hiện tại (đóng game, xóa nhân vật)."
  def leave(%{pos: pos}, uid) do
    if shared?(pos), do: MapServer.leave(pos.map, uid)
    :ok
  end

  def leave(_p, _uid), do: :ok

  @doc "NPC đứng ngay cạnh nhân vật có một trong các `roles` (hoặc nil)."
  def near_npc(%{pos: %{map: id, x: x, y: y}}, roles) do
    Enum.find(Maps.get(id).npcs, fn %{at: {nx, ny}} = n ->
      n.role in roles and abs(nx - x) + abs(ny - y) == 1
    end)
  end

  def near_npc(_p, _roles), do: nil

  @doc """
  Đi một bước theo hướng `dir`. Trả về `{kết_quả, nhân_vật}` như các lệnh khác.

  Bước vào trùm thì lần đầu chỉ nhận `%{confirm: "boss", boss: ...}`; gửi lại với
  `confirm: true` mới vào trận. Bước vào đá dịch chuyển thì ghi nhớ đá đó và nhận
  `%{waystone: true}` để client mở bảng chọn nơi đến. Bước vào NPC thì nhận `%{npc: id}`
  để mở hội thoại. Bước vào điểm thu thập thì nhận nguyên liệu.
  """
  def move(p, uid, dir, confirm? \\ false) do
    with {:ok, {dx, dy}} <- Map.fetch(@dirs, dir),
         nil <- p.battle do
      %{map: map_id, x: x, y: y} = p.pos
      map = Maps.get(map_id)
      {tx, ty} = {x + dx, y + dy}

      cond do
        portal = Maps.portal_at(map, tx, ty) -> use_portal(p, uid, portal)
        npc = Maps.npc_at(map, tx, ty) -> {%{ok: true, npc: npc.id}, p}
        Maps.tile(map, tx, ty) == "F" -> drink_fountain(p)
        Maps.tile(map, tx, ty) == "W" -> touch_waystone(p, map)
        not Maps.walkable?(map, tx, ty) -> {%{ok: false}, p}
        map.private -> {%{ok: true}, put_pos(p, map_id, tx, ty)}
        true -> step_shared(p, uid, map, {tx, ty}, confirm?)
      end
    else
      :error -> {%{ok: false, msg: "Hướng đi không hợp lệ."}, p}
      _battle -> {%{ok: false, msg: "Đang trong trận đấu."}, p}
    end
  end

  defp put_pos(p, map, x, y), do: %{p | pos: %{map: map, x: x, y: y}}

  defp drink_fountain(p) do
    max_hp = Engine.derived(p).maxHp

    if p.hp >= max_hp,
      do: {%{ok: false, msg: "Nước giếng mát lạnh. Máu đang đầy."}, p},
      else: {%{ok: true, msg: "Uống nước giếng, máu đã đầy."}, %{p | hp: max_hp}}
  end

  defp use_portal(p, uid, portal) do
    target = Maps.get(portal.to)

    if target.zone && not Engine.zone_unlocked?(p, target.zone) do
      prev = Data.zone(target.zone - 1)
      {%{ok: false, msg: "Hạ #{prev.boss.name} để mở #{Data.zone(target.zone).name}."}, p}
    else
      leave(p, uid)
      {x, y} = portal.spawn
      p = put_pos(p, target.id, x, y)
      enter(p, uid)
      {%{ok: true, msg: "Đến #{target.name}."}, p}
    end
  end

  defp step_shared(p, uid, map, {tx, ty} = to, confirm?) do
    case MapServer.step(map.id, uid, to, confirm? == true) do
      :ok ->
        {%{ok: true}, put_pos(p, map.id, tx, ty)}

      {:gather, node} ->
        item = Data.item(node.item)
        verb = if String.starts_with?(node.item, "ore"), do: "Đào", else: "Hái"
        p = p |> Engine.add_item(node.item) |> Daily.on_gather(node.item)
        {%{ok: true, msg: "#{verb} được #{item.name}."}, p}

      {:confirm_boss, m} ->
        boss = Data.zone(map.zone).boss

        {%{ok: false, confirm: "boss", boss: %{id: m.kind, name: boss.name, level: boss.level}},
         p}

      {:busy, _m} ->
        {%{ok: false, msg: "Con quái này đang giao chiến với người khác."}, p}

      {:engage, m} ->
        zone = Data.zone(map.zone)
        spec = if m.boss, do: zone.boss, else: Enum.find(zone.monsters, &(&1.id == m.kind))

        case Engine.start_encounter(p, map.zone, spec, m.boss) do
          {%{ok: true} = r, p} ->
            {r, put_in(p.battle[:encounter], %{map: map.id, mid: m.id})}

          {r, p} ->
            MapServer.release(map.id, uid, m.id)
            {r, p}
        end
    end
  end

  # ---------- Đá dịch chuyển ----------

  defp touch_waystone(p, map) do
    known = Map.get(p, :waystones, [])

    if map.id in known or map.id == "village" do
      {%{ok: true, waystone: true}, p}
    else
      {%{ok: true, waystone: true, msg: "Đã ghi nhớ đá dịch chuyển ở #{map.name}."},
       Map.put(p, :waystones, known ++ [map.id])}
    end
  end

  @doc "Những nơi có thể dịch chuyển tới: Làng và các đá đã ghi nhớ."
  def waystones(p), do: ["village" | Map.get(p, :waystones, [])]

  defp next_to_waystone?(%{pos: %{map: id, x: x, y: y}}) do
    case Maps.get(id).waystone do
      %{at: {wx, wy}} -> abs(wx - x) + abs(wy - y) == 1
      nil -> false
    end
  end

  @doc "Dịch chuyển từ đá đang đứng cạnh tới đá ở bản đồ `to`."
  def teleport(p, uid, to) do
    target = is_binary(to) && Maps.get(to)

    cond do
      p.battle ->
        {%{ok: false, msg: "Đang trong trận đấu."}, p}

      not next_to_waystone?(p) ->
        {%{ok: false, msg: "Hãy đứng cạnh đá dịch chuyển."}, p}

      !target or target.waystone == nil ->
        {%{ok: false, msg: "Không có đá dịch chuyển ở đó."}, p}

      to not in waystones(p) ->
        {%{ok: false, msg: "Bạn chưa tới đá dịch chuyển đó."}, p}

      to == p.pos.map ->
        {%{ok: false, msg: "Bạn đang ở đây rồi."}, p}

      target.zone && not Engine.zone_unlocked?(p, target.zone) ->
        {%{ok: false, msg: "Vùng chưa mở."}, p}

      true ->
        leave(p, uid)
        {x, y} = target.waystone.spawn
        p = put_pos(p, target.id, x, y)
        enter(p, uid)
        {%{ok: true, msg: "Dịch chuyển tới #{target.name}."}, p}
    end
  end

  @doc """
  Gọi khi trận vừa kết thúc: thắng thì quái biến mất khỏi bản đồ, thua hoặc chạy thì
  nhả quái ra. Gục ngã thì được đưa về Nhà.
  """
  def finish_encounter(%{battle: %{over: true} = b} = p, uid) do
    case b[:encounter] do
      %{map: map_id, mid: mid} ->
        if b.result == "win",
          do: MapServer.defeat(map_id, uid, mid),
          else: MapServer.release(map_id, uid, mid)

      _ ->
        :ok
    end

    if b.result == "lose" do
      leave(p, uid)
      %{p | pos: Maps.home_spawn()}
    else
      p
    end
  end

  def finish_encounter(p, _uid), do: p
end
