defmodule HacLong.Friends do
  @moduledoc """
  Bạn bè và nhắn tin riêng.

  - Kết bạn (`request/2`): gửi lời mời; người kia nhận (`accept/2`) thì thành bạn của nhau
    (mỗi chiều một dòng trong bảng `friends`). Hai người cùng mời nhau thì thành bạn luôn.
    Người đã chặn mình thì không mời được. Tối đa `@max` bạn.
  - Tin nhắn riêng (`send_message/3`) chỉ gửi cho bạn bè; lưu trong `private_messages`, người
    nhận đang online thì nhận ngay (`{:dm, tin}` trên kênh người chơi), không thì thấy số tin
    chưa đọc khi vào game. Mở cuộc trò chuyện (`history/2`) là đánh dấu đã đọc.
  - Thay đổi danh sách bạn thì cả hai nhận `{:friends, thông_báo | nil}`.
  """
  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.Accounts.User
  alias HacLong.Game.{Character, Names, Session}

  @max 50
  @max_text 200
  @history 60

  def max, do: @max

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp online?(uid), do: Registry.lookup(HacLong.Game.Registry, uid) != []

  defp notify(uid, text),
    do: Phoenix.PubSub.broadcast(HacLong.PubSub, Session.topic(uid), {:friends, text})

  defp name_of(uid) do
    Repo.one(
      from u in User,
        left_join: c in Character,
        on: c.user_id == u.id,
        where: u.id == ^uid,
        select: coalesce(c.name, u.username)
    )
  end

  defp row(a, b), do: from(f in "friends", where: f.user_id == ^a and f.friend_id == ^b)

  def friends?(a, b), do: Repo.exists?(row(a, b) |> where([f], f.accepted))

  defp blocked_by?(target, uid) do
    Repo.exists?(from b in "user_blocks", where: b.user_id == ^target and b.blocked_id == ^uid)
  end

  defp count(uid),
    do: Repo.aggregate(from(f in "friends", where: f.user_id == ^uid and f.accepted), :count)

  # ---------- Danh sách ----------

  @doc """
  Bạn bè, lời mời đến và lời mời đã gửi của `uid`:
  `%{friends: [%{id, name, level, cls, online, unread}], incoming: [..], outgoing: [..], unread}`.
  """
  def list(uid) do
    people = fn q ->
      from(f in q,
        join: u in User,
        on: u.id == f.other,
        left_join: c in Character,
        on: c.user_id == u.id,
        select: %{id: u.id, name: coalesce(c.name, u.username), level: c.level, cls: c.cls}
      )
      |> Repo.all()
    end

    mine =
      from(f in "friends",
        where: f.user_id == ^uid,
        select: %{other: f.friend_id, accepted: f.accepted}
      )

    theirs =
      from(f in "friends",
        where: f.friend_id == ^uid and not f.accepted,
        select: %{other: f.user_id}
      )

    friends_q = from(f in subquery(mine), where: f.accepted)
    outgoing_q = from(f in subquery(mine), where: not f.accepted)
    incoming_q = subquery(theirs)

    unread = unread_by_sender(uid)

    friends =
      people.(friends_q)
      |> Enum.map(&Map.merge(&1, %{online: online?(&1.id), unread: Map.get(unread, &1.id, 0)}))
      |> Enum.sort_by(&{!&1.online, -&1.unread, &1.name})

    %{
      friends: friends,
      incoming: people.(incoming_q),
      outgoing: people.(outgoing_q),
      unread: friends |> Enum.map(& &1.unread) |> Enum.sum(),
      max: @max
    }
  end

  defp unread_by_sender(uid) do
    from(m in "private_messages",
      where: m.to_id == ^uid and is_nil(m.read_at),
      group_by: m.from_id,
      select: {m.from_id, count()}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Tổng số tin riêng chưa đọc (chỉ tính tin từ bạn bè)."
  def unread(uid) do
    Repo.one(
      from m in "private_messages",
        join: f in "friends",
        on: f.user_id == m.to_id and f.friend_id == m.from_id and f.accepted,
        where: m.to_id == ^uid and is_nil(m.read_at),
        select: count()
    ) || 0
  end

  # ---------- Kết bạn ----------

  @doc "Tìm người chơi theo tên nhân vật rồi mời kết bạn."
  def request_by_name(uid, name) when is_binary(name) do
    key = Names.key(name)

    case Repo.one(from c in Character, where: c.name_key == ^key, select: c.user_id) do
      nil -> {:error, "Không có nhân vật tên này."}
      target -> request(uid, target)
    end
  end

  def request_by_name(_uid, _), do: {:error, "Tên không hợp lệ."}

  def request(uid, target) do
    cond do
      uid == target ->
        {:error, "Không tự kết bạn với mình được."}

      not Repo.exists?(from c in Character, where: c.user_id == ^target) ->
        {:error, "Không tìm thấy người chơi."}

      friends?(uid, target) ->
        {:error, "Hai người đã là bạn."}

      Repo.exists?(row(uid, target)) ->
        {:error, "Đã gửi lời mời rồi, chờ người kia nhận."}

      count(uid) >= @max ->
        {:error, "Bạn đã có đủ #{@max} bạn."}

      blocked_by?(target, uid) ->
        {:error, "Không gửi được lời mời."}

      # người kia đã mời mình trước: thành bạn luôn
      Repo.exists?(row(target, uid)) ->
        accept(uid, target)

      true ->
        Repo.insert_all("friends", [%{user_id: uid, friend_id: target, inserted_at: now()}])
        notify(target, "👋 #{name_of(uid)} muốn kết bạn với bạn.")
        notify(uid, nil)
        {:ok, "Đã gửi lời mời kết bạn."}
    end
  end

  @doc "`uid` nhận lời mời kết bạn của `from`."
  def accept(uid, from) do
    cond do
      not Repo.exists?(row(from, uid) |> where([f], not f.accepted)) ->
        {:error, "Lời mời không còn nữa."}

      count(uid) >= @max ->
        {:error, "Bạn đã có đủ #{@max} bạn."}

      true ->
        Repo.transaction(fn ->
          Repo.update_all(row(from, uid), set: [accepted: true])

          Repo.insert_all(
            "friends",
            [%{user_id: uid, friend_id: from, accepted: true, inserted_at: now()}],
            on_conflict: {:replace, [:accepted]},
            conflict_target: [:user_id, :friend_id]
          )
        end)

        notify(from, "🤝 #{name_of(uid)} đã nhận lời kết bạn.")
        notify(uid, nil)
        {:ok, "Đã kết bạn với #{name_of(from)}."}
    end
  end

  @doc "`uid` từ chối lời mời của `from` (hoặc rút lời mời mình đã gửi cho `from`)."
  def decline(uid, from) do
    Repo.delete_all(row(from, uid) |> where([f], not f.accepted))
    Repo.delete_all(row(uid, from) |> where([f], not f.accepted))
    notify(uid, nil)
    notify(from, nil)
    {:ok, "Đã bỏ lời mời."}
  end

  def remove(uid, other) do
    Repo.delete_all(row(uid, other))
    Repo.delete_all(row(other, uid))
    notify(uid, nil)
    notify(other, nil)
    {:ok, "Đã xóa khỏi danh sách bạn."}
  end

  # ---------- Tin nhắn riêng ----------

  defp clean(text) do
    text
    |> String.replace(~r/[\p{Cc}\p{Cf}]/u, " ")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, @max_text)
  end

  @doc "Gửi tin riêng cho bạn `to`. Trả về `{:ok, tin}` hoặc `{:error, lý_do}`."
  def send_message(uid, to, text) when is_binary(text) do
    text = clean(text)

    cond do
      text == "" ->
        {:error, "Tin nhắn trống."}

      not friends?(uid, to) ->
        {:error, "Chỉ nhắn riêng được cho bạn bè."}

      true ->
        at = now()

        {1, [%{id: id}]} =
          Repo.insert_all(
            "private_messages",
            [%{from_id: uid, to_id: to, text: text, inserted_at: at}],
            returning: [:id]
          )

        msg = %{id: id, from: uid, to: to, name: name_of(uid), text: text, at: at, read: false}

        for u <- [to, uid],
            do: Phoenix.PubSub.broadcast(HacLong.PubSub, Session.topic(u), {:dm, msg})

        {:ok, msg}
    end
  end

  def send_message(_uid, _to, _text), do: {:error, "Tin nhắn không hợp lệ."}

  @doc "Cuộc trò chuyện giữa `uid` và `other` (mới nhất ở cuối); đánh dấu tin đến là đã đọc."
  def history(uid, other) do
    msgs =
      from(m in "private_messages",
        where:
          (m.from_id == ^uid and m.to_id == ^other) or (m.from_id == ^other and m.to_id == ^uid),
        order_by: [desc: m.id],
        limit: @history,
        select: %{
          id: m.id,
          from: m.from_id,
          to: m.to_id,
          text: m.text,
          at: m.inserted_at,
          read: not is_nil(m.read_at)
        }
      )
      |> Repo.all()
      |> Enum.reverse()

    from(m in "private_messages",
      where: m.to_id == ^uid and m.from_id == ^other and is_nil(m.read_at)
    )
    |> Repo.update_all(set: [read_at: now()])

    %{with: %{id: other, name: name_of(other), online: online?(other)}, messages: msgs}
  end
end
