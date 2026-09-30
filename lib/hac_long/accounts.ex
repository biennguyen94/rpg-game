defmodule HacLong.Accounts do
  @moduledoc "Tài khoản người chơi: đăng ký, đăng nhập và token cho WebSocket."

  alias HacLong.Repo
  alias HacLong.Accounts.User

  @token_salt "user socket"
  # token đăng nhập có hạn 30 ngày
  @token_max_age 30 * 24 * 3600

  def get_user(id), do: Repo.get(User, id)

  def register(attrs) do
    %User{} |> User.registration_changeset(attrs) |> Repo.insert()
  end

  def authenticate(username, password) when is_binary(username) and is_binary(password) do
    user = Repo.get_by(User, username: username |> String.trim() |> String.downcase())

    cond do
      user && Pbkdf2.verify_pass(password, user.password_hash) ->
        {:ok, user}

      user ->
        {:error, :invalid}

      true ->
        # chạy hash giả để thời gian phản hồi không lộ tên đăng nhập có tồn tại hay không
        Pbkdf2.no_user_verify()
        {:error, :invalid}
    end
  end

  def authenticate(_, _), do: {:error, :invalid}

  def sign_token(%User{id: id}), do: Phoenix.Token.sign(HacLongWeb.Endpoint, @token_salt, id)

  def verify_token(token) when is_binary(token) do
    with {:ok, id} <-
           Phoenix.Token.verify(HacLongWeb.Endpoint, @token_salt, token, max_age: @token_max_age),
         %User{} = user <- get_user(id) do
      {:ok, user}
    else
      _ -> {:error, :invalid}
    end
  end

  def verify_token(_), do: {:error, :invalid}
end
