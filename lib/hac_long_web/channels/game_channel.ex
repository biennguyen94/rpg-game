defmodule HacLongWeb.GameChannel do
  @moduledoc """
  Kênh chơi game.

  - Client gửi `"cmd"` với payload `%{"act" => ..., ...}` (xem `HacLong.Game.Commands`;
    bước đi là `%{"act" => "move", "dir" => "up" | "down" | "left" | "right"}`) và nhận lại
    kết quả kèm trạng thái nhân vật mới.
  - Khi nhân vật đổi từ tab khác, server đẩy `"player"`.
  - Server đẩy `"map"` với quái và người chơi trên bản đồ nhân vật đang đứng, mỗi khi
    bản đồ đó thay đổi. Kênh tự chuyển theo dõi khi nhân vật sang bản đồ khác.
  - Chat thế giới: client gửi `"chat"` với `%{"text" => ...}`; server đẩy `"chat"` (một tin)
    cho mọi người và `"chat_history"` (các tin gần nhất) lúc mới vào.
  - `"leaderboard"`: trả về các bảng xếp hạng và hạng của mình.
  - Server đẩy `"world_boss"` (trạng thái trùm thế giới: còn sống, máu, top sát thương) mỗi
    khi thay đổi, và `"notice"` (`%{msg}`) khi có thông báo riêng (vd. nhận thưởng trùm).
  - `"block"` / `"unblock"` `%{"uid"}`: ẩn/hiện chat của một người; `"report"` `%{"id"}`: báo
    cáo một tin nhắn chat.
  - `"mail"`: danh sách thư; server đẩy `"mail"` `%{unread}` khi có thư mới. Mở thư (nhận quà)
    là lệnh `"cmd"` `%{"act" => "mail_claim", "id" => ...}`.
  - `"admin"` `%{"op" => ...}` (chỉ tài khoản quản trị): xem/xử lý báo cáo, tra cứu, cấm chat,
    khóa tài khoản, thông báo, tặng quà qua hộp thư, gọi trùm thế giới. Xem `admin/3`.
  """
  require Logger
  use HacLongWeb, :channel

  alias HacLong.{Accounts, Chat, Leaderboard, Mailbox, Moderation, RateLimit, WorldBoss}
  alias HacLong.Game.{Achievements, Chests, Daily, Data, Engine, Quests, Session, Tutorial}
  alias HacLong.World.{Maps, MapServer}

  @impl true
  def join("game", _params, socket) do
    uid = socket.assigns.user_id
    Phoenix.PubSub.subscribe(HacLong.PubSub, Session.topic(uid))
    Phoenix.PubSub.subscribe(HacLong.PubSub, Chat.topic())
    Phoenix.PubSub.subscribe(HacLong.PubSub, WorldBoss.topic())
    player = Session.attach(uid, self())
    send(self(), :push_map)
    blocked = Moderation.blocked(uid)

    reply = %{
      username: socket.assigns.username,
      user_id: uid,
      admin: socket.assigns[:admin] == true,
      blocked: blocked,
      mail: Mailbox.unread(uid),
      player: present(player)
    }

    {:ok, reply, socket |> assign(:map, nil) |> assign(:blocked, MapSet.new(blocked, & &1.id))}
  end

  @impl true
  def handle_in("cmd", %{} = cmd, socket) do
    {result, player} = Session.command(socket.assigns.user_id, cmd)
    socket = follow_map(socket, player)
    {:reply, {:ok, Map.put(result, :player, present(player))}, socket}
  end

  def handle_in("chat", %{"text" => text}, socket) do
    uid = socket.assigns.user_id

    with :ok <- chat_limit(uid),
         :ok <- not_muted(uid),
         %{} = p <- Session.get(uid) || {:error, "Hãy tạo nhân vật trước."},
         from = %{
           uid: uid,
           name: p.name,
           map: p.pos.map,
           title: Achievements.title_name(p[:title])
         },
         {:ok, _msg} <- Chat.post(from, text) do
      {:reply, :ok, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("leaderboard", _payload, socket) do
    uid = socket.assigns.user_id

    case RateLimit.hit({:leaderboard, uid}, 20, :timer.minutes(1)) do
      :ok ->
        boards = Map.new(Leaderboard.kinds(), &{&1, Leaderboard.top(&1)})
        {:reply, {:ok, Map.put(boards, :me, Leaderboard.level_rank(uid))}, socket}

      {:error, _} ->
        {:reply, {:error, %{msg: "Thao tác quá nhanh."}}, socket}
    end
  end

  def handle_in("mail", _payload, socket) do
    uid = socket.assigns.user_id

    with :ok <- limit({:mail, uid}, 30, :timer.minutes(1)) do
      {:reply, {:ok, %{mails: Mailbox.list(uid), unread: Mailbox.unread(uid)}}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("block", %{"uid" => id}, socket) when is_integer(id) do
    uid = socket.assigns.user_id

    case Moderation.block(uid, id) do
      :ok ->
        {:reply, {:ok, %{blocked: Moderation.blocked(uid)}},
         assign(socket, :blocked, MapSet.put(socket.assigns.blocked, id))}

      {:error, msg} ->
        {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("unblock", %{"uid" => id}, socket) when is_integer(id) do
    uid = socket.assigns.user_id
    Moderation.unblock(uid, id)

    {:reply, {:ok, %{blocked: Moderation.blocked(uid)}},
     assign(socket, :blocked, MapSet.delete(socket.assigns.blocked, id))}
  end

  def handle_in("report", %{"id" => id}, socket) when is_integer(id) do
    uid = socket.assigns.user_id

    with :ok <- limit({:report, uid}, 10, :timer.minutes(10)),
         :ok <- Moderation.report(uid, id) do
      {:reply, :ok, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("admin", %{"op" => op} = p, %{assigns: %{admin: true}} = socket) do
    Logger.info("quản trị #{socket.assigns.username}: #{op} #{inspect(Map.delete(p, "op"))}")

    case admin(op, p, socket) do
      {:ok, data} -> {:reply, {:ok, data}, socket}
      :ok -> {:reply, {:ok, %{}}, socket}
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("admin", _p, socket), do: {:reply, {:error, %{msg: "Không có quyền."}}, socket}

  def handle_in(_event, _payload, socket), do: {:reply, {:error, %{msg: "Sai cú pháp."}}, socket}

  # ---------- Quản trị ----------

  defp admin("reports", _p, _s), do: {:ok, %{reports: Moderation.open_reports()}}

  defp admin("lookup", %{"name" => name}, _s) do
    case Moderation.find_user(name) do
      nil -> {:error, "Không tìm thấy \"#{name}\"."}
      u -> {:ok, %{user: Moderation.info(u)}}
    end
  end

  defp admin("resolve", %{"id" => id, "action" => action} = p, s)
       when action in ~w(dismiss mute ban) do
    report = Enum.find(Moderation.open_reports(), &(&1.id == id))

    cond do
      report == nil ->
        {:error, "Báo cáo không còn."}

      action == "dismiss" ->
        Moderation.resolve(id, s.assigns.user_id, action)

      true ->
        with :ok <- punish(action, report.target_id, p),
             do: Moderation.resolve(id, s.assigns.user_id, action)
    end
  end

  defp admin(op, %{"uid" => id} = p, _s)
       when op in ~w(mute unmute ban unban) and is_integer(id) do
    case op do
      "unmute" -> Moderation.unmute(id)
      "unban" -> Moderation.unban(id)
      _ -> punish(op, id, p)
    end
  end

  defp admin("announce", %{"text" => text}, _s) when is_binary(text) and text != "" do
    Chat.system("📢 " <> String.slice(String.trim(text), 0, 200))
    :ok
  end

  # Tặng quà qua hộp thư: cho một người (`uid`) hoặc mọi người (`all: true`).
  defp admin("gift", p, _s) do
    mail = %{
      subject: p["subject"] || "Quà từ Ban Quản Trị",
      body: p["body"] || "",
      gold: p["gold"] || 0,
      xp: p["xp"] || 0,
      items: p["items"] || %{}
    }

    case p do
      %{"all" => true} ->
        with {:ok, n} <- Mailbox.send_all(mail), do: {:ok, %{sent: n}}

      %{"uid" => id} when is_integer(id) ->
        with :ok <- Mailbox.send(id, mail), do: {:ok, %{sent: 1}}

      _ ->
        {:error, "Chọn người nhận."}
    end
  end

  defp admin("world_boss", _p, _s), do: {:ok, %{status: WorldBoss.spawn_now()}}

  defp admin(_op, _p, _s), do: {:error, "Lệnh quản trị không hợp lệ."}

  # `minutes`: số phút, hoặc nil/0 là vĩnh viễn
  defp punish("mute", id, p), do: Moderation.mute(id, minutes(p))

  defp punish("ban", id, p) do
    with :ok <- Moderation.ban(id, minutes(p), p["reason"]) do
      # đăng xuất ngay mọi thiết bị đang mở game
      HacLongWeb.Endpoint.broadcast("user_socket:#{id}", "disconnect", %{})
      :ok
    end
  end

  defp minutes(%{"minutes" => m}) when is_integer(m) and m > 0, do: m
  defp minutes(_), do: nil

  defp not_muted(uid) do
    user = Accounts.get_user(uid)

    if Accounts.muted?(user) do
      until =
        if user.muted_until.year >= 9999,
          do: "vĩnh viễn",
          else:
            "đến " <> Calendar.strftime(DateTime.add(user.muted_until, 7 * 3600), "%H:%M %d/%m")

      {:error, "Bạn đang bị cấm chat #{until}."}
    else
      :ok
    end
  end

  defp limit(key, n, window) do
    case RateLimit.hit(key, n, window) do
      :ok -> :ok
      {:error, _} -> {:error, "Thao tác quá nhanh."}
    end
  end

  # 5 tin mỗi 10 giây, chống spam.
  defp chat_limit(uid) do
    case RateLimit.hit({:chat, uid}, 5, 10_000) do
      :ok -> :ok
      {:error, secs} -> {:error, "Chat chậm lại chút, đợi #{secs} giây."}
    end
  end

  @impl true
  def handle_info(:push_map, socket) do
    push(socket, "chat_history", %{
      messages: Enum.reject(Chat.history(), &(&1.uid in socket.assigns.blocked))
    })

    push(socket, "world_boss", WorldBoss.status())
    {:noreply, follow_map(socket, Session.get(socket.assigns.user_id))}
  end

  def handle_info({:world_boss, status}, socket) do
    push(socket, "world_boss", status)
    {:noreply, socket}
  end

  def handle_info({:mail, unread}, socket) do
    push(socket, "mail", %{unread: unread})
    {:noreply, socket}
  end

  def handle_info({:notice, msg}, socket) do
    push(socket, "notice", %{msg: msg})
    {:noreply, socket}
  end

  def handle_info({:chat, msg}, socket) do
    unless msg.uid in socket.assigns.blocked, do: push(socket, "chat", msg)
    {:noreply, socket}
  end

  def handle_info({:player, player, origin}, socket) do
    if origin != self(), do: push(socket, "player", %{player: present(player)})
    {:noreply, follow_map(socket, player)}
  end

  def handle_info({:map_state, id, snap}, socket) do
    if id == socket.assigns.map, do: push(socket, "map", snap)
    {:noreply, socket}
  end

  # Nhân vật sang bản đồ khác: đổi kênh PubSub đang nghe và gửi ngay trạng thái bản đồ mới.
  defp follow_map(socket, player) do
    map_id = player && player.pos.map

    if map_id == socket.assigns.map do
      socket
    else
      if old = socket.assigns.map, do: unsubscribe(old)

      if map_id do
        if Maps.get(map_id).private do
          push(socket, "map", %{
            map: map_id,
            phase: HacLong.World.Clock.phase(),
            monsters: [],
            nodes: [],
            players: []
          })
        else
          Phoenix.PubSub.subscribe(HacLong.PubSub, MapServer.topic(map_id))
          push(socket, "map", MapServer.snapshot(map_id))
        end
      end

      assign(socket, :map, map_id)
    end
  end

  defp unsubscribe(map_id) do
    unless Maps.get(map_id).private,
      do: Phoenix.PubSub.unsubscribe(HacLong.PubSub, MapServer.topic(map_id))
  end

  # Kèm các chỉ số tính sẵn (máu tối đa, tấn công, giá nghỉ trọ...) cho client hiển thị.
  defp present(nil), do: nil

  defp present(player) do
    # có việc mới hoặc việc đã xong chờ trả: hiện dấu "!" trên đầu Trưởng Làng
    ready =
      Quests.available(player) != [] or
        Enum.any?(Map.keys(player.quests.active), &Quests.complete?(player, Data.quest(&1)))

    view =
      player
      |> Engine.view()
      |> Map.merge(%{
        questReady: ready,
        dailyReady: Daily.ready?(player),
        dailyLeft: Daily.seconds_left(),
        tutorial: Tutorial.view(player),
        achievements: Achievements.view(player),
        chestReady: player[:chest_day] != Daily.today(),
        chests:
          Enum.map(Chests.tiers(), fn t ->
            %{
              id: t.id,
              name: t.name,
              price: Chests.price(t, player.level),
              odds: Map.new(t.weights, fn {r, w} -> {r, w} end)
            }
          end)
      })

    Map.put(player, :view, view)
  end
end
