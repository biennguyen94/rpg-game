defmodule HacLongWeb.RemoteIpTest do
  use ExUnit.Case, async: false
  import Plug.Test

  alias HacLongWeb.RemoteIp

  setup do
    on_exit(fn -> Application.delete_env(:hac_long, :trusted_proxies) end)
  end

  defp call(peer, xff) do
    conn(:get, "/")
    |> Map.put(:remote_ip, peer)
    |> then(fn c -> if xff, do: Plug.Conn.put_req_header(c, "x-forwarded-for", xff), else: c end)
    |> RemoteIp.call([])
    |> Map.get(:remote_ip)
  end

  test "không cấu hình proxy thì không tin header (tránh giả IP)" do
    assert call({1, 2, 3, 4}, "9.9.9.9") == {1, 2, 3, 4}
  end

  test "request từ proxy tin cậy thì lấy IP ngoài cùng không phải proxy" do
    Application.put_env(:hac_long, :trusted_proxies, ["10.0.0.0/8", "127.0.0.1"])
    assert call({10, 0, 0, 5}, "203.0.113.7") == {203, 0, 113, 7}

    # người chơi tự ghi IP giả ở đầu chuỗi: bỏ qua, lấy IP mà proxy của mình ghi vào
    assert call({10, 0, 0, 5}, "1.1.1.1, 203.0.113.7, 10.1.2.3") == {203, 0, 113, 7}
    assert call({127, 0, 0, 1}, "203.0.113.9") == {203, 0, 113, 9}
    # request không đi qua proxy tin cậy: giữ nguyên
    assert call({8, 8, 8, 8}, "203.0.113.7") == {8, 8, 8, 8}
    # header hỏng hoặc toàn proxy: giữ nguyên
    assert call({10, 0, 0, 5}, "rác") == {10, 0, 0, 5}
    assert call({10, 0, 0, 5}, "10.9.9.9") == {10, 0, 0, 5}
    assert call({10, 0, 0, 5}, nil) == {10, 0, 0, 5}
  end

  test "IPv6 và CIDR" do
    Application.put_env(:hac_long, :trusted_proxies, ["fd00::/8"])
    assert call({0xFD00, 0, 0, 0, 0, 0, 0, 1}, "2001:db8::5") == {0x2001, 0xDB8, 0, 0, 0, 0, 0, 5}
    assert RemoteIp.parse_cidr("10.0.0.0/33") == nil
    assert RemoteIp.parse_cidr("không phải ip") == nil
  end
end
