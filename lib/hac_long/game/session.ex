defmodule HacLong.Game.Session do
  @moduledoc """
  Tiến trình giữ nhân vật của một tài khoản khi người chơi đang online.

  Mọi lệnh của cùng một tài khoản đi qua đúng một tiến trình này nên được xử lý
  lần lượt, kể cả khi mở nhiều tab: không có chuyện hai thao tác cùng đọc một
  trạng thái cũ rồi ghi đè nhau. Sau mỗi thay đổi, trạng thái được ghi ngay vào
  PostgreSQL và phát cho các tab khác qua PubSub. Không có ai dùng trong
  `@idle_timeout` thì tiến trình tự tắt.
  """
  use GenServer, restart: :transient

  alias HacLong.Game.{Characters, Commands}

  @idle_timeout :timer.minutes(10)

  def topic(user_id), do: "player:#{user_id}"

  @doc "Trạng thái hiện tại (nil nếu chưa tạo nhân vật)."
  def get(user_id), do: call(user_id, :get)

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
    {:ok, %{user_id: user_id, player: Characters.load(user_id)}, @idle_timeout}
  end

  @impl true
  def handle_call(:get, _from, s), do: {:reply, s.player, s, @idle_timeout}

  def handle_call({:command, cmd, origin}, _from, s) do
    {result, player} = Commands.run(s.player, cmd)

    if player != s.player do
      if player, do: Characters.save!(s.user_id, player), else: Characters.delete!(s.user_id)
      Phoenix.PubSub.broadcast(HacLong.PubSub, topic(s.user_id), {:player, player, origin})
    end

    {:reply, {result, player}, %{s | player: player}, @idle_timeout}
  end

  @impl true
  def handle_info(:timeout, s), do: {:stop, :normal, s}
end
