defmodule HacLongWeb.RemoteIp do
  @moduledoc """
  Lấy IP thật của người chơi khi server chạy sau proxy (nginx, load balancer).

  Proxy ghi IP gốc vào header `X-Forwarded-For` ("client, proxy1, proxy2"). Header này
  ai cũng tự ghi được, nên chỉ tin khi request đến từ một proxy nằm trong danh sách tin cậy,
  và lấy IP ngoài cùng bên phải không phải proxy tin cậy (đi ngược từ proxy gần nhất).

  Cấu hình: `config :hac_long, :trusted_proxies, ["10.0.0.0/8", "127.0.0.1"]` hoặc biến môi
  trường `TRUSTED_PROXIES="10.0.0.0/8,127.0.0.1"`. Để trống (mặc định) thì không đọc header.
  """
  @behaviour Plug
  import Bitwise

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case trusted() do
      [] ->
        conn

      nets ->
        if trusted?(conn.remote_ip, nets) do
          chain =
            conn
            |> Plug.Conn.get_req_header("x-forwarded-for")
            |> Enum.flat_map(&String.split(&1, ","))
            |> Enum.map(&String.trim/1)
            |> Enum.map(&parse_ip/1)

          case chain |> Enum.reverse() |> Enum.find(&(&1 && not trusted?(&1, nets))) do
            nil -> conn
            ip -> %{conn | remote_ip: ip}
          end
        else
          conn
        end
    end
  end

  defp trusted do
    Application.get_env(:hac_long, :trusted_proxies, [])
    |> Enum.map(&parse_cidr/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_ip(s) do
    case :inet.parse_address(String.to_charlist(s)) do
      {:ok, ip} -> ip
      _ -> nil
    end
  end

  @doc false
  def parse_cidr(s) do
    {addr, bits} =
      case String.split(String.trim(s), "/") do
        [a, b] -> {a, Integer.parse(b)}
        [a] -> {a, nil}
      end

    case parse_ip(addr) do
      nil ->
        nil

      ip ->
        size = if tuple_size(ip) == 4, do: 32, else: 128

        bits =
          case bits do
            {n, ""} when n >= 0 and n <= size -> n
            nil -> size
            _ -> nil
          end

        bits && {to_int(ip), size, bits}
    end
  end

  defp trusted?(ip, nets) do
    n = to_int(ip)
    size = if tuple_size(ip) == 4, do: 32, else: 128

    Enum.any?(nets, fn {net, nsize, bits} ->
      nsize == size and n >>> (size - bits) == net >>> (size - bits)
    end)
  end

  defp to_int(ip) when tuple_size(ip) == 4,
    do: ip |> Tuple.to_list() |> Enum.reduce(0, &(&2 * 256 + &1))

  defp to_int(ip), do: ip |> Tuple.to_list() |> Enum.reduce(0, &(&2 * 65_536 + &1))
end
