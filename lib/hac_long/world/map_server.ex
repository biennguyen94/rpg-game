defmodule HacLong.World.MapServer do
  @moduledoc """
  Một tiến trình cho mỗi bản đồ dùng chung (Làng và các vùng quái).

  Giữ vị trí quái và người chơi đang có mặt. Mọi thay đổi trên bản đồ đi qua đây nên
  được xử lý lần lượt: hai người cùng lao vào một con quái thì chỉ người đến trước được đánh.

  - Quái sinh ra theo `spawns` của bản đồ, đi lang thang mỗi `:wander_ms` (cấu hình),
    bị hạ thì hồi lại sau `respawn` giây. Quái không bước vào ô có người, cổng hay quái khác.
  - Người chơi bước vào ô có quái thì con quái bị khóa cho người đó (`busy`) tới khi trận xong.
  - Người chơi được gắn với tiến trình `Session` của họ; Session tắt thì tự rời bản đồ và
    nhả quái đang khóa.
  - Có thay đổi thì gom lại và phát toàn bộ trạng thái bản đồ qua PubSub `"map:<id>"`
    (tối đa khoảng 20 lần mỗi giây).
  """
  use GenServer

  alias HacLong.Game.Data
  alias HacLong.World.Maps

  @flush_ms 50
  @dirs [{0, -1}, {0, 1}, {-1, 0}, {1, 0}]
  # quái không sinh ra quá gần cổng để người vừa vào không bị đánh ngay
  @safe_radius 3

  def topic(map_id), do: "map:#{map_id}"

  def child_spec(map_id),
    do: %{id: {__MODULE__, map_id}, start: {__MODULE__, :start_link, [map_id]}}

  def start_link(map_id),
    do: GenServer.start_link(__MODULE__, map_id, name: via(map_id))

  defp via(map_id), do: {:via, Registry, {HacLong.World.Registry, map_id}}

  # ---------- API ----------

  @doc "Người chơi vào bản đồ. `info`: tên, lớp, cấp để người khác nhìn thấy."
  def enter(map_id, uid, info, {x, y}),
    do: GenServer.call(via(map_id), {:enter, uid, info, {x, y}, self()})

  def leave(map_id, uid), do: GenServer.call(via(map_id), {:leave, uid})

  @doc """
  Người chơi bước sang ô `{x, y}` (đã kiểm tra địa hình). Trả về:
  `:ok` (đã đi), `{:engage, quái}` (ô có quái, quái đã bị khóa cho người này, người
  đứng yên), `{:busy, quái}` (quái đang đánh với người khác) hoặc `{:confirm_boss, trùm}`
  (ô có trùm mà chưa xác nhận muốn đấu: chưa khóa gì).
  """
  def step(map_id, uid, {x, y}, confirm_boss? \\ false),
    do: GenServer.call(via(map_id), {:step, uid, {x, y}, confirm_boss?})

  @doc "Trận thắng: quái biến mất và hẹn giờ hồi lại."
  def defeat(map_id, uid, mid), do: GenServer.call(via(map_id), {:defeat, uid, mid})

  @doc "Trận thua hoặc bỏ chạy: nhả quái ra."
  def release(map_id, uid, mid), do: GenServer.call(via(map_id), {:release, uid, mid})

  def snapshot(map_id), do: GenServer.call(via(map_id), :snapshot)

  @doc "Đặt một con quái vào ô cho trước (dùng trong test)."
  def put_monster(map_id, kind, {x, y}, boss? \\ false),
    do: GenServer.call(via(map_id), {:put_monster, kind, {x, y}, boss?})

  @doc "Xóa hết quái và tắt hồi quái (dùng trong test)."
  def clear_monsters(map_id), do: GenServer.call(via(map_id), :clear_monsters)

  # ---------- Tiến trình ----------

  @impl true
  def init(map_id) do
    map = Maps.get(map_id)
    zone = map.zone && Data.zone(map.zone)

    s = %{
      map: map,
      zone: zone,
      monsters: %{},
      players: %{},
      next_id: 1,
      flush_scheduled: false,
      respawn: true
    }

    s = Enum.reduce(Enum.with_index(map.spawns), s, fn {sp, i}, s -> fill_spawn(s, sp, i) end)
    s = if map.boss && zone, do: spawn_boss(s), else: s
    schedule_wander()
    {:ok, s}
  end

  @impl true
  def handle_call({:enter, uid, info, pos, pid}, _from, s) do
    # vào lại (vd. đổi tab) thì bỏ theo dõi tiến trình cũ
    with %{ref: ref} <- s.players[uid], do: Process.demonitor(ref, [:flush])

    ref = Process.monitor(pid)
    player = Map.merge(info, %{id: uid, pos: pos, ref: ref})
    {:reply, :ok, changed(put_in(s.players[uid], player))}
  end

  def handle_call({:leave, uid}, _from, s), do: {:reply, :ok, remove_player(s, uid)}

  def handle_call({:step, uid, pos, confirm?}, _from, s) do
    case monster_at(s, pos) do
      %{boss: true, busy: nil} = m when not confirm? ->
        {:reply, {:confirm_boss, public(m)}, s}

      %{busy: nil} = m ->
        {:reply, {:engage, public(m)}, changed(put_in(s.monsters[m.id].busy, uid))}

      %{busy: ^uid} = m ->
        {:reply, {:engage, public(m)}, s}

      %{} = m ->
        {:reply, {:busy, public(m)}, s}

      nil ->
        s = if s.players[uid], do: put_in(s.players[uid].pos, pos), else: s
        {:reply, :ok, changed(s)}
    end
  end

  def handle_call({:defeat, uid, mid}, _from, s) do
    case s.monsters[mid] do
      %{busy: ^uid} = m ->
        s = %{s | monsters: Map.delete(s.monsters, mid)}

        if s.respawn,
          do: Process.send_after(self(), {:respawn, m.origin}, respawn_ms(s, m.origin))

        {:reply, :ok, changed(s)}

      _ ->
        {:reply, :ok, s}
    end
  end

  def handle_call({:release, uid, mid}, _from, s) do
    case s.monsters[mid] do
      %{busy: ^uid} -> {:reply, :ok, changed(put_in(s.monsters[mid].busy, nil))}
      _ -> {:reply, :ok, s}
    end
  end

  def handle_call(:snapshot, _from, s), do: {:reply, snapshot_of(s), s}

  def handle_call({:put_monster, kind, pos, boss?}, _from, s) do
    origin = if boss?, do: :boss, else: {:manual, kind}
    {m, s} = new_monster(s, kind, pos, boss?, origin)
    {:reply, public(m), changed(s)}
  end

  def handle_call(:clear_monsters, _from, s),
    do: {:reply, :ok, changed(%{s | monsters: %{}, respawn: false})}

  @impl true
  def handle_info(:wander, s) do
    schedule_wander()
    {:noreply, wander(s)}
  end

  def handle_info({:respawn, :boss}, s), do: {:noreply, if(s.respawn, do: spawn_boss(s), else: s)}

  def handle_info({:respawn, {:spawn, i}}, s) do
    if s.respawn, do: {:noreply, fill_spawn(s, Enum.at(s.map.spawns, i), i)}, else: {:noreply, s}
  end

  def handle_info({:respawn, _}, s), do: {:noreply, s}

  def handle_info(:flush, s) do
    Phoenix.PubSub.broadcast(
      HacLong.PubSub,
      topic(s.map.id),
      {:map_state, s.map.id, snapshot_of(s)}
    )

    {:noreply, %{s | flush_scheduled: false}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _}, s) do
    case Enum.find(s.players, fn {_, p} -> p.ref == ref end) do
      {uid, _} -> {:noreply, remove_player(s, uid)}
      nil -> {:noreply, s}
    end
  end

  # ---------- Nội bộ ----------

  defp remove_player(s, uid) do
    case Map.pop(s.players, uid) do
      {nil, _} ->
        s

      {p, players} ->
        Process.demonitor(p.ref, [:flush])

        monsters =
          Map.new(s.monsters, fn
            {id, %{busy: ^uid} = m} -> {id, %{m | busy: nil}}
            other -> other
          end)

        changed(%{s | players: players, monsters: monsters})
    end
  end

  defp changed(%{flush_scheduled: true} = s), do: s

  defp changed(s) do
    Process.send_after(self(), :flush, @flush_ms)
    %{s | flush_scheduled: true}
  end

  defp schedule_wander do
    case Application.get_env(:hac_long, :wander_ms) do
      ms when is_integer(ms) -> Process.send_after(self(), :wander, ms)
      _ -> :ok
    end
  end

  defp respawn_ms(s, :boss), do: s.map.boss.respawn * 1000
  defp respawn_ms(s, {:spawn, i}), do: Enum.at(s.map.spawns, i).respawn * 1000
  defp respawn_ms(_s, _), do: 30_000

  defp fill_spawn(s, sp, i) do
    have = Enum.count(s.monsters, fn {_, m} -> m.origin == {:spawn, i} end)

    Enum.reduce(1..(sp.max - have)//1, s, fn _, s ->
      case free_tile(s) do
        nil -> s
        pos -> s |> new_monster(sp.monster, pos, false, {:spawn, i}) |> elem(1) |> changed()
      end
    end)
  end

  defp spawn_boss(s) do
    if Enum.any?(s.monsters, fn {_, m} -> m.boss end) do
      s
    else
      {_, s} = new_monster(s, s.zone.boss.id, s.map.boss.at, true, :boss)
      changed(s)
    end
  end

  defp new_monster(s, kind, pos, boss?, origin) do
    m = %{id: s.next_id, kind: kind, pos: pos, boss: boss?, busy: nil, origin: origin}
    {m, %{s | monsters: Map.put(s.monsters, m.id, m), next_id: s.next_id + 1}}
  end

  defp monster_at(s, pos), do: Enum.find_value(s.monsters, fn {_, m} -> m.pos == pos && m end)

  defp occupied?(s, pos) do
    Enum.any?(s.monsters, fn {_, m} -> m.pos == pos end) or
      Enum.any?(s.players, fn {_, p} -> p.pos == pos end)
  end

  defp open_tile?(s, {x, y} = pos) do
    Maps.walkable?(s.map, x, y) and Maps.portal_at(s.map, x, y) == nil and not occupied?(s, pos)
  end

  # Ô trống ngẫu nhiên, cách xa các cổng và người chơi.
  defp free_tile(s) do
    far? = fn {x, y}, {px, py} -> abs(x - px) + abs(y - py) > @safe_radius end

    candidates =
      for y <- 0..(s.map.height - 1),
          x <- 0..(s.map.width - 1),
          open_tile?(s, {x, y}),
          Enum.all?(s.map.portals, &far?.({x, y}, &1.at)),
          Enum.all?(s.players, fn {_, p} -> far?.({x, y}, p.pos) end),
          s.map.boss == nil or far?.({x, y}, s.map.boss.at),
          do: {x, y}

    if candidates == [], do: nil, else: Enum.random(candidates)
  end

  defp wander(s) do
    Enum.reduce(Map.keys(s.monsters), s, fn id, s ->
      m = s.monsters[id]

      if m.boss or m.busy != nil or :rand.uniform() > 0.35 do
        s
      else
        {x, y} = m.pos
        {dx, dy} = Enum.random(@dirs)
        to = {x + dx, y + dy}
        if open_tile?(s, to), do: changed(put_in(s.monsters[id].pos, to)), else: s
      end
    end)
  end

  defp public(m) do
    {x, y} = m.pos
    %{id: m.id, kind: m.kind, x: x, y: y, boss: m.boss, busy: m.busy != nil}
  end

  defp snapshot_of(s) do
    %{
      map: s.map.id,
      monsters: s.monsters |> Map.values() |> Enum.map(&public/1),
      players:
        Enum.map(s.players, fn {uid, p} ->
          {x, y} = p.pos
          %{id: uid, name: p.name, cls: p.cls, level: p.level, x: x, y: y}
        end)
    }
  end
end
