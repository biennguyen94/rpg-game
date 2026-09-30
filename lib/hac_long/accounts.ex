defmodule HacLong.Accounts do
  @moduledoc "Tài khoản người chơi: đăng ký, đăng nhập, token đăng nhập, đổi mật khẩu."

  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.Accounts.{User, UserToken}

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

  # ---------- Token đăng nhập ----------
  # Token là chuỗi ngẫu nhiên 32 byte; database chỉ giữ mã băm của nó. Mỗi lần đăng nhập
  # một token mới (mỗi thiết bị một token), xóa token là đăng xuất thiết bị đó.

  @doc "Tạo token đăng nhập mới cho `user`."
  def sign_token(%User{id: id}) do
    token = :crypto.strong_rand_bytes(32)
    Repo.insert!(%UserToken{user_id: id, token_hash: hash(token)})
    Base.url_encode64(token, padding: false)
  end

  def verify_token(token) when is_binary(token) do
    cutoff = DateTime.add(DateTime.utc_now(), -@token_max_age, :second)

    with {:ok, raw} <- Base.url_decode64(token, padding: false),
         %User{} = user <-
           Repo.one(
             from t in UserToken,
               join: u in assoc(t, :user),
               where: t.token_hash == ^hash(raw) and t.inserted_at > ^cutoff,
               select: u
           ) do
      {:ok, user}
    else
      _ -> {:error, :invalid}
    end
  end

  def verify_token(_), do: {:error, :invalid}

  @doc "Đăng xuất thiết bị đang dùng `token`."
  def revoke_token(token) when is_binary(token) do
    with {:ok, raw} <- Base.url_decode64(token, padding: false) do
      Repo.delete_all(from t in UserToken, where: t.token_hash == ^hash(raw))
    end

    :ok
  end

  def revoke_token(_), do: :ok

  @doc "Đăng xuất mọi thiết bị của `user`."
  def revoke_all(%User{id: id}) do
    Repo.delete_all(from t in UserToken, where: t.user_id == ^id)
    :ok
  end

  @doc "Đổi mật khẩu: kiểm tra mật khẩu cũ, rồi thu hồi mọi token cũ."
  def change_password(%User{} = user, current, new) do
    with {:ok, _} <- authenticate(user.username, current) do
      cs = User.password_changeset(user, %{"password" => new})

      case Repo.update(cs) do
        {:ok, user} ->
          revoke_all(user)
          {:ok, user}

        error ->
          error
      end
    end
  end

  defp hash(raw), do: :crypto.hash(:sha256, raw)
end
