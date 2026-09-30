defmodule HacLongWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :hac_long

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_hac_long_key",
    signing_salt: "p8WDx3Py",
    same_site: "Lax"
  ]

  socket "/socket", HacLongWeb.UserSocket,
    websocket: true,
    longpoll: false

  # Giao diện: priv/static/{js,css,assets}. Trang chủ do PageController trả về.
  plug Plug.Static,
    at: "/",
    from: :hac_long,
    gzip: false,
    only: HacLongWeb.static_paths()

  # Thư viện client của Phoenix Channels.
  plug Plug.Static, at: "/vendor", from: {:phoenix, "priv/static"}, only: ~w(phoenix.js)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :hac_long
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug HacLongWeb.Router
end
