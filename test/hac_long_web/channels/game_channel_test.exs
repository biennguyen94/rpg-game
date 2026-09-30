defmodule HacLongWeb.GameChannelTest do
  use HacLongWeb.ChannelCase

  alias HacLong.Accounts
  alias HacLong.Game.{Characters, Commands, Session}
  alias HacLong.World.MapServer
  alias HacLongWeb.UserSocket

  defp join_game(user) do
    {:ok, socket} = connect(UserSocket, %{"token" => Accounts.sign_token(user)})
    {:ok, reply, socket} = subscribe_and_join(socket, "game", %{})
    {reply, socket}
  end

  # Server giới hạn tốc độ thao tác; test chạy nhanh hơn người bấm nên đợi rồi gửi lại.
  defp cmd(socket, payload) do
    ref = push(socket, "cmd", payload)
    assert_reply ref, :ok, reply

    if reply[:msg] == "Thao tác quá nhanh." do
      Process.sleep(100)
      cmd(socket, payload)
    else
      reply
    end
  end

  test "từ chối kết nối khi token sai" do
    assert :error = connect(UserSocket, %{"token" => "sai"})
    assert :error = connect(UserSocket, %{})
  end

  # Tạo nhân vật rồi đặt sẵn ở vị trí `pos` trong database, trước khi vào game.
  defp player_at(user, pos, attrs \\ %{}) do
    # tên nhân vật không được trùng nên thêm số riêng cho mỗi người
    name = "Hiệp #{System.unique_integer([:positive]) |> rem(100_000)}"
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => name, "cls" => "knight"})

    # các test ở đây không nói về hướng dẫn người mới: tắt để không có thông báo lẫn vào
    p = p |> Map.put(:tutorial, nil) |> Map.merge(attrs) |> Map.put(:pos, pos)

    # thành tựu đã đủ điều kiện thì nhận trước, cũng để không có thông báo lẫn vào
    {p, _} = HacLong.Game.Achievements.check(p)
    Characters.save!(user.id, p)
    p
  end

  test "tên nhân vật không được trùng (không phân biệt hoa thường) và phải hợp lệ" do
    a = create_user()
    {_, sa} = join_game(a)

    assert cmd(sa, %{"act" => "create", "name" => "  Rồng   Đen ", "cls" => "rogue"}).player.name ==
             "Rồng Đen"

    b = create_user()
    {_, sb} = join_game(b)

    for bad <- ["rồng đen", "RỒNG  ĐEN"] do
      assert %{ok: false, msg: "Tên này đã có người dùng.", player: nil} =
               cmd(sb, %{"act" => "create", "name" => bad, "cls" => "rogue"})
    end

    assert %{ok: false, msg: "Tên nhân vật phải dài 2–16 ký tự."} =
             cmd(sb, %{"act" => "create", "name" => "x", "cls" => "rogue"})

    assert %{ok: false, msg: "Tên chỉ gồm chữ, số, khoảng trắng, - và _."} =
             cmd(sb, %{"act" => "create", "name" => "<b>hi</b>", "cls" => "rogue"})

    # tên khác dấu là tên khác
    assert %{ok: true} = cmd(sb, %{"act" => "create", "name" => "Rồng Đèn", "cls" => "rogue"})
  end

  test "tạo nhân vật rồi ra khỏi nhà" do
    user = create_user()
    {reply, socket} = join_game(user)
    assert reply.player == nil
    assert reply.username == user.username and reply.user_id == user.id

    r = cmd(socket, %{"act" => "create", "name" => "Hiệp", "cls" => "knight"})
    assert r.ok and r.player.cls == "knight"
    assert r.player.pos == %{map: "home", x: 5, y: 6}
    assert_push "map", %{map: "home", monsters: []}
    assert [_, _, _] = r.player.daily.tasks
    assert Characters.load(user.id).daily.date == HacLong.Game.Daily.today()
    assert Characters.load(user.id).name == "Hiệp"

    # bước xuống cửa nhà thì ra Làng
    r = cmd(socket, %{"act" => "move", "dir" => "down"})
    assert r.ok and r.player.pos == %{map: "village", x: 12, y: 15}
    # hướng dẫn người mới sang bước 2, chỉ đường tới Trưởng Làng
    assert_push "notice", %{msg: "Hướng dẫn 2/5" <> _}
    assert %{step: 2, target: %{map: "village"}} = r.player.view.tutorial
    assert Characters.load(user.id).tutorial == 1
    assert_push "map", %{map: "village", players: players}
    assert Enum.any?(players, &(&1.id == user.id))
    assert Characters.load(user.id).pos.map == "village"
  end

  test "chạm quái trên bản đồ, chiến đấu và lưu vào database" do
    MapServer.clear_monsters("forest_1")
    user = create_user()

    player_at(user, %{map: "forest_1", x: 13, y: 16}, %{
      quests: %{active: %{"forest_kill" => 0}, done: []}
    })

    {_, socket} = join_game(user)
    assert_push "map", %{map: "forest_1"}
    bat = MapServer.put_monster("forest_1", "bat", {13, 15})

    r = cmd(socket, %{"act" => "move", "dir" => "up"})
    assert r.ok and r.player.battle.monster.id == "bat"
    assert r.player.battle.encounter == %{map: "forest_1", mid: bat.id}
    # người đứng yên, quái bị khóa cho người này
    assert r.player.pos == %{map: "forest_1", x: 13, y: 16}
    assert [%{busy: true}] = MapServer.snapshot("forest_1").monsters

    r =
      Enum.reduce_while(1..200, r, fn _, _ ->
        r = cmd(socket, %{"act" => "attack"})
        if r.player.battle.over, do: {:halt, r}, else: {:cont, r}
      end)

    assert r.player.battle.result in ~w(win lose)

    # trận đấu (kể cả nhật ký) được lưu và đọc lại đúng như trong bộ nhớ
    assert Characters.load(user.id) == Map.delete(r.player, :view)
    assert r.player.view.derived.maxHp > 0

    if r.player.battle.result == "win" do
      assert MapServer.snapshot("forest_1").monsters == []
      # hạ Dơi Hang thì nhiệm vụ "Lũ dơi hang" được cộng tiến độ
      assert r.player.quests.active["forest_kill"] == 1
      assert Characters.load(user.id).quests.active["forest_kill"] == 1
      # và việc hằng ngày "hạ quái ở Rừng Mê" (vùng 0)
      zone_task = Enum.find(r.player.daily.tasks, &(&1.kind == "zone"))
      assert zone_task.zone != 0 or zone_task.progress == 1
    else
      assert r.player.pos.map == "home"
    end

    r = cmd(socket, %{"act" => "leave"})
    assert r.player.battle == nil
    assert Characters.load(user.id).battle == nil
  end

  test "chạm đá dịch chuyển rồi dịch chuyển về Làng" do
    two = HacLong.World.Maps.get("forest_2")
    {sx, sy} = two.waystone.spawn
    user = create_user()
    player_at(user, %{map: "forest_2", x: sx, y: sy})
    {_, socket} = join_game(user)

    r = cmd(socket, %{"act" => "move", "dir" => "up"})
    assert r.ok and r.waystone
    assert Characters.load(user.id).waystones == ["forest_2"]

    r = cmd(socket, %{"act" => "teleport", "to" => "village"})
    assert r.ok and r.player.pos.map == "village"
    assert_push "map", %{map: "village"}
    assert Characters.load(user.id).pos.map == "village"
  end

  test "chat thế giới: mọi người nhận được, chữ được làm sạch, chống spam" do
    HacLong.RateLimit.reset()
    a = create_user()
    b = create_user()
    pa = player_at(a, %{map: "village", x: 12, y: 14})
    player_at(b, %{map: "forest_1", x: 13, y: 16})
    name = pa.name
    {_, sa} = join_game(a)
    {_, _sb} = join_game(b)
    assert_push "chat_history", %{messages: _}

    ref = push(sa, "chat", %{"text" => "  xin\nchào\u0000   mọi người  "})
    assert_reply ref, :ok
    # cả hai kênh (a và b) đều nhận
    assert_push "chat", %{text: "xin chào mọi người", name: ^name, map: "village", uid: uid}
    assert uid == a.id
    assert_push "chat", %{text: "xin chào mọi người"}
    assert Enum.any?(HacLong.Chat.history(), &(&1.text == "xin chào mọi người"))

    ref = push(sa, "chat", %{"text" => String.duplicate("a", 500)})
    assert_reply ref, :ok
    assert_push "chat", %{text: long}
    assert String.length(long) == 120

    ref = push(sa, "chat", %{"text" => "   "})
    assert_reply ref, :error, %{msg: "Tin nhắn trống."}

    replies =
      for i <- 1..6 do
        ref = push(sa, "chat", %{"text" => "spam #{i}"})
        assert_reply ref, status, _
        status
      end

    assert :error in replies
  end

  test "chưa có nhân vật thì chưa chat được; xem bảng xếp hạng" do
    user = create_user()
    {_, socket} = join_game(user)
    ref = push(socket, "chat", %{"text" => "alo"})
    assert_reply ref, :error, %{msg: "Hãy tạo nhân vật trước."}

    ref = push(socket, "leaderboard", %{})
    assert_reply ref, :ok, %{level: level, kills: _, dragon: _, me: nil}
    assert is_list(level)
  end

  test "hạ Hắc Long lần đầu thì ghi thời điểm cho bảng Diệt rồng" do
    MapServer.clear_monsters("lair_boss")
    user = create_user()
    bosses = ~w(wolf orc_warrior lich hill_giant golden_dragon)

    p =
      player_at(user, %{map: "lair_boss", x: 7, y: 4}, %{
        level: 50,
        bosses: bosses,
        stats: %{str: 400, vit: 200, agi: 0, def: 200},
        hp: 5000
      })

    {_, socket} = join_game(user)
    MapServer.put_monster("lair_boss", "shadow_dragon", {7, 3}, true)
    r = cmd(socket, %{"act" => "move", "dir" => "up", "confirm" => true})
    assert r.player.battle.monster.final

    r =
      Enum.reduce_while(1..100, r, fn _, _ ->
        r = cmd(socket, %{"act" => "attack"})
        if r.player.battle.over, do: {:halt, r}, else: {:cont, r}
      end)

    assert r.player.battle.result == "win" and r.player.victory
    assert %DateTime{} = Characters.load(user.id).victory_at
    assert [%{name: name} | _] = HacLong.Leaderboard.top(:dragon)
    assert name == p.name
  end

  describe "trùm thế giới" do
    setup do
      HacLong.WorldBoss.despawn()
      on_exit(fn -> HacLong.WorldBoss.despawn() end)
      :ok
    end

    # nhân vật mạnh đứng ngay dưới chỗ trùm ở Tế Đàn
    defp champion(stats) do
      {bx, by} = HacLong.World.Maps.get("altar").world_boss
      user = create_user()

      p =
        player_at(user, %{map: "altar", x: bx, y: by + 1}, %{
          level: 40,
          stats: stats,
          hp: 20_000
        })

      {_, socket} = join_game(user)
      {user, p, socket}
    end

    defp fight(socket) do
      r = cmd(socket, %{"act" => "move", "dir" => "up"})
      assert %{ok: false, confirm: "boss", boss: %{world: true}} = r
      r = cmd(socket, %{"act" => "move", "dir" => "up", "confirm" => true})
      assert r.player.battle.monster.world
      r
    end

    test "chưa xuất hiện thì ô của trùm là ô trống" do
      {_user, _p, socket} = champion(%{str: 10, vit: 10, agi: 0, def: 10})
      r = cmd(socket, %{"act" => "move", "dir" => "up"})
      assert r.ok and r.player.battle == nil
    end

    test "cả server đánh chung một thanh máu, chia thưởng theo sát thương" do
      HacLong.WorldBoss.spawn_now(hp: 3000)
      {ua, pa, sa} = champion(%{str: 300, vit: 200, agi: 0, def: 300})
      {ub, pb, sb} = champion(%{str: 40, vit: 200, agi: 0, def: 300})

      fight(sb)
      # trùm có thể né vài đòn, đánh tới khi trúng
      rb =
        Enum.reduce_while(1..20, nil, fn _, _ ->
          r = cmd(sb, %{"act" => "attack"})
          if r.player.battle.monster.hp < 3000, do: {:halt, r}, else: {:cont, r}
        end)

      # B đánh làm giảm máu chung
      assert rb.player.battle.monster.hp < 3000
      assert HacLong.WorldBoss.status().hp == rb.player.battle.monster.hp

      # A vào sau thấy máu chung, không phải máu đầy
      ra = fight(sa)
      assert ra.player.battle.monster.hp == HacLong.WorldBoss.status().hp

      ra =
        Enum.reduce_while(1..200, ra, fn _, _ ->
          r = cmd(sa, %{"act" => "attack"})
          if r.player.battle.over, do: {:halt, r}, else: {:cont, r}
        end)

      assert ra.player.battle.result == "win"
      refute HacLong.WorldBoss.status().alive

      # thưởng đến qua Session (không đồng bộ): A và B đều được, A (gây nhiều hơn) được nhiều hơn
      a = wait_for(fn -> Characters.load(ua.id) end, &(&1.gold > pa.gold))
      b = wait_for(fn -> Characters.load(ub.id) end, &(&1.gold > pb.gold))
      assert a.gold - pa.gold > b.gold - pb.gold
      assert a.inv["dragon_scale"] == 1 and b.inv["dragon_scale"] == 1
      # trận của B (đang đánh dở) cũng kết thúc
      assert b.battle.over and b.battle.result == "win"
      assert b.battle.monster.hp == 0
      assert a.battle.reward.gold > 0
    end

    test "hết giờ thì trùm bay đi, trận đang đánh kết thúc, không ai được thưởng" do
      HacLong.WorldBoss.spawn_now(hp: 100_000)
      {ua, pa, sa} = champion(%{str: 20, vit: 200, agi: 0, def: 300})
      fight(sa)
      cmd(sa, %{"act" => "attack"})
      HacLong.WorldBoss.despawn()
      a = wait_for(fn -> Characters.load(ua.id) end, &(&1.battle && &1.battle.over))
      assert a.battle.result == "fled" and a.gold == pa.gold
      assert_push "notice", %{msg: msg}
      assert msg =~ "bay đi"
    end
  end

  defp wait_for(get, ok?, tries \\ 50) do
    v = get.()

    cond do
      ok?.(v) -> v
      tries == 0 -> flunk("đợi mãi không thấy: #{inspect(v, limit: 5)}")
      true -> Process.sleep(50) && wait_for(get, ok?, tries - 1)
    end
  end

  test "vào tháp thì rời bản đồ Làng; tầng tháp được lưu và nạp lại" do
    user = create_user()
    player_at(user, %{map: "village", x: 21, y: 9})
    {_, socket} = join_game(user)
    assert Enum.any?(MapServer.snapshot("village").players, &(&1.id == user.id))

    r = cmd(socket, %{"act" => "tower_enter", "floor" => 1})
    assert r.ok and r.player.pos.map == "tower"
    assert_push "map", %{map: "tower"}
    refute Enum.any?(MapServer.snapshot("village").players, &(&1.id == user.id))
    loaded = Characters.load(user.id)
    assert loaded.pos == r.player.pos and loaded.tower == r.player.tower

    r = cmd(socket, %{"act" => "move", "dir" => "down"})
    assert r.player.pos.map == "village" and r.player.tower == nil
    assert Enum.any?(MapServer.snapshot("village").players, &(&1.id == user.id))
  end

  describe "chặn, báo cáo, quản trị" do
    setup do
      HacLong.RateLimit.reset()
      :ok
    end

    defp chatter do
      u = create_user()
      p = player_at(u, %{map: "village", x: 12, y: 14})
      {reply, socket} = join_game(u)
      {u, p, reply, socket}
    end

    defp say(socket, text) do
      ref = push(socket, "chat", %{"text" => text})
      assert_reply ref, status, payload
      {status, payload}
    end

    test "chặn thì không thấy chat của người đó; báo cáo lấy đúng nội dung từ server" do
      {_ua, _pa, reply, sa} = chatter()
      assert reply.admin == false and reply.blocked == []
      {ub, pb, _, sb} = chatter()

      {:ok, _} = say(sb, "câu nói xấu")
      assert_push "chat", %{text: "câu nói xấu", id: msg_id, uid: uid}
      assert uid == ub.id

      # báo cáo: chỉ gửi id, nội dung lấy từ lịch sử chat trên server
      ref = push(sa, "report", %{"id" => msg_id})
      assert_reply ref, :ok
      assert [%{text: "câu nói xấu", target: target}] = HacLong.Moderation.open_reports()
      assert target == pb.name
      ref = push(sa, "report", %{"id" => 999_999})
      assert_reply ref, :error, %{msg: "Tin nhắn đã quá cũ để báo cáo."}

      ref = push(sa, "block", %{"uid" => ub.id})
      assert_reply ref, :ok, %{blocked: [%{id: id}]}
      assert id == ub.id
      # tin của B vẫn đến kênh B, nhưng kênh A không nhận
      {:ok, _} = say(sb, "sau khi bị chặn")
      assert_push "chat", %{text: "sau khi bị chặn"}
      refute_push "chat", %{text: "sau khi bị chặn"}

      ref = push(sa, "unblock", %{"uid" => ub.id})
      assert_reply ref, :ok, %{blocked: []}
    end

    test "danh hiệu hiện trong chat và bảng xếp hạng" do
      u = create_user()
      player_at(u, %{map: "village", x: 12, y: 14}, %{kills: 150})
      {_, socket} = join_game(u)

      r = cmd(socket, %{"act" => "title_set", "id" => "hunter"})
      assert r.ok and r.player.title == "hunter"
      assert Enum.find(r.player.view.achievements, &(&1.id == "hunter")).done

      {:ok, _} = say(socket, "chào")
      assert_push "chat", %{text: "chào", title: "Thợ Săn"}

      ref = push(socket, "leaderboard", %{})
      assert_reply ref, :ok, %{kills: kills}
      assert Enum.find(kills, &(&1.user_id == u.id)).title == "Thợ Săn"
    end

    test "người thường không gọi được lệnh quản trị" do
      {_u, _p, _r, socket} = chatter()
      ref = push(socket, "admin", %{"op" => "reports"})
      assert_reply ref, :error, %{msg: "Không có quyền."}
    end

    test "quản trị: xử lý báo cáo bằng cấm chat, khóa và mở khóa tài khoản" do
      {ua, _pa, _, sa} = chatter()
      {ub, pb, _, sb} = chatter()
      admin = create_user()
      {:ok, _} = HacLong.Moderation.set_admin(admin.username, true)
      admin = HacLong.Accounts.get_user(admin.id)
      player_at(admin, %{map: "village", x: 11, y: 14})
      {reply, sadm} = join_game(admin)
      assert reply.admin

      {:ok, _} = say(sb, "spam quảng cáo")
      assert_push "chat", %{text: "spam quảng cáo", id: msg_id}
      ref = push(sa, "report", %{"id" => msg_id})
      assert_reply ref, :ok

      ref = push(sadm, "admin", %{"op" => "reports"})
      assert_reply ref, :ok, %{reports: [%{id: rid, target_id: tid}]}
      assert tid == ub.id

      ref =
        push(sadm, "admin", %{"op" => "resolve", "id" => rid, "action" => "mute", "minutes" => 30})

      assert_reply ref, :ok
      assert HacLong.Moderation.open_reports() == []
      {:error, %{msg: msg}} = say(sb, "còn nói được không")
      assert msg =~ "cấm chat"

      ref = push(sadm, "admin", %{"op" => "lookup", "name" => pb.name})
      assert_reply ref, :ok, %{user: %{id: ^tid, muted_until: %DateTime{}}}

      # khóa tài khoản: đăng nhập bị từ chối, token cũ hết hiệu lực, kết nối bị ngắt
      token = HacLong.Accounts.sign_token(ub)
      @endpoint.subscribe("user_socket:#{ub.id}")
      ref = push(sadm, "admin", %{"op" => "ban", "uid" => ub.id, "reason" => "spam"})
      assert_reply ref, :ok
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: "user_socket:" <> _}
      assert {:error, :invalid} = HacLong.Accounts.verify_token(token)
      assert {:error, {:banned, _}} = HacLong.Accounts.authenticate(ub.username, "matkhau1")

      ref = push(sadm, "admin", %{"op" => "unban", "uid" => ub.id})
      assert_reply ref, :ok
      assert {:ok, _} = HacLong.Accounts.authenticate(ub.username, "matkhau1")

      ref = push(sadm, "admin", %{"op" => "announce", "text" => "Bảo trì lúc 22 giờ"})
      assert_reply ref, :ok
      assert_push "chat", %{uid: 0, text: "📢 Bảo trì lúc 22 giờ"}
      _ = ua
    end
  end

  describe "hộp thư" do
    setup do
      HacLong.RateLimit.reset()
      :ok
    end

    test "quản trị tặng quà; mở thư nhận quà đúng một lần" do
      u = create_user()
      p = player_at(u, %{map: "village", x: 12, y: 14})
      {reply, socket} = join_game(u)
      assert reply.mail == 0

      admin = create_user()
      {:ok, _} = HacLong.Moderation.set_admin(admin.username, true)
      admin = HacLong.Accounts.get_user(admin.id)
      player_at(admin, %{map: "village", x: 11, y: 14})
      {_, sadm} = join_game(admin)

      ref =
        push(sadm, "admin", %{
          "op" => "gift",
          "uid" => u.id,
          "subject" => "Đền bù bảo trì",
          "gold" => 500,
          "items" => %{"potion_m" => 2}
        })

      assert_reply ref, :ok, %{sent: 1}
      assert_push "mail", %{unread: 1}

      ref = push(socket, "mail", %{})

      assert_reply ref, :ok, %{
        unread: 1,
        mails: [%{id: id, subject: "Đền bù bảo trì", claimed: false}]
      }

      r = cmd(socket, %{"act" => "mail_claim", "id" => id})
      assert r.ok and r.msg =~ "+500 vàng"
      assert r.player.gold == p.gold + 500
      assert r.player.inv["potion_m"] == 2
      assert_push "mail", %{unread: 0}
      # đã lưu database
      assert Characters.load(u.id).gold == p.gold + 500

      assert %{ok: false, msg: "Thư đã mở rồi."} =
               cmd(socket, %{"act" => "mail_claim", "id" => id})

      assert Characters.load(u.id).gold == p.gold + 500

      # vật phẩm không có thật thì không gửi
      ref = push(sadm, "admin", %{"op" => "gift", "uid" => u.id, "items" => %{"xyz" => 1}})
      assert_reply ref, :error, %{msg: "Vật phẩm không hợp lệ."}

      ref = push(sadm, "admin", %{"op" => "gift", "all" => true, "gold" => 10})
      assert_reply ref, :ok, %{sent: n}
      assert n >= 2
      assert_push "mail", %{unread: 1}
    end

    test "không online lúc hạ trùm thế giới thì nhận thưởng qua hộp thư" do
      u = create_user()
      p = player_at(u, %{map: "village", x: 12, y: 14})

      :ok =
        Session.world_boss_end(u.id, %{
          result: "win",
          reward: %{gold: 300, xp: 40, items: %{"dragon_scale" => 1}, share: 25}
        })

      assert Characters.load(u.id).gold == p.gold

      assert [%{subject: "Thưởng trùm thế giới", gold: 300, body: body}] =
               HacLong.Mailbox.list(u.id)

      assert body =~ "25%"
    end
  end

  test "người chơi khác thấy nhau trên bản đồ, tab đóng thì rời bản đồ" do
    a = create_user()
    b = create_user()
    player_at(a, %{map: "village", x: 12, y: 14})
    player_at(b, %{map: "village", x: 11, y: 14})
    {_, sa} = join_game(a)
    {_, _sb} = join_game(b)

    cmd(sa, %{"act" => "move", "dir" => "up"})
    snap = MapServer.snapshot("village")
    assert %{x: 12, y: 13} = Enum.find(snap.players, &(&1.id == a.id))
    assert Enum.find(snap.players, &(&1.id == b.id))

    Process.unlink(sa.channel_pid)
    ref = Process.monitor(sa.channel_pid)
    close(sa)
    assert_receive {:DOWN, ^ref, _, _, _}
    # Session xử lý tin DOWN của tab rồi mới trả lời lệnh này
    Session.get(a.id)
    refute Enum.find(MapServer.snapshot("village").players, &(&1.id == a.id))
    # vị trí đã đi được ghi lại khi rời game
    assert Characters.load(a.id).pos == %{map: "village", x: 12, y: 13}
  end

  test "thao tác quá nhanh bị từ chối" do
    user = create_user()
    player_at(user, %{map: "village", x: 12, y: 14})
    {_, socket} = join_game(user)

    refs = for _ <- 1..20, do: push(socket, "cmd", %{"act" => "unequip", "slot" => "shield"})

    msgs =
      for ref <- refs do
        assert_reply ref, :ok, reply
        reply[:msg]
      end

    assert "Thao tác quá nhanh." in msgs
  end

  test "bước đi quá nhanh bị từ chối" do
    user = create_user()
    player_at(user, %{map: "village", x: 12, y: 14})
    {_, socket} = join_game(user)

    results =
      for _ <- 1..10, do: cmd(socket, %{"act" => "move", "dir" => Enum.random(~w(left right))})

    assert Enum.count(results, & &1.ok) < 10
  end

  test "trạng thái sống sót khi tiến trình session tắt và nạp lại từ database" do
    user = create_user()
    {_, socket} = join_game(user)
    cmd(socket, %{"act" => "create", "name" => "Bền", "cls" => "rogue"})
    r = cmd(socket, %{"act" => "move", "dir" => "left"})

    [{pid, _}] = Registry.lookup(HacLong.Game.Registry, user.id)
    DynamicSupervisor.terminate_child(HacLong.Game.SessionSupervisor, pid)

    assert Session.get(user.id) == Map.delete(r.player, :view)
  end

  test "tab khác nhận trạng thái mới, tab gửi lệnh thì không nhận trùng" do
    user = create_user()
    {_, s1} = join_game(user)
    {:ok, sock2} = connect(UserSocket, %{"token" => Accounts.sign_token(user)})
    {:ok, _, _s2} = subscribe_and_join(sock2, "game", %{})

    cmd(s1, %{"act" => "create", "name" => "Hai Tab", "cls" => "warrior"})
    assert_push "player", %{player: %{name: "Hai Tab"}}
    refute_push "player", _
  end

  test "xóa nhân vật" do
    user = create_user()
    {_, socket} = join_game(user)
    cmd(socket, %{"act" => "create", "name" => "Xóa", "cls" => "warrior"})
    r = cmd(socket, %{"act" => "reset"})
    assert r.player == nil
    assert Characters.load(user.id) == nil
  end

  test "lệnh sai cú pháp" do
    {_, socket} = join_game(create_user())
    ref = push(socket, "cmd", "khong phai map")
    assert_reply ref, :error, _
    ref = push(socket, "lung tung", %{})
    assert_reply ref, :error, _
  end
end
