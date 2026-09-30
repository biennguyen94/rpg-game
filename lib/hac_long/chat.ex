defmodule HacLong.Chat do
  @moduledoc """
  Chat thế giới: ai cũng thấy tin của mọi người. Tin không lưu database; tiến trình này
  giữ 50 tin gần nhất để người mới vào xem lại, và phát tin mới qua PubSub `"chat"`.
  """
  use GenServer

  @topic "chat"
  @keep 50
  @max_len 120

  def topic, do: @topic

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Các tin gần nhất, cũ trước mới sau."
  def history, do: GenServer.call(__MODULE__, :history)

  @doc """
  Gửi tin. `from`: `%{uid, name, map}`. Chữ được bỏ ký tự điều khiển, gộp khoảng trắng,
  cắt còn #{@max_len} ký tự. Trả về `{:ok, tin}` hoặc `{:error, lý_do}`.
  """
  def post(from, text) when is_binary(text) do
    text =
      text
      |> String.replace(~r/[\p{Cc}\p{Cf}]/u, " ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
      |> String.slice(0, @max_len)

    if text == "",
      do: {:error, "Tin nhắn trống."},
      else: GenServer.call(__MODULE__, {:post, from, text})
  end

  def post(_from, _text), do: {:error, "Tin nhắn không hợp lệ."}

  @doc "Thông báo của hệ thống (trùm thế giới xuất hiện...)."
  def system(text),
    do: GenServer.call(__MODULE__, {:post, %{uid: 0, name: "Thông báo", map: nil}, text})

  @impl true
  def init(_), do: {:ok, %{msgs: [], next: 1}}

  @impl true
  def handle_call(:history, _from, s), do: {:reply, Enum.reverse(s.msgs), s}

  def handle_call({:post, from, text}, _from, s) do
    msg = %{
      id: s.next,
      uid: from.uid,
      name: from.name,
      map: from.map,
      text: text,
      at: System.system_time(:millisecond)
    }

    Phoenix.PubSub.broadcast(HacLong.PubSub, @topic, {:chat, msg})
    {:reply, {:ok, msg}, %{s | msgs: Enum.take([msg | s.msgs], @keep), next: s.next + 1}}
  end
end
