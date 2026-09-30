defmodule HacLong.World.MapServer do
  @moduledoc """
  Một tiến trình cho mỗi bản đồ dùng chung (Làng và các vùng quái).

  Giữ vị trí quái và người chơi đang có mặt. Mọi thay đổi trên bản đồ đi qua đây nên
  được xử lý lần lượt: hai người cùng lao vào một con quái thì chỉ người đến trước được đánh.

  - Quái sinh ra theo `spawns` của bản đồ, đi lang thang mỗi `:wander_ms` (cấu hình),
    bị hạ thì hồi lại sau `respawn` giây. Quái không bước vào ô có người, cổng hay quái khác.
  - Ban đêm (`HacLong.World.Clock`) quái thường mới sinh có `@rare_chance` là quái Bóng Đêm
    (`rare: true`): mạnh hơn, thưởng nhiều hơn, dễ rơi đồ hơn (xem `HacLong.World`).
  - Người chơi bước vào ô có quái thì con quái bị khóa cho người đó (`busy`) tới khi trận xong.
  - Điểm thu thập (thảo dược, quặng) mọc theo `gather`; ai bước vào trước thì hái được,
    điểm đó biến mất và mọc lại ở chỗ ngẫu nhiên sau `respawn` giây.
  - Người chơi được gắn với tiến trình `Session` của họ; Session tắt thì tự rời bản đồ và
    nhả quái đang khóa.
  - Có thay đổi thì gom lại và phát toàn bộ trạng thái bản đồ qua PubSub `"map:<id>"`
    (tối đa khoảng 20 lần mỗi giây).
  """
  use GenServer

  alias HacLong.Game.Data
  alias HacLong.World.{Clock, Maps}

  @flush_ms 50
  @dirs [{0, -1}, {0, 1}, {-1, 0}, {1, 0}]
  # quái không sinh ra quá gần cổng để người vừa vào không bị đánh ngay
  @safe_radius 3
  @rare_chance 0.12

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

  @doc "Đổi thông tin người khác thấy (tên, cấp, ngoại hình...) của người đang ở bản đồ."
  def update(map_id, uid, info), do: GenServer.call(via(map_id), {:update, uid, info})

  @doc """
  Người chơi bước sang ô `{x, y}` (đã kiểm tra địa hình). Trả về:
  `:ok` (đã đi), `{:engage, quái}` (ô có quái, quái đã bị khóa cho người này, người
  đứng yên), `{:busy, quái}` (quái đang đánh với người khác) hoặc `{:confirm_boss, trùm}`
  (ô có trùm mà chưa xác nhận muốn đấu: chưa khóa gì), hoặc `{:gather, điểm}` (ô có
  điểm thu thập: đã hái, điểm biến mất; người đứng yên).
  """
  def step(map_id, uid, {x, y}, confirm_boss? \\ false),
    do: GenServer.call(via(map_id), {:step, uid, {x, y}, confirm_boss?})

  @doc "Trận thắng: quái biến mất và hẹn giờ hồi lại."
  def defeat(map_id, uid, mid), do: GenServer.call(via(map_id), {:defeat, uid, mid})

  @doc "Người giữ quái rời trận chung nhưng đồng đội vẫn đánh: chuyển quái cho `to`."
  def reassign(map_id, from, mid, to), do: GenServer.call(via(map_id), {:reassign, from, mid, to})

  @doc "Trận thua hoặc bỏ chạy: nhả quái ra."
  def release(map_id, uid, mid), do: GenServer.call(via(map_id), {:release, uid, mid})

  def snapshot(map_id), do: GenServer.call(via(map_id), :snapshot)

  @doc "Đặt một con quái vào ô cho trước (dùng trong test)."
  def put_monster(map_id, kind, {x, y}, boss? \\ false, rare? \\ false),
    do: GenServer.call(via(map_id), {:put_monster, kind, {x, y}, boss?, rare?})

  @doc "Đặt một điểm thu thập vào ô cho trước (dùng trong test)."
  def put_node(map_id, item, {x, y}), do: GenServer.call(via(map_id), {:put_node, item, {x, y}})

  @doc "Xóa hết quái, điểm thu thập và tắt hồi (dùng trong test)."
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
      nodes: %{},
      players: %{},
      next_id: 1,
      flush_scheduled: false,
      respawn: true
    }

    s = Enum.reduce(Enum.with_index(map.spawns), s, fn {sp, i}, s -> fill_spawn(s, sp, i) end)
    s = Enum.reduce(Enum.with_index(map.gather), s, fn {g, i}, s -> fill_nodes(s, g, i) end)
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

  def handle_call({:update, uid, info}, _from, s) do
    case s.players[uid] do
      nil -> {:reply, :ok, s}
      pl -> {:reply, :ok, changed(put_in(s.players[uid], Map.merge(pl, info)))}
    end
  end

  def handle_call({:step, uid, pos, confirm?}, _from, s) do
    case node_at(s, pos) do
      nil -> step_monster(s, uid, pos, confirm?)
      node -> {:reply, {:gather, public_node(node)}, gathered(s, node)}
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

  def handle_call({:reassign, from, mid, to}, _from, s) do
    case s.monsters[mid] do
      %{busy: ^from} -> {:reply, :ok, changed(put_in(s.monsters[mid].busy, to))}
      _ -> {:reply, :ok, s}
    end
  end

  def handle_call({:release, uid, mid}, _from, s) do
    case s.monsters[mid] do
      %{busy: ^uid} -> {:reply, :ok, changed(put_in(s.monsters[mid].busy, nil))}
      _ -> {:reply, :ok, s}
    end
  end

  def handle_call(:snapshot, _from, s), do: {:reply, snapshot_of(s), s}

  def handle_call({:put_monster, kind, pos, boss?, rare?}, _from, s) do
    origin = if boss?, do: :boss, else: {:manual, kind}
    {m, s} = new_monster(s, kind, pos, boss?, origin)
    m = %{m | rare: rare?}
    s = put_in(s.monsters[m.id], m)
    {:reply, public(m), changed(s)}
  end

  def handle_call({:put_node, item, pos}, _from, s) do
    s = new_node(s, item, pos, :manual)
    {:reply, public_node(s.nodes[s.next_id - 1]), changed(s)}
  end

  def handle_call(:clear_monsters, _from, s),
    do: {:reply, :ok, changed(%{s | monsters: %{}, nodes: %{}, respawn: false})}

  @impl true
  def handle_info(:wander, s) do
    schedule_wander()
    {:noreply, wander(s)}
  end

  def handle_info({:respawn, :boss}, s), do: {:noreply, if(s.respawn, do: spawn_boss(s), else: s)}

  def handle_info({:respawn, {:spawn, i}}, s) do
    if s.respawn, do: {:noreply, fill_spawn(s, Enum.at(s.map.spawns, i), i)}, else: {:noreply, s}
  end

  def handle_info({:respawn, {:gather, i}}, s) do
    if s.respawn,
      do: {:noreply, fill_nodes(s, Enum.at(s.map.gather, i), i)},
      else: {:noreply, s}
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

  defp step_monster(s, uid, pos, confirm?) do
    case monster_at(s, pos) do
      %{boss: true, busy: nil} = m when not confirm? ->
        {:reply, {:confirm_boss, public(m)}, s}

      %{busy: nil} = m ->
        {:reply, {:engage, public(m)}, changed(put_in(s.monsters[m.id].busy, uid))}

      %{busy: ^uid} = m ->
        {:reply, {:engage, public(m)}, s}

      %{} = m ->
        {:reply, {:busy, Map.put(public(m), :owner, m.busy)}, s}

      nil ->
        s = if s.players[uid], do: put_in(s.players[uid].pos, pos), else: s
        {:reply, :ok, changed(s)}
    end
  end

  defp node_at(s, pos), do: Enum.find_value(s.nodes, fn {_, n} -> n.pos == pos && n end)

  defp gathered(s, node) do
    s = %{s | nodes: Map.delete(s.nodes, node.id)}

    case node.origin do
      {:gather, i} when s.respawn ->
        Process.send_after(
          self(),
          {:respawn, node.origin},
          Enum.at(s.map.gather, i).respawn * 1000
        )

      _ ->
        :ok
    end

    changed(s)
  end

  defp fill_nodes(s, g, i) do
    have = Enum.count(s.nodes, fn {_, n} -> n.origin == {:gather, i} end)

    Enum.reduce(1..(g.max - have)//1, s, fn _, s ->
      case free_tile(s) do
        nil -> s
        pos -> s |> new_node(g.item, pos, {:gather, i}) |> changed()
      end
    end)
  end

  defp new_node(s, item, pos, origin) do
    n = %{id: s.next_id, item: item, pos: pos, origin: origin}
    %{s | nodes: Map.put(s.nodes, n.id, n), next_id: s.next_id + 1}
  end

  defp public_node(n) do
    {x, y} = n.pos
    %{id: n.id, item: n.item, x: x, y: y}
  end

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
    rare = match?({:spawn, _}, origin) and Clock.night?() and :rand.uniform() < @rare_chance
    m = %{id: s.next_id, kind: kind, pos: pos, boss: boss?, busy: nil, origin: origin, rare: rare}
    {m, %{s | monsters: Map.put(s.monsters, m.id, m), next_id: s.next_id + 1}}
  end

  defp monster_at(s, pos), do: Enum.find_value(s.monsters, fn {_, m} -> m.pos == pos && m end)

  defp occupied?(s, pos) do
    Enum.any?(s.monsters, fn {_, m} -> m.pos == pos end) or
      Enum.any?(s.nodes, fn {_, n} -> n.pos == pos end) or
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
    %{id: m.id, kind: m.kind, x: x, y: y, boss: m.boss, busy: m.busy != nil, rare: m.rare}
  end

  defp snapshot_of(s) do
    %{
      map: s.map.id,
      phase: Clock.phase(),
      monsters: s.monsters |> Map.values() |> Enum.map(&public/1),
      nodes: s.nodes |> Map.values() |> Enum.map(&public_node/1),
      players:
        Enum.map(s.players, fn {uid, p} ->
          {x, y} = p.pos

          %{
            id: uid,
            name: p.name,
            cls: p.cls,
            level: p.level,
            look: p[:look],
            tag: p[:tag],
            x: x,
            y: y
          }
        end)
    }
  end
end
