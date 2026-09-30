defmodule HacLong.Game.Rng do
  @moduledoc """
  Nguồn số ngẫu nhiên của engine. Mặc định dùng `:rand.uniform/0`.

  Test có thể cài một dãy số cố định cho tiến trình hiện tại bằng `put_sequence/1`
  để kết quả trận đấu lặp lại được (và so khớp với engine JS).
  """

  @key {__MODULE__, :seq}

  @doc "Số thực trong [0, 1)."
  def uniform do
    case Process.get(@key) do
      nil ->
        :rand.uniform()

      {[x | rest], all} ->
        Process.put(@key, {rest, all})
        x

      {[], [_ | _] = all} ->
        [x | rest] = all
        Process.put(@key, {rest, all})
        x
    end
  end

  @doc "Dùng dãy số cố định (lặp vòng) cho tiến trình hiện tại."
  def put_sequence(list) when is_list(list) and list != [], do: Process.put(@key, {list, list})

  def clear, do: Process.delete(@key)
end
