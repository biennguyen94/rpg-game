defmodule HacLong.Moderation do
  @moduledoc """
  Giữ trật tự: người chơi chặn và báo cáo nhau; quản trị viên xử lý báo cáo, cấm chat,
  khóa tài khoản.

  - Chặn: chỉ ẩn chat của người bị chặn với người chặn (lọc ở `HacLongWeb.GameChannel`).
  - Báo cáo: chọn một tin nhắn còn trong lịch sử chat; nội dung lấy từ server nên không
    giả được. Mỗi người báo cáo một tin một lần.
  - Cấm chat / khóa tài khoản có thời hạn (`nil` phút/giờ là vĩnh viễn). Khóa thì mọi token
    bị thu hồi; kênh game bị ngắt ở `HacLongWeb.GameChannel`.
  - Người chơi được tra theo tên nhân vật (không phân biệt hoa thường) hoặc tên đăng nhập.
  """
  import Ecto.Query

  alias HacLong.{Accounts, Chat, Repo}
  alias HacLong.Accounts.User
  alias HacLong.Game.{Character, Names}

  @forever ~U[9999-12-31 00:00:00Z]

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  # ---------- Chặn ----------

  def block(user_id, blocked_id) when user_id != blocked_id do
    Repo.insert_all(
      "user_blocks",
      [%{user_id: user_id, blocked_id: blocked_id, inserted_at: now()}],
      on_conflict: :nothing
    )

    :ok
  end

  def block(_, _), do: {:error, "Không tự chặn mình được."}

  def unblock(user_id, blocked_id) do
    Repo.delete_all(
      from b in "user_blocks", where: b.user_id == ^user_id and b.blocked_id == ^blocked_id
    )

    :ok
  end

  @doc "Những người `user_id` đã chặn: `[%{id, name}]`."
  def blocked(user_id) do
    Repo.all(
      from b in "user_blocks",
        join: u in User,
        on: u.id == b.blocked_id,
        left_join: c in Character,
        on: c.user_id == u.id,
        where: b.user_id == ^user_id,
        select: %{id: u.id, name: coalesce(c.name, u.username)}
    )
  end

  # ---------- Báo cáo ----------

  def report(reporter_id, msg_id) do
    case Chat.find(msg_id) do
      nil ->
        {:error, "Tin nhắn đã quá cũ để báo cáo."}

      %{uid: 0} ->
        {:error, "Không báo cáo thông báo hệ thống."}

      %{uid: ^reporter_id} ->
        {:error, "Không tự báo cáo mình được."}

      msg ->
        Repo.insert_all(
          "chat_reports",
          [%{reporter_id: reporter_id, target_id: msg.uid, text: msg.text, inserted_at: now()}],
          on_conflict: :nothing
        )

        :ok
    end
  end

  @doc "Báo cáo chưa xử lý, cũ trước mới sau."
  def open_reports do
    Repo.all(
      from r in "chat_reports",
        join: t in User,
        on: t.id == r.target_id,
        left_join: tc in Character,
        on: tc.user_id == t.id,
        join: rp in User,
        on: rp.id == r.reporter_id,
        left_join: rc in Character,
        on: rc.user_id == rp.id,
        where: is_nil(r.resolved_at),
        order_by: [asc: r.id],
        select: %{
          id: r.id,
          text: r.text,
          target_id: t.id,
          target: coalesce(tc.name, t.username),
          reporter: coalesce(rc.name, rp.username),
          at: r.inserted_at
        }
    )
  end

  @doc "Đánh dấu báo cáo đã xử lý với `action` (\"dismiss\", \"mute\", \"ban\")."
  def resolve(report_id, admin_id, action) do
    {n, _} =
      Repo.update_all(
        from(r in "chat_reports", where: r.id == ^report_id and is_nil(r.resolved_at)),
        set: [resolved_at: now(), resolved_by_id: admin_id, action: action]
      )

    if n == 1, do: :ok, else: {:error, "Báo cáo không còn."}
  end

  # ---------- Cấm chat, khóa tài khoản ----------

  defp until(nil), do: @forever
  defp until(minutes), do: DateTime.add(now(), minutes * 60, :second)

  def mute(user_id, minutes), do: set(user_id, muted_until: until(minutes))
  def unmute(user_id), do: set(user_id, muted_until: nil)

  def ban(user_id, minutes, reason) do
    with :ok <- set(user_id, banned_until: until(minutes), ban_reason: reason) do
      Accounts.revoke_all(%User{id: user_id})
    end
  end

  def unban(user_id), do: set(user_id, banned_until: nil, ban_reason: nil)

  defp set(user_id, fields) do
    {n, _} = Repo.update_all(from(u in User, where: u.id == ^user_id), set: fields)
    if n == 1, do: :ok, else: {:error, "Không tìm thấy người chơi."}
  end

  # ---------- Tra cứu ----------

  @doc "Tìm tài khoản theo tên nhân vật hoặc tên đăng nhập."
  def find_user(name) when is_binary(name) do
    key = Names.key(name)

    Repo.one(
      from u in User,
        left_join: c in Character,
        on: c.user_id == u.id,
        where: c.name_key == ^key or u.username == ^String.downcase(String.trim(name)),
        limit: 1
    )
  end

  def find_user(_), do: nil

  @doc "Thông tin cho quản trị viên."
  def info(%User{} = u) do
    c =
      Repo.one(
        from c in Character,
          where: c.user_id == ^u.id,
          select: map(c, [:name, :level, :gold, :kills])
      )

    %{
      id: u.id,
      username: u.username,
      admin: u.admin,
      character: c,
      banned_until: Accounts.banned?(u) && u.banned_until,
      ban_reason: u.ban_reason,
      muted_until: Accounts.muted?(u) && u.muted_until,
      reports: Repo.one(from r in "chat_reports", where: r.target_id == ^u.id, select: count())
    }
  end

  @doc "Cấp/thu quyền quản trị."
  def set_admin(username, admin?) do
    case Repo.get_by(User, username: String.downcase(username)) do
      nil -> {:error, "Không có tài khoản #{username}."}
      u -> u |> Ecto.Changeset.change(admin: admin?) |> Repo.update()
    end
  end
end
