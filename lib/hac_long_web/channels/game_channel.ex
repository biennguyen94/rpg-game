defmodule HacLongWeb.GameChannel do
  @moduledoc """
  Kênh chơi game.

  - Client gửi `"cmd"` với payload `%{"act" => ..., ...}` (xem `HacLong.Game.Commands`;
    bước đi là `%{"act" => "move", "dir" => "up" | "down" | "left" | "right"}`) và nhận lại
    kết quả kèm trạng thái nhân vật mới.
  - Khi nhân vật đổi từ tab khác, server đẩy `"player"`.
  - Server đẩy `"map"` với quái và người chơi trên bản đồ nhân vật đang đứng, mỗi khi
    bản đồ đó thay đổi. Kênh tự chuyển theo dõi khi nhân vật sang bản đồ khác.
  - Chat thế giới: client gửi `"chat"` với `%{"text" => ...}`; server đẩy `"chat"` (một tin)
    cho mọi người và `"chat_history"` (các tin gần nhất) lúc mới vào.
  - `"leaderboard"`: trả về các bảng xếp hạng và hạng của mình.
  """
  use HacLongWeb, :channel

  alias HacLong.{Chat, Leaderboard, RateLimit}
  alias HacLong.Game.{Daily, Data, Engine, Quests, Session}
  alias HacLong.World.{Maps, MapServer}

  @impl true
  def join("game", _params, socket) do
    uid = socket.assigns.user_id
    Phoenix.PubSub.subscribe(HacLong.PubSub, Session.topic(uid))
    Phoenix.PubSub.subscribe(HacLong.PubSub, Chat.topic())
    player = Session.attach(uid, self())
    send(self(), :push_map)

    {:ok, %{username: socket.assigns.username, user_id: uid, player: present(player)},
     assign(socket, :map, nil)}
  end

  @impl true
  def handle_in("cmd", %{} = cmd, socket) do
    {result, player} = Session.command(socket.assigns.user_id, cmd)
    socket = follow_map(socket, player)
    {:reply, {:ok, Map.put(result, :player, present(player))}, socket}
  end

  def handle_in("chat", %{"text" => text}, socket) do
    uid = socket.assigns.user_id

    with :ok <- chat_limit(uid),
         %{} = p <- Session.get(uid) || {:error, "Hãy tạo nhân vật trước."},
         {:ok, _msg} <- Chat.post(%{uid: uid, name: p.name, map: p.pos.map}, text) do
      {:reply, :ok, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("leaderboard", _payload, socket) do
    uid = socket.assigns.user_id

    case RateLimit.hit({:leaderboard, uid}, 20, :timer.minutes(1)) do
      :ok ->
        boards = Map.new(Leaderboard.kinds(), &{&1, Leaderboard.top(&1)})
        {:reply, {:ok, Map.put(boards, :me, Leaderboard.level_rank(uid))}, socket}

      {:error, _} ->
        {:reply, {:error, %{msg: "Thao tác quá nhanh."}}, socket}
    end
  end

  def handle_in(_event, _payload, socket), do: {:reply, {:error, %{msg: "Sai cú pháp."}}, socket}

  # 5 tin mỗi 10 giây, chống spam.
  defp chat_limit(uid) do
    case RateLimit.hit({:chat, uid}, 5, 10_000) do
      :ok -> :ok
      {:error, secs} -> {:error, "Chat chậm lại chút, đợi #{secs} giây."}
    end
  end

  @impl true
  def handle_info(:push_map, socket) do
    push(socket, "chat_history", %{messages: Chat.history()})
    {:noreply, follow_map(socket, Session.get(socket.assigns.user_id))}
  end

  def handle_info({:chat, msg}, socket) do
    push(socket, "chat", msg)
    {:noreply, socket}
  end

  def handle_info({:player, player, origin}, socket) do
    if origin != self(), do: push(socket, "player", %{player: present(player)})
    {:noreply, follow_map(socket, player)}
  end

  def handle_info({:map_state, id, snap}, socket) do
    if id == socket.assigns.map, do: push(socket, "map", snap)
    {:noreply, socket}
  end

  # Nhân vật sang bản đồ khác: đổi kênh PubSub đang nghe và gửi ngay trạng thái bản đồ mới.
  defp follow_map(socket, player) do
    map_id = player && player.pos.map

    if map_id == socket.assigns.map do
      socket
    else
      if old = socket.assigns.map, do: unsubscribe(old)

      if map_id do
        if Maps.get(map_id).private do
          push(socket, "map", %{map: map_id, monsters: [], nodes: [], players: []})
        else
          Phoenix.PubSub.subscribe(HacLong.PubSub, MapServer.topic(map_id))
          push(socket, "map", MapServer.snapshot(map_id))
        end
      end

      assign(socket, :map, map_id)
    end
  end

  defp unsubscribe(map_id) do
    unless Maps.get(map_id).private,
      do: Phoenix.PubSub.unsubscribe(HacLong.PubSub, MapServer.topic(map_id))
  end

  # Kèm các chỉ số tính sẵn (máu tối đa, tấn công, giá nghỉ trọ...) cho client hiển thị.
  defp present(nil), do: nil

  defp present(player) do
    # có việc mới hoặc việc đã xong chờ trả: hiện dấu "!" trên đầu Trưởng Làng
    ready =
      Quests.available(player) != [] or
        Enum.any?(Map.keys(player.quests.active), &Quests.complete?(player, Data.quest(&1)))

    view =
      player
      |> Engine.view()
      |> Map.merge(%{
        questReady: ready,
        dailyReady: Daily.ready?(player),
        dailyLeft: Daily.seconds_left()
      })

    Map.put(player, :view, view)
  end
end
