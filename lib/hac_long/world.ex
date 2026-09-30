defmodule HacLong.World do
  @moduledoc """
  Di chuyển trên bản đồ, gọi từ `HacLong.Game.Session` (tiến trình của người chơi).

  Vị trí nằm trong trạng thái nhân vật: `player.pos = %{map: id, x: x, y: y}`.
  Nhà là bản đồ riêng nên chỉ cần kiểm tra địa hình; các bản đồ khác dùng chung,
  đi qua `HacLong.World.MapServer` để biết ô nào có quái và ai đang ở đâu.

  Session luôn gọi MapServer, không bao giờ ngược lại, nên không thể bị treo chờ nhau.
  """

  alias HacLong.Game.{Data, Engine}
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

  @doc "Chỉ nghỉ trọ được ở Làng hoặc ở Nhà."
  def can_rest?(%{pos: %{map: m}}), do: m in [Maps.home(), "village"]

  @doc "Đi một bước theo hướng `dir`. Trả về `{kết_quả, nhân_vật}` như các lệnh khác."
  def move(p, uid, dir) do
    with {:ok, {dx, dy}} <- Map.fetch(@dirs, dir),
         nil <- p.battle do
      %{map: map_id, x: x, y: y} = p.pos
      map = Maps.get(map_id)
      {tx, ty} = {x + dx, y + dy}

      cond do
        portal = Maps.portal_at(map, tx, ty) -> use_portal(p, uid, portal)
        Maps.tile(map, tx, ty) == "F" -> drink_fountain(p)
        not Maps.walkable?(map, tx, ty) -> {%{ok: false}, p}
        map.private -> {%{ok: true}, put_pos(p, map_id, tx, ty)}
        true -> step_shared(p, uid, map, {tx, ty})
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
      {%{ok: false, msg: "Hạ #{prev.boss.name} để mở #{target.name}."}, p}
    else
      leave(p, uid)
      {x, y} = portal.spawn
      p = put_pos(p, target.id, x, y)
      enter(p, uid)
      {%{ok: true, msg: "Đến #{target.name}."}, p}
    end
  end

  defp step_shared(p, uid, map, {tx, ty} = to) do
    case MapServer.step(map.id, uid, to) do
      :ok ->
        {%{ok: true}, put_pos(p, map.id, tx, ty)}

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
