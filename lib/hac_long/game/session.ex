defmodule HacLong.Game.Session do
  @moduledoc """
  Tiến trình giữ nhân vật của một tài khoản khi người chơi đang online.

  Mọi lệnh của cùng một tài khoản đi qua đúng một tiến trình này nên được xử lý
  lần lượt, kể cả khi mở nhiều tab: không có chuyện hai thao tác cùng đọc một
  trạng thái cũ rồi ghi đè nhau. Sau mỗi thay đổi, trạng thái được ghi vào
  PostgreSQL và phát cho các tab khác qua PubSub.

  - Các tab đang mở (`GameChannel`) gắn vào Session bằng `attach/2`. Còn ít nhất một tab thì
    nhân vật có mặt trên bản đồ; tab cuối đóng thì rời bản đồ. Không còn tab nào và
    không ai dùng trong `@idle_timeout` thì tiến trình tự tắt.
  - Bước đi (`"move"`) rất nhiều nên không ghi database mỗi bước: vị trí được ghi dồn sau
    `@flush_ms`, khi đổi bản đồ, khi vào trận, khi đóng game và khi tiến trình tắt.
  - Bước đi bị giới hạn tốc độ (`@step_ms`) để không chạy nhanh bằng script; các lệnh khác
    (đánh, mua bán...) cũng vậy (`@act_ms`), nhanh hơn tay người bấm nhiều.
  """
  use GenServer, restart: :transient

  alias HacLong.Game.{Characters, Commands, Quests}
  alias HacLong.World

  @idle_timeout :timer.minutes(10)
  @flush_ms 5_000
  # khoảng cách tối thiểu giữa hai bước, cho phép dồn vài bước khi mạng giật
  @step_ms 90
  @step_burst 4
  @act_ms 80
  @act_burst 10

  def topic(user_id), do: "player:#{user_id}"

  @doc "Trạng thái hiện tại (nil nếu chưa tạo nhân vật)."
  def get(user_id), do: call(user_id, :get)

  @doc "Tab `pid` mở game: nhân vật có mặt trên bản đồ. Trả về trạng thái hiện tại."
  def attach(user_id, pid), do: call(user_id, {:attach, pid})

  @doc "Chạy một lệnh từ client. Trả về `{kết_quả, nhân_vật}`."
  def command(user_id, cmd) when is_map(cmd), do: call(user_id, {:command, cmd, self()})

  defp call(user_id, msg, retry \\ true) do
    pid =
      case DynamicSupervisor.start_child(HacLong.Game.SessionSupervisor, {__MODULE__, user_id}) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    GenServer.call(pid, msg)
  catch
    # tiến trình vừa tự tắt vì rảnh đúng lúc gọi: khởi động lại và thử một lần nữa
    :exit, {reason, _} when retry and reason in [:noproc, :normal] -> call(user_id, msg, false)
  end

  def start_link(user_id) do
    GenServer.start_link(__MODULE__, user_id,
      name: {:via, Registry, {HacLong.Game.Registry, user_id}}
    )
  end

  @impl true
  def init(user_id) do
    # để `terminate/2` chạy khi server tắt (deploy) và ghi nốt vị trí chưa lưu
    Process.flag(:trap_exit, true)

    s = %{
      user_id: user_id,
      player: Characters.load(user_id),
      tabs: %{},
      dirty: false,
      flush_timer: nil,
      steps: {@step_burst, now()},
      acts: {@act_burst, now()}
    }

    {:ok, s, @idle_timeout}
  end

  @impl true
  def handle_call(:get, _from, s), do: reply(s.player, s)

  def handle_call({:attach, pid}, _from, s) do
    if map_size(s.tabs) == 0, do: World.enter(s.player, s.user_id)
    s = %{s | tabs: Map.put(s.tabs, Process.monitor(pid), pid)}
    reply(s.player, s)
  end

  def handle_call({:command, %{"act" => act} = cmd, origin}, _from, s)
      when act in ["move", "teleport"] do
    case take(s, :steps, @step_ms, @step_burst) do
      {:ok, s} ->
        {result, player} = run_move(s, cmd)
        old = s.player

        s =
          cond do
            player == old ->
              s

            old.pos.map != player.pos.map or player.battle != nil or
                player.waystones != old.waystones ->
              save(s, player)

            true ->
              s |> Map.put(:player, player) |> mark_dirty()
          end

        if player != old, do: broadcast(s, player, origin)
        reply({result, player}, s)

      :too_fast ->
        reply({%{ok: false}, s.player}, s)
    end
  end

  def handle_call({:command, cmd, origin}, _from, s) do
    case take(s, :acts, @act_ms, @act_burst) do
      {:ok, s} -> run_command(s, cmd, origin)
      :too_fast -> reply({%{ok: false, msg: "Thao tác quá nhanh."}, s.player}, s)
    end
  end

  defp run_command(s, cmd, origin) do
    old = s.player
    {result, player} = Commands.run(old, cmd)
    player = after_command(s, old, player, cmd)

    s =
      if player != old do
        broadcast(s, player, origin)
        if player, do: save(s, player), else: delete(s)
      else
        s
      end

    reply({result, player}, s)
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _}, s) do
    s = %{s | tabs: Map.delete(s.tabs, ref)}

    if map_size(s.tabs) == 0 do
      World.leave(s.player, s.user_id)
      {:noreply, flush(s), @idle_timeout}
    else
      {:noreply, s}
    end
  end

  def handle_info(:flush, s), do: {:noreply, flush(%{s | flush_timer: nil}), timeout(s)}

  def handle_info(:timeout, s) do
    if map_size(s.tabs) == 0, do: {:stop, :normal, flush(s)}, else: {:noreply, s}
  end

  def handle_info({:EXIT, _pid, _reason}, s), do: {:noreply, s, timeout(s)}

  @impl true
  def terminate(_reason, s), do: flush(s)

  # ---------- Nội bộ ----------

  defp reply(value, s), do: {:reply, value, s, timeout(s)}

  # Còn tab đang mở thì không tự tắt (nhân vật vẫn đứng trên bản đồ).
  defp timeout(%{tabs: tabs}) when map_size(tabs) > 0, do: :infinity
  defp timeout(_), do: @idle_timeout

  defp run_move(%{player: nil} = s, _cmd), do: {%{ok: false, msg: "Chưa có nhân vật."}, s.player}

  defp run_move(s, %{"act" => "teleport"} = cmd),
    do: World.teleport(s.player, s.user_id, cmd["to"])

  defp run_move(s, cmd),
    do: World.move(s.player, s.user_id, cmd["dir"], cmd["confirm"] == true)

  defp after_command(s, old, player, cmd) do
    cond do
      # trận vừa kết thúc: cập nhật quái trên bản đồ, gục ngã thì về Nhà
      player && old && old.battle && not old.battle.over && player.battle && player.battle.over ->
        player = World.finish_encounter(player, s.user_id)

        # lần đầu hạ Hắc Long: ghi lại thời điểm cho bảng xếp hạng
        player =
          if player.victory and not old.victory,
            do: Map.put(player, :victory_at, DateTime.truncate(DateTime.utc_now(), :second)),
            else: player

        if player.battle.result == "win",
          do: Quests.on_kill(player, player.battle.monster.id),
          else: player

      cmd["act"] == "create" and player && old == nil ->
        if map_size(s.tabs) > 0, do: World.enter(player, s.user_id)
        player

      cmd["act"] == "reset" and old && player == nil ->
        World.leave(old, s.user_id)
        player

      true ->
        player
    end
  end

  # Xô token: mỗi `every_ms` hồi một lượt, tối đa `burst` lượt.
  defp take(s, key, every_ms, burst) do
    {tokens, at} = Map.fetch!(s, key)
    t = now()
    tokens = min(burst, tokens + (t - at) / every_ms)

    if tokens >= 1,
      do: {:ok, Map.put(s, key, {tokens - 1, t})},
      else: :too_fast
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp broadcast(s, player, origin) do
    Phoenix.PubSub.broadcast(HacLong.PubSub, topic(s.user_id), {:player, player, origin})
  end

  defp save(s, player) do
    Characters.save!(s.user_id, player)
    cancel_flush(%{s | player: player, dirty: false})
  end

  defp delete(s) do
    Characters.delete!(s.user_id)
    cancel_flush(%{s | player: nil, dirty: false})
  end

  defp mark_dirty(%{flush_timer: nil} = s),
    do: %{s | dirty: true, flush_timer: Process.send_after(self(), :flush, @flush_ms)}

  defp mark_dirty(s), do: %{s | dirty: true}

  defp cancel_flush(%{flush_timer: nil} = s), do: s

  defp cancel_flush(s) do
    Process.cancel_timer(s.flush_timer)
    %{s | flush_timer: nil}
  end

  defp flush(%{dirty: true, player: p} = s) when p != nil, do: save(s, p)
  defp flush(s), do: s
end
