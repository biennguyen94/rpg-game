defmodule HacLong.RateLimit do
  @moduledoc """
  Giới hạn số lần làm một việc trong một khoảng thời gian (đếm theo cửa sổ cố định).

      RateLimit.hit({:login_ip, ip}, 20, :timer.minutes(5))
      #=> :ok | {:error, giây_phải_đợi}

  Bộ đếm nằm trong bảng ETS nên nhanh, không đụng database. Mất khi server khởi động lại,
  chấp nhận được với mục đích chống dò mật khẩu và spam. Mỗi phút dọn các cửa sổ đã cũ.
  """
  use GenServer

  @table __MODULE__
  @sweep_ms :timer.minutes(1)

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Tính thêm một lần cho `key`. Quá `limit` lần trong `window_ms` thì báo lỗi."
  def hit(key, limit, window_ms) do
    now = System.system_time(:millisecond)
    window = div(now, window_ms)
    k = {key, window_ms, window}
    count = :ets.update_counter(@table, k, {2, 1}, {k, 0, (window + 1) * window_ms})

    if count <= limit,
      do: :ok,
      else: {:error, max(1, div((window + 1) * window_ms - now + 999, 1000))}
  end

  @doc "Xóa hết bộ đếm (dùng trong test)."
  def reset, do: :ets.delete_all_objects(@table)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, s) do
    now = System.system_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    Process.send_after(self(), :sweep, @sweep_ms)
    {:noreply, s}
  end
end
