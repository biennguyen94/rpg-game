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
  - `"guild"` `%{"op" => ...}`: bang hội (xem `guild/3`); chat bang là `"chat"` với
    `"to" => "guild"`, server đẩy `"chat"` kèm `guild: true`; đổi bang thì server đẩy `"guild"`.
  - `"party"` `%{"op" => ...}`: tổ đội (`invite {uid}`, `accept`, `decline`, `leave`,
    `kick {uid}`, `info`); server đẩy `"party"` (tổ đội đổi), `"party_invite"` (có lời mời),
    `"shared"` (máu chung của trận đánh cùng). Chat tổ đội: `"chat"` với `"to" => "party"`.
  - `"arena"`: điểm đấu trường của mình, đối thủ gợi ý, bảng xếp hạng; thách đấu là lệnh
    `"cmd"` `%{"act" => "pvp_challenge", "uid" => ...}`.
  - `"market"` `%{"q"}`: hàng đang bán ở chợ và hàng mình đang rao; rao bán, mua, rút về là
    lệnh `"cmd"` `market_sell {id, count, price}`, `market_buy {listing}`,
    `market_cancel {listing}` (đứng cạnh Chủ Chợ).
  - `"inspect"` `%{"uid"}`: xem thông tin người chơi khác (chạm vào họ trên bản đồ).
  - `"visit"` `%{"uid"}`: xem nhà đã trang trí của người khác; `"home_like"` `%{"uid"}`: khen nhà
    (mỗi nhà một lần, chủ nhà nhận `"notice"`). Xem `HacLong.Homes`.
  - `"mail"`: danh sách thư; server đẩy `"mail"` `%{unread}` khi có thư mới. Mở thư (nhận quà)
    là lệnh `"cmd"` `%{"act" => "mail_claim", "id" => ...}`.
  - `"admin"` `%{"op" => ...}` (chỉ tài khoản quản trị): xem/xử lý báo cáo, tra cứu, cấm chat,
    khóa tài khoản, thông báo, tặng quà qua hộp thư, gọi trùm thế giới. Xem `admin/3`.
  """
  require Logger
  use HacLongWeb, :channel

  alias HacLong.{
    Accounts,
    Arena,
    Chat,
    Guilds,
    Homes,
    Leaderboard,
    Mailbox,
    Market,
    Moderation,
    Party,
    RateLimit,
    WorldBoss
  }

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
    gid = player && player[:guild] && player.guild.id
    if gid, do: Phoenix.PubSub.subscribe(HacLong.PubSub, Guilds.topic(gid))

    reply = %{
      username: socket.assigns.username,
      user_id: uid,
      admin: socket.assigns[:admin] == true,
      blocked: blocked,
      mail: Mailbox.unread(uid),
      party: party_view(uid),
      player: present(player)
    }

    {:ok, reply,
     socket
     |> assign(:map, nil)
     |> assign(:guild_id, gid)
     |> assign(:blocked, MapSet.new(blocked, & &1.id))}
  end

  @impl true
  def handle_in("cmd", %{} = cmd, socket) do
    {result, player} = Session.command(socket.assigns.user_id, cmd)
    socket = follow_map(socket, player)
    {:reply, {:ok, Map.put(result, :player, present(player))}, socket}
  end

  def handle_in("chat", %{"text" => text} = payload, socket) do
    uid = socket.assigns.user_id

    with :ok <- chat_limit(uid),
         :ok <- not_muted(uid),
         %{} = p <- Session.get(uid) || {:error, "Hãy tạo nhân vật trước."},
         from = %{
           uid: uid,
           name: p.name,
           map: p.pos.map,
           title: Achievements.title_name(p[:title]),
           tag: p[:guild] && p.guild.tag
         },
         {:ok, _msg} <- post_chat(payload["to"], p, from, text) do
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
        boards = boards |> Map.put(:guild, Guilds.top()) |> Map.put(:arena, Arena.top())
        {:reply, {:ok, Map.put(boards, :me, Leaderboard.level_rank(uid))}, socket}

      {:error, _} ->
        {:reply, {:error, %{msg: "Thao tác quá nhanh."}}, socket}
    end
  end

  def handle_in("guild", %{"op" => op} = p, socket) do
    uid = socket.assigns.user_id

    with :ok <- limit({:guild, uid}, 40, :timer.minutes(1)),
         {:ok, data} <- guild(op, p, uid) do
      {:reply, {:ok, data}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("party", %{"op" => op} = p, socket) do
    uid = socket.assigns.user_id

    target = p["uid"]

    result =
      case op do
        "info" -> :ok
        "invite" when is_integer(target) -> invite(uid, target)
        "accept" -> Party.accept(uid)
        "decline" -> Party.decline(uid)
        "leave" -> Party.leave(uid)
        "kick" when is_integer(target) -> Party.kick(uid, target)
        _ -> {:error, "Thao tác không hợp lệ."}
      end

    with :ok <- limit({:party, uid}, 40, :timer.minutes(1)),
         :ok <- result do
      {:reply, {:ok, %{party: party_view(uid)}}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("market", p, socket) do
    uid = socket.assigns.user_id

    with :ok <- limit({:market, uid}, 40, :timer.minutes(1)) do
      {:reply,
       {:ok,
        %{
          listings: Market.listings(p["q"] || "", uid),
          fee: Market.fee_pct(),
          max: Market.max_active()
        }}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("arena", _payload, socket) do
    uid = socket.assigns.user_id

    with :ok <- limit({:arena, uid}, 30, :timer.minutes(1)) do
      me = Map.put(Arena.stats(uid), :per_day, Arena.per_day())
      {:reply, {:ok, %{me: me, suggestions: Arena.suggestions(uid), top: Arena.top()}}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("inspect", %{"uid" => target}, socket) when is_integer(target) do
    uid = socket.assigns.user_id

    with :ok <- limit({:inspect, uid}, 60, :timer.minutes(1)),
         %{} = p <- online_or_saved(target) || {:error, "Không tìm thấy người chơi."} do
      name = fn id -> (it = HacLong.Game.Gear.item(p, id)) && it.name end
      guild = Guilds.brief(target)
      party = Party.of(uid)

      {:reply,
       {:ok,
        %{
          id: target,
          name: p.name,
          cls: p.cls,
          level: p.level,
          rebirths: Map.get(p, :rebirths, 0),
          look: Engine.look(p),
          title: Achievements.title_name(p[:title]),
          guild: guild && %{name: guild.name, tag: guild.tag},
          gear: %{
            weapon: name.(p.equip.weapon),
            armor: name.(p.equip.armor),
            shield: name.(p.equip.shield)
          },
          arena: Arena.stats(target),
          blocked: target in socket.assigns.blocked,
          party: party && target in party.members
        }}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("visit", %{"uid" => target}, socket) when is_integer(target) do
    uid = socket.assigns.user_id

    with :ok <- limit({:inspect, uid}, 60, :timer.minutes(1)),
         %{} = p <- online_or_saved(target) || {:error, "Không tìm thấy người chơi."} do
      {:reply, {:ok, Homes.view(p, target, uid)}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
    end
  end

  def handle_in("home_like", %{"uid" => target}, socket) when is_integer(target) do
    uid = socket.assigns.user_id

    with :ok <- limit({:home_like, uid}, 20, :timer.minutes(1)),
         %{} <- online_or_saved(target) || {:error, "Không tìm thấy người chơi."},
         %{name: name} <- Session.get(uid) || {:error, "Chưa có nhân vật."},
         {:ok, n} <- Homes.like(target, uid, name) do
      {:reply, {:ok, %{likes: n}}, socket}
    else
      {:error, msg} -> {:reply, {:error, %{msg: msg}}, socket}
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

  # người đang online thì lấy trạng thái mới nhất, không thì đọc database
  defp online_or_saved(uid) do
    case Registry.lookup(HacLong.Game.Registry, uid) do
      [_] -> Session.get(uid)
      [] -> HacLong.Game.Characters.load(uid)
    end
  end

  # ---------- Tổ đội ----------

  # chỉ mời được người đang online
  defp invite(uid, target) do
    case Registry.lookup(HacLong.Game.Registry, target) do
      [_] -> Party.invite(uid, target)
      [] -> {:error, "Người này không online."}
    end
  end

  defp party_view(uid) do
    case Party.of(uid) do
      nil ->
        nil

      party ->
        members =
          for m <- party.members, p = Session.get(m) do
            %{
              id: m,
              name: p.name,
              cls: p.cls,
              level: p.level,
              hp: p.hp,
              maxHp: Engine.derived(p).maxHp,
              map: p.pos.map
            }
          end

        %{id: party.id, leader: party.leader, members: members, max: Party.max()}
    end
  end

  defp party_chat(from, text) do
    case Party.of(from.uid) do
      nil ->
        {:error, "Bạn chưa ở trong tổ đội nào."}

      party ->
        text = text |> String.replace(~r/\s+/u, " ") |> String.trim() |> String.slice(0, 120)

        if text == "" do
          {:error, "Tin nhắn trống."}
        else
          msg =
            Map.merge(from, %{
              id: nil,
              text: text,
              party: true,
              at: System.system_time(:millisecond)
            })

          for m <- party.members,
              do: Phoenix.PubSub.broadcast(HacLong.PubSub, Session.topic(m), {:party_chat, msg})

          {:ok, msg}
        end
    end
  end

  # Kênh chat: thế giới (mặc định), bang hội, tổ đội.
  defp post_chat("guild", p, from, text), do: guild_chat(p, from, text)
  defp post_chat("party", _p, from, text), do: party_chat(from, text)
  defp post_chat(_, _p, from, text), do: Chat.post(from, text)

  # ---------- Bang hội ----------

  defp guild_chat(%{guild: %{id: gid}}, from, text) do
    text =
      text
      |> String.replace(~r/[\p{Cc}\p{Cf}]/u, " ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()
      |> String.slice(0, 120)

    if text == "" do
      {:error, "Tin nhắn trống."}
    else
      msg =
        Map.merge(from, %{id: nil, text: text, guild: true, at: System.system_time(:millisecond)})

      Phoenix.PubSub.broadcast(HacLong.PubSub, Guilds.topic(gid), {:guild_chat, msg})
      {:ok, msg}
    end
  end

  defp guild_chat(_p, _from, _text), do: {:error, "Bạn chưa vào bang nào."}

  # Trả về {:ok, dữ_liệu} hoặc {:error, lý_do}. Sau mỗi thay đổi trả lại thông tin bang.
  defp guild("list", p, uid),
    do: {:ok, %{guilds: Guilds.list(p["q"] || ""), requested: Guilds.my_requests(uid)}}

  defp guild("info", _p, uid) do
    case Guilds.brief(uid) do
      nil -> {:ok, %{guild: nil}}
      b -> {:ok, %{guild: Guilds.info(b.id, uid)}}
    end
  end

  defp guild(op, p, uid) do
    target = p["uid"]
    gid = p["id"]

    result =
      case op do
        "join" -> Guilds.join(uid, gid)
        "cancel" -> Guilds.cancel_request(uid, gid)
        "accept" -> Guilds.accept(uid, target)
        "reject" -> Guilds.reject(uid, target)
        "kick" -> Guilds.kick(uid, target)
        "promote" -> Guilds.set_role(uid, target, "officer")
        "demote" -> Guilds.set_role(uid, target, "member")
        "transfer" -> Guilds.transfer(uid, target)
        "leave" -> Guilds.leave(uid)
        "disband" -> Guilds.disband(uid)
        "settings" -> Guilds.settings(uid, p)
        _ -> {:error, "Thao tác không hợp lệ."}
      end

    with {:ok, msg} <- result do
      {:ok, info} = guild("info", p, uid)
      {:ok, Map.put(info, :msg, msg)}
    end
  end

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

  # Bang của mình vừa đổi (vào, rời, bị đuổi, giải tán): đổi kênh chat bang.
  def handle_info({:guild, brief}, socket) do
    old = socket.assigns[:guild_id]
    new = brief && brief.id

    if old != new do
      if old, do: Phoenix.PubSub.unsubscribe(HacLong.PubSub, Guilds.topic(old))
      if new, do: Phoenix.PubSub.subscribe(HacLong.PubSub, Guilds.topic(new))
    end

    push(socket, "guild", %{guild: brief})
    {:noreply, assign(socket, :guild_id, new)}
  end

  def handle_info({:guild_chat, msg}, socket) do
    unless msg.uid in socket.assigns.blocked, do: push(socket, "chat", msg)
    {:noreply, socket}
  end

  def handle_info({:party, _pid}, socket) do
    push(socket, "party", %{party: party_view(socket.assigns.user_id)})
    {:noreply, socket}
  end

  def handle_info({:party_invite, from}, socket) do
    name = (p = Session.get(from)) && p.name
    push(socket, "party_invite", %{from: from, name: name})
    {:noreply, socket}
  end

  def handle_info({:party_chat, msg}, socket) do
    unless msg.uid in socket.assigns.blocked, do: push(socket, "chat", msg)
    {:noreply, socket}
  end

  def handle_info({:shared_hp, key, hp, n}, socket) do
    push(socket, "shared", %{key: key, hp: hp, n: n})
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
