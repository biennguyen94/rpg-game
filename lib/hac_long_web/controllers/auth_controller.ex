defmodule HacLongWeb.AuthController do
  use HacLongWeb, :controller

  alias HacLong.{Accounts, RateLimit}

  # Giới hạn để chống dò mật khẩu và tạo tài khoản hàng loạt: {số lần, trong bao lâu}.
  @login_per_ip {30, :timer.minutes(5)}
  @login_per_name {10, :timer.minutes(5)}
  @register_per_ip {5, :timer.hours(1)}
  @password_per_user {5, :timer.minutes(5)}

  def register(conn, params) do
    with :ok <- limit(conn, {:register, ip(conn)}, @register_per_ip) do
      case Accounts.register(Map.take(params, ["username", "password"])) do
        {:ok, user} ->
          conn |> put_status(:created) |> json(session(user))

        {:error, cs} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: first_error(cs)})
      end
    end
  end

  def login(conn, params) do
    name = params["username"] |> to_string() |> String.trim() |> String.downcase()

    with :ok <- limit(conn, {:login_ip, ip(conn)}, @login_per_ip),
         :ok <- limit(conn, {:login_name, name}, @login_per_name) do
      case Accounts.authenticate(params["username"], params["password"]) do
        {:ok, user} ->
          json(conn, session(user))

        {:error, _} ->
          conn |> put_status(:unauthorized) |> json(%{error: "Sai tên đăng nhập hoặc mật khẩu."})
      end
    end
  end

  def me(conn, _params) do
    with {:ok, user, _token} <- current(conn) do
      json(conn, %{username: user.username})
    end
  end

  @doc "Đăng xuất thiết bị này (thu hồi token đang dùng)."
  def logout(conn, _params) do
    with {:ok, _user, token} <- current(conn) do
      Accounts.revoke_token(token)
      json(conn, %{ok: true})
    end
  end

  @doc "Đăng xuất mọi thiết bị: thu hồi mọi token và ngắt mọi kết nối game đang mở."
  def logout_all(conn, _params) do
    with {:ok, user, _token} <- current(conn) do
      Accounts.revoke_all(user)
      disconnect(user)
      json(conn, %{ok: true})
    end
  end

  @doc "Đổi mật khẩu. Mọi thiết bị khác bị đăng xuất; thiết bị này nhận token mới."
  def password(conn, params) do
    with {:ok, user, _token} <- current(conn),
         :ok <- limit(conn, {:password, user.id}, @password_per_user) do
      case Accounts.change_password(user, to_string(params["current"]), params["password"]) do
        {:ok, user} ->
          disconnect(user)
          json(conn, session(user))

        {:error, :invalid} ->
          conn |> put_status(:unauthorized) |> json(%{error: "Mật khẩu hiện tại không đúng."})

        {:error, cs} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: first_error(cs)})
      end
    end
  end

  # ---------- Nội bộ ----------

  defp current(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Accounts.verify_token(token) do
      {:ok, user, token}
    else
      _ -> conn |> put_status(:unauthorized) |> json(%{error: "Phiên đăng nhập đã hết hạn."})
    end
  end

  defp limit(conn, key, {n, window}) do
    case RateLimit.hit(key, n, window) do
      :ok ->
        :ok

      {:error, secs} ->
        wait = if secs >= 60, do: "#{div(secs + 59, 60)} phút", else: "#{secs} giây"

        conn
        |> put_resp_header("retry-after", Integer.to_string(secs))
        |> put_status(:too_many_requests)
        |> json(%{error: "Thử quá nhiều lần. Đợi #{wait} rồi thử lại."})
    end
  end

  # Ngắt mọi WebSocket của người này (xem `HacLongWeb.UserSocket.id/1`).
  defp disconnect(user),
    do: HacLongWeb.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})

  # Địa chỉ IP của người gọi (đã tính X-Forwarded-For nếu có proxy tin cậy, xem
  # HacLongWeb.RemoteIp).
  defp ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp session(user), do: %{token: Accounts.sign_token(user), username: user.username}

  @labels %{username: "Tên đăng nhập", password: "Mật khẩu"}

  defp first_error(cs) do
    {field, {msg, _}} = hd(cs.errors)
    "#{Map.get(@labels, field, field)} #{msg}."
  end
end
