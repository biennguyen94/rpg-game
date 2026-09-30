defmodule HacLongWeb.GameChannel do
  @moduledoc """
  Kênh chơi game. Client gửi `"cmd"` với payload `%{"act" => ..., ...}` (xem
  `HacLong.Game.Commands`) và nhận lại kết quả kèm trạng thái nhân vật mới.
  Khi nhân vật đổi từ tab khác, server đẩy `"player"` xuống.
  """
  use HacLongWeb, :channel

  alias HacLong.Game.Session

  @impl true
  def join("game", _params, socket) do
    uid = socket.assigns.user_id
    Phoenix.PubSub.subscribe(HacLong.PubSub, Session.topic(uid))
    {:ok, %{username: socket.assigns.username, player: Session.get(uid)}, socket}
  end

  @impl true
  def handle_in("cmd", %{} = cmd, socket) do
    {result, player} = Session.command(socket.assigns.user_id, cmd)
    {:reply, {:ok, Map.put(result, :player, player)}, socket}
  end

  def handle_in(_event, _payload, socket), do: {:reply, {:error, %{msg: "Sai cú pháp."}}, socket}

  @impl true
  def handle_info({:player, _player, origin}, socket) when origin == self(),
    do: {:noreply, socket}

  def handle_info({:player, player, _origin}, socket) do
    push(socket, "player", %{player: player})
    {:noreply, socket}
  end
end
