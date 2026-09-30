defmodule HacLongWeb.PageController do
  use HacLongWeb, :controller

  @doc """
  Trả về `index.html` của client, chèn thêm thư viện Phoenix và `js/net.js`
  để giao diện chạy ở chế độ online (đăng nhập, lưu trên server).
  File gốc không đổi nên vẫn mở được bản offline như trước.
  """
  def index(conn, _params) do
    html =
      HacLongWeb.ClientStatic.dir()
      |> Path.join("index.html")
      |> File.read!()
      |> String.replace(
        ~s(<script src="js/ui.js"></script>),
        ~s(<script src="/vendor/phoenix.js"></script>\n<script src="js/net.js"></script>\n<script src="js/ui.js"></script>)
      )

    conn |> put_resp_content_type("text/html") |> send_resp(200, html)
  end
end
