defmodule HacLongWeb.UserSocket do
  use Phoenix.Socket

  channel "game", HacLongWeb.GameChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case HacLong.Accounts.verify_token(token) do
      {:ok, user} ->
        {:ok, assign(socket, user_id: user.id, username: user.username, admin: user.admin)}

      _ ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"
end
