defmodule HacLongWeb.AuthController do
  use HacLongWeb, :controller

  alias HacLong.Accounts

  def register(conn, params) do
    case Accounts.register(Map.take(params, ["username", "password"])) do
      {:ok, user} ->
        conn |> put_status(:created) |> json(session(user))

      {:error, cs} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: first_error(cs)})
    end
  end

  def login(conn, params) do
    case Accounts.authenticate(params["username"], params["password"]) do
      {:ok, user} ->
        json(conn, session(user))

      {:error, _} ->
        conn |> put_status(:unauthorized) |> json(%{error: "Sai tên đăng nhập hoặc mật khẩu."})
    end
  end

  def me(conn, _params) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Accounts.verify_token(token) do
      json(conn, %{username: user.username})
    else
      _ -> conn |> put_status(:unauthorized) |> json(%{error: "Phiên đăng nhập đã hết hạn."})
    end
  end

  defp session(user), do: %{token: Accounts.sign_token(user), username: user.username}

  @labels %{username: "Tên đăng nhập", password: "Mật khẩu"}

  defp first_error(cs) do
    {field, {msg, _}} = hd(cs.errors)
    "#{Map.get(@labels, field, field)} #{msg}."
  end
end
