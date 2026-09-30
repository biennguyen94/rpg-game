defmodule HacLongWeb.ClientStatic do
  @moduledoc """
  Phục vụ file tĩnh của client (`js/`, `css/`, `assets/`) từ thư mục gốc của repo,
  để giao diện hiện tại dùng nguyên vẹn, không phải copy sang `priv/static`.
  Đường dẫn cấu hình bằng `config :hac_long, :client_dir` (hoặc biến môi trường
  `CLIENT_DIR` khi chạy production).
  """
  @behaviour Plug

  def dir, do: Application.fetch_env!(:hac_long, :client_dir)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    opts =
      case :persistent_term.get({__MODULE__, dir()}, nil) do
        nil ->
          o = Plug.Static.init(at: "/", from: dir(), only: ~w(js css assets), gzip: false)
          :persistent_term.put({__MODULE__, dir()}, o)
          o

        o ->
          o
      end

    Plug.Static.call(conn, opts)
  end
end
