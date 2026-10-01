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
    assert [_, _, _, _] = r.player.daily.tasks
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

    assert r.player.battle.encounter == %{
             map: "forest_1",
             mid: bat.id,
             shared: "forest_1:#{bat.id}"
           }

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
    assert Characters.load(user.id) == Map.drop(r.player, [:view, :guild])
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
      assert a.boss_top == 1 and b.boss_top == 1
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

  describe "tổ đội" do
    setup do
      HacLong.RateLimit.reset()
      MapServer.clear_monsters("forest_1")
      :ok
    end

    defp pop(socket, op, payload \\ %{}) do
      ref = push(socket, "party", Map.put(payload, "op", op))
      assert_reply ref, status, reply
      {status, reply}
    end

    test "mời vào tổ đội, đánh chung một con quái, cùng thắng và chia thưởng" do
      ua = create_user()
      stats = %{str: 12, vit: 60, agi: 0, def: 30}
      pa = player_at(ua, %{map: "forest_1", x: 12, y: 15}, %{level: 5, stats: stats})
      {_, sa} = join_game(ua)
      ub = create_user()
      pb = player_at(ub, %{map: "forest_1", x: 14, y: 15}, %{level: 5, stats: stats})
      {_, sb} = join_game(ub)

      assert {:error, %{msg: "Người này không online."}} = pop(sa, "invite", %{"uid" => 999_999})
      assert {:ok, %{party: %{members: [_]}}} = pop(sa, "invite", %{"uid" => ub.id})
      assert_push "party_invite", %{from: from}
      assert from == ua.id
      assert {:ok, %{party: %{leader: leader, members: [_, _]}}} = pop(sb, "accept")
      assert leader == ua.id

      # chat tổ đội
      ref = push(sb, "chat", %{"text" => "đánh con nhện nào", "to" => "party"})
      assert_reply ref, :ok
      assert_push "chat", %{text: "đánh con nhện nào", party: true}

      # A chạm quái, B chạm vào cùng con quái thì vào đánh chung
      spider = MapServer.put_monster("forest_1", "spider", {13, 15})
      ra = cmd(sa, %{"act" => "move", "dir" => "right"})
      key = "forest_1:#{spider.id}"
      assert ra.player.battle.encounter.shared == key
      full = ra.player.battle.monster.maxHp

      # quái có thể né vài đòn: đánh tới khi trúng
      ra =
        Enum.reduce_while(1..20, nil, fn _, _ ->
          r = cmd(sa, %{"act" => "attack"})
          if r.player.battle.monster.hp < full, do: {:halt, r}, else: {:cont, r}
        end)

      left = ra.player.battle.monster.hp
      assert left < full

      rb = cmd(sb, %{"act" => "move", "dir" => "left"})
      assert rb.ok and rb.msg =~ "Vào đánh cùng đồng đội (2 người)"
      assert rb.player.battle.monster.hp == left
      assert rb.player.battle.encounter.joined

      # đánh luân phiên tới khi quái gục
      Enum.reduce_while(1..200, nil, fn i, _ ->
        s = if rem(i, 2) == 0, do: sa, else: sb
        r = cmd(s, %{"act" => "attack"})
        if r.player.battle && r.player.battle.over, do: {:halt, r}, else: {:cont, r}
      end)

      # cả hai cùng thắng (người không ra đòn cuối được báo qua Session)
      a = wait_for(fn -> Session.get(ua.id) end, &(&1.battle && &1.battle.over))
      b = wait_for(fn -> Session.get(ub.id) end, &(&1.battle && &1.battle.over))
      assert a.battle.result == "win" and b.battle.result == "win"
      # thưởng mỗi người = thưởng gốc × 1,2 / 2
      base = HacLong.Game.Engine.make_monster(HacLong.Game.Data.monster("spider"), false).xp
      assert a.battle.reward.xp == round(base * 0.6) and b.battle.reward.xp == round(base * 0.6)
      assert a.kills == pa.kills + 1 and b.kills == pb.kills + 1
      # con quái biến mất khỏi bản đồ sau khi cả hai rời trận
      cmd(sa, %{"act" => "leave"})
      cmd(sb, %{"act" => "leave"})
      assert MapServer.snapshot("forest_1").monsters == []

      assert {:ok, %{party: nil}} = pop(sb, "leave")
      assert_push "party", %{party: nil}
    end
  end

  describe "giao dịch trực tiếp" do
    setup do
      HacLong.RateLimit.reset()
      HacLong.Trade.reset()
      :ok
    end

    defp top(socket, op, payload \\ %{}) do
      ref = push(socket, "trade", Map.put(payload, "op", op))
      assert_reply ref, status, r
      {status, r}
    end

    test "mời, bỏ đồ, đổi gì cũng phải xác nhận lại, cả hai xác nhận thì đổi" do
      sword = %{uid: "#TRADE1", base: "club", rarity: 2, bonus: %{str: 3}}
      ua = create_user()

      pa =
        player_at(ua, %{map: "village", x: 12, y: 14}, %{
          gold: 500,
          inv: %{"potion_s" => 5},
          gear: [sword],
          upgrades: %{"#TRADE1" => 2}
        })

      ub = create_user()
      pb = player_at(ub, %{map: "village", x: 13, y: 14}, %{gold: 1000})
      {_, sa} = join_game(ua)
      {_, sb} = join_game(ub)

      assert {:error, %{msg: "Không tự giao dịch với mình được."}} =
               top(sa, "request", %{"uid" => ua.id})

      assert {:ok, %{trade: %{status: :pending, incoming: false}}} =
               top(sa, "request", %{"uid" => ub.id})

      assert_push "trade_request", %{from: from}
      assert from == ua.id
      assert {:ok, %{trade: %{status: :open, partner_name: name}}} = top(sb, "accept")
      assert name == pa.name

      # không đủ đồ thì không cho bỏ vào
      assert {:error, %{msg: "Không đủ đồ trong túi."}} =
               top(sa, "offer", %{"offer" => %{"items" => %{"potion_s" => 9}}})

      offer_a = %{"items" => %{"potion_s" => 2}, "gear" => ["#TRADE1"], "gold" => 100}

      assert {:ok, %{trade: %{mine: %{gold: 100, gear: [g]}}}} =
               top(sa, "offer", %{"offer" => offer_a})

      assert g.up == 2 and g.rarity == 2

      assert {:ok, _} = top(sb, "offer", %{"offer" => %{"gold" => 300}})
      assert {:ok, %{trade: %{my_ready: true, their_ready: false}}} = top(sa, "ready")

      # B đổi món thì A phải xác nhận lại
      assert {:ok, %{trade: %{my_ready: false, their_ready: false}}} =
               top(sb, "offer", %{"offer" => %{"gold" => 250}})

      assert {:ok, _} = top(sa, "ready")
      assert {:ok, _} = top(sb, "ready")

      wait_for(fn -> HacLong.Trade.of(ua.id) end, &is_nil/1)
      a = Session.get(ua.id)
      b = Session.get(ub.id)
      assert a.gold == pa.gold - 100 + 250 and b.gold == pb.gold - 250 + 100
      assert a.inv["potion_s"] == 3 and b.inv["potion_s"] == Map.get(pb.inv, "potion_s", 0) + 2
      assert a.gear == []
      assert [%{uid: "#TRADE1"}] = b.gear
      assert b.upgrades["#TRADE1"] == 2 and not Map.has_key?(a.upgrades || %{}, "#TRADE1")
      assert Characters.load(ub.id).gold == b.gold
    end

    test "hủy, người kia bận, thiếu đồ lúc đổi thì mở lại" do
      ua = create_user()
      player_at(ua, %{map: "village", x: 12, y: 14}, %{gold: 500})
      ub = create_user()
      player_at(ub, %{map: "village", x: 13, y: 14}, %{gold: 500})
      uc = create_user()
      player_at(uc, %{map: "village", x: 14, y: 14})
      {_, sa} = join_game(ua)
      {_, sb} = join_game(ub)
      {_, sc} = join_game(uc)

      assert {:ok, _} = top(sa, "request", %{"uid" => ub.id})

      assert {:error, %{msg: "Người này đang bận giao dịch."}} =
               top(sc, "request", %{"uid" => ub.id})

      assert {:ok, %{trade: nil}} = top(sb, "decline")
      assert {:ok, %{trade: nil}} = top(sa, "info")

      assert {:ok, _} = top(sa, "request", %{"uid" => ub.id})
      assert {:ok, _} = top(sb, "accept")
      assert {:ok, _} = top(sa, "offer", %{"offer" => %{"gold" => 400}})
      # A tiêu mất vàng trước khi đổi
      :sys.replace_state({:via, Registry, {HacLong.Game.Registry, ua.id}}, fn st ->
        put_in(st.player.gold, 10)
      end)

      assert {:ok, _} = top(sa, "ready")
      assert {:ok, _} = top(sb, "ready")

      t = wait_for(fn -> HacLong.Trade.of(ub.id) end, &(&1 && &1.status == :open))
      assert not t.my_ready and not t.their_ready
      assert Session.get(ub.id).gold == 500
      assert {:ok, %{trade: nil}} = top(sa, "cancel")
    end
  end

  describe "bạn bè và tin riêng" do
    setup do
      HacLong.RateLimit.reset()
      :ok
    end

    defp fop(socket, op, payload \\ %{}) do
      ref = push(socket, "friends", Map.put(payload, "op", op))
      assert_reply ref, status, r
      {status, r}
    end

    test "mời kết bạn theo tên, nhận lời, nhắn tin, chưa đọc, xóa bạn" do
      ua = create_user()
      pa = player_at(ua, %{map: "village", x: 12, y: 14})
      ub = create_user()
      pb = player_at(ub, %{map: "village", x: 13, y: 14})
      {_, sa} = join_game(ua)
      {_, sb} = join_game(ub)

      assert {:error, %{msg: "Không tự kết bạn với mình được."}} =
               fop(sa, "request", %{"uid" => ua.id})

      assert {:error, %{msg: "Không có nhân vật tên này."}} =
               fop(sa, "request", %{"name" => "Không Ai"})

      # chưa là bạn thì không nhắn được
      ref = push(sa, "dm", %{"op" => "send", "uid" => ub.id, "text" => "chào"})
      assert_reply ref, :error, %{msg: "Chỉ nhắn riêng được cho bạn bè."}

      assert {:ok, %{msg: "Đã gửi lời mời kết bạn.", outgoing: [%{id: bid}]}} =
               fop(sa, "request", %{"name" => String.upcase(pb.name)})

      assert bid == ub.id
      assert_push "friends", %{msg: "👋 " <> _}
      assert {:error, _} = fop(sa, "request", %{"uid" => ub.id})
      assert {:ok, %{incoming: [%{id: aid}]}} = fop(sb, "list")
      assert aid == ua.id

      assert {:ok, %{friends: [%{id: ^aid, online: true, unread: 0}], incoming: []}} =
               fop(sb, "accept", %{"uid" => ua.id})

      assert {:ok, %{friends: [%{name: name}]}} = fop(sa, "list")
      assert name == pb.name

      ref = push(sa, "dm", %{"op" => "send", "uid" => ub.id, "text" => "  chào   bạn  "})
      assert_reply ref, :ok, %{message: %{text: "chào bạn"}}
      assert_push "dm", %{text: "chào bạn", from: from}
      assert from == ua.id
      assert {:ok, %{unread: 1, friends: [%{unread: 1}]}} = fop(sb, "list")

      ref = push(sb, "dm", %{"op" => "history", "uid" => ua.id})

      assert_reply ref, :ok, %{messages: [%{text: "chào bạn"}], unread: 0, with: %{name: aname}}
      assert aname == pa.name

      assert {:ok, %{unread: 0}} = fop(sb, "list")

      ref = push(sa, "dm", %{"op" => "send", "uid" => ub.id, "text" => "   "})
      assert_reply ref, :error, %{msg: "Tin nhắn trống."}

      assert {:ok, %{friends: []}} = fop(sa, "remove", %{"uid" => ub.id})
      assert {:ok, %{friends: []}} = fop(sb, "list")
    end

    test "hai người cùng mời thì thành bạn; bị chặn thì không mời được" do
      ua = create_user()
      player_at(ua, %{map: "village", x: 12, y: 14})
      ub = create_user()
      player_at(ub, %{map: "village", x: 13, y: 14})
      {_, sa} = join_game(ua)
      {_, sb} = join_game(ub)

      assert {:ok, _} = fop(sa, "request", %{"uid" => ub.id})
      assert {:ok, %{friends: [_]}} = fop(sb, "request", %{"uid" => ua.id})
      assert {:ok, _} = fop(sa, "remove", %{"uid" => ub.id})

      ref = push(sb, "block", %{"uid" => ua.id})
      assert_reply ref, :ok, _
      assert {:error, %{msg: "Không gửi được lời mời."}} = fop(sa, "request", %{"uid" => ub.id})
    end
  end

  describe "thăm nhà" do
    setup do
      HacLong.RateLimit.reset()
      :ok
    end

    test "xem nhà đã trang trí của người khác, khen nhà một lần, chủ nhà được báo" do
      owner = create_user()

      player_at(owner, %{map: "village", x: 12, y: 14}, %{
        decor: [%{id: "plant", x: 3, y: 5}, %{id: "fountain", x: 7, y: 2}],
        pet: "hound",
        pets: ["hound"]
      })

      {_, so} = join_game(owner)
      guest = create_user()
      player_at(guest, %{map: "village", x: 13, y: 14})
      {_, sg} = join_game(guest)

      ref = push(sg, "visit", %{"uid" => owner.id})
      assert_reply ref, :ok, v
      assert v.id == owner.id and v.likes == 0 and not v.liked
      assert [%{id: "plant", x: 3, y: 5}, %{id: "fountain"}] = v.decor
      assert v.comfort > 0 and v.look.pet == "hound"

      ref = push(sg, "home_like", %{"uid" => owner.id})
      assert_reply ref, :ok, %{likes: 1}
      assert_push "notice", %{msg: "🏡 " <> _}
      ref = push(sg, "home_like", %{"uid" => owner.id})
      assert_reply ref, :error, %{msg: "Bạn đã khen nhà này rồi."}

      ref = push(sg, "visit", %{"uid" => owner.id})
      assert_reply ref, :ok, %{likes: 1, liked: true}

      # tự khen nhà mình thì không được; nhà của mình thì xem như đã khen
      ref = push(so, "home_like", %{"uid" => owner.id})
      assert_reply ref, :error, %{msg: "Không tự khen nhà mình được."}
      ref = push(so, "visit", %{"uid" => owner.id})
      assert_reply ref, :ok, %{liked: true}

      ref = push(sg, "visit", %{"uid" => -1})
      assert_reply ref, :error, %{msg: "Không tìm thấy người chơi."}
    end
  end

  describe "đấu trường" do
    setup do
      HacLong.RateLimit.reset()
      :ok
    end

    test "thách đấu bản sao người chơi khác: thắng thì lên điểm, thua không mất gì" do
      strong = %{str: 200, vit: 150, agi: 0, def: 100}
      weak = %{str: 5, vit: 30, agi: 0, def: 5}
      ua = create_user()
      pa = player_at(ua, %{map: "village", x: 12, y: 14}, %{level: 30, stats: strong, gold: 1000})
      {_, sa} = join_game(ua)
      # đối thủ không cần online
      ub = create_user()
      player_at(ub, %{map: "village", x: 13, y: 14}, %{level: 10, stats: weak})

      ref = push(sa, "inspect", %{"uid" => ub.id})

      assert_reply ref, :ok, %{
        level: 10,
        arena: %{rating: 1000},
        look: %{weapon: "hand1/club_slant"}
      }

      assert %{ok: false, msg: "Không tự thách đấu mình được."} =
               cmd(sa, %{"act" => "pvp_challenge", "uid" => ua.id})

      r = cmd(sa, %{"act" => "pvp_challenge", "uid" => ub.id})
      assert r.ok and r.player.battle.monster.pvp == ub.id

      r =
        Enum.reduce_while(1..50, r, fn _, _ ->
          r = cmd(sa, %{"act" => "attack"})
          if r.player.battle.over, do: {:halt, r}, else: {:cont, r}
        end)

      assert r.player.battle.result == "win"
      assert r.player.battle.reward.gold > 0
      assert r.player.gold == pa.gold + r.player.battle.reward.gold

      assert HacLong.Arena.stats(ua.id).rating == 1016 and
               HacLong.Arena.stats(ub.id).rating == 984

      ref = push(sa, "arena", %{})
      assert_reply ref, :ok, %{me: %{wins: 1, today: 1}, top: [_ | _]}

      # thua: không mất vàng, không về Nhà, máu như trước trận
      cmd(sa, %{"act" => "leave"})
      uc = create_user()

      player_at(uc, %{map: "village", x: 14, y: 14}, %{
        level: 50,
        stats: %{str: 900, vit: 900, agi: 0, def: 900}
      })

      before = Session.get(ua.id)
      cmd(sa, %{"act" => "pvp_challenge", "uid" => uc.id})

      r =
        Enum.reduce_while(1..50, nil, fn _, _ ->
          r = cmd(sa, %{"act" => "flee"})
          if r.player.battle.over, do: {:halt, r}, else: {:cont, r}
        end)

      assert r.player.battle.result in ["lose", "fled"]
      assert r.player.gold == before.gold and r.player.hp == before.hp
      assert r.player.pos.map == "village"
      assert HacLong.Arena.stats(ua.id).losses == 1
    end
  end

  describe "chợ" do
    setup do
      HacLong.RateLimit.reset()
      :ok
    end

    test "rao bán, mua, rút về; người bán nhận tiền qua hộp thư trừ phí" do
      sword = %{uid: "#CHO1", base: "mace", rarity: 2, bonus: %{str: 3, agi: 1}}
      ua = create_user()

      player_at(ua, %{map: "village", x: 7, y: 14}, %{
        level: 15,
        inv: %{"potion_m" => 5},
        gear: [sword],
        upgrades: %{"#CHO1" => 2}
      })

      {_, sa} = join_game(ua)
      ub = create_user()
      pb = player_at(ub, %{map: "village", x: 8, y: 15}, %{level: 15, gold: 2000})
      {_, sb} = join_game(ub)

      r = cmd(sa, %{"act" => "market_sell", "id" => "potion_m", "count" => 3, "price" => 300})
      assert r.ok and r.player.inv["potion_m"] == 2
      r = cmd(sa, %{"act" => "market_sell", "id" => "#CHO1", "price" => 1000})
      assert r.ok and r.player.gear == [] and r.player.upgrades == %{}

      assert %{ok: false, msg: "Không đủ số lượng trong túi."} =
               cmd(sa, %{"act" => "market_sell", "id" => "potion_m", "count" => 9, "price" => 10})

      ref = push(sb, "market", %{})
      assert_reply ref, :ok, %{listings: listings}
      pot = Enum.find(listings, &(&1.item == "potion_m"))
      gear = Enum.find(listings, &(&1.gear != nil))
      assert pot.count == 3 and pot.seller_id == ua.id and not pot.mine
      assert gear.gear.up == 2 and gear.name == "Chùy Gai Sức Mạnh"

      assert %{ok: false, msg: "Đây là hàng của bạn."} =
               cmd(sa, %{"act" => "market_buy", "listing" => pot.id})

      r = cmd(sb, %{"act" => "market_buy", "listing" => pot.id})
      assert r.ok and r.player.gold == pb.gold - 300 and r.player.inv["potion_m"] == 3
      assert_push "mail", %{unread: 1}
      assert [%{gold: 285, subject: "Chợ: bán được Bình Máu Vừa"}] = HacLong.Mailbox.list(ua.id)

      assert %{ok: false, msg: "Món này đã có người mua hoặc đã rút về."} =
               cmd(sb, %{"act" => "market_buy", "listing" => pot.id})

      r = cmd(sb, %{"act" => "market_buy", "listing" => gear.id})
      assert [%{uid: "#CHO1"}] = r.player.gear
      assert r.player.upgrades["#CHO1"] == 2

      # rút về
      r = cmd(sa, %{"act" => "market_sell", "id" => "potion_m", "count" => 2, "price" => 50})
      refute Map.has_key?(r.player.inv, "potion_m")
      ref = push(sa, "market", %{})
      assert_reply ref, :ok, %{listings: [%{id: lid, mine: true}]}
      r = cmd(sa, %{"act" => "market_cancel", "listing" => lid})
      assert r.ok and r.player.inv["potion_m"] == 2

      # phải đứng cạnh Chủ Chợ
      uc = create_user()
      player_at(uc, %{map: "village", x: 12, y: 14}, %{inv: %{"herb" => 1}})
      {_, sc} = join_game(uc)

      assert %{ok: false, msg: "Hãy đến gặp Chủ Chợ ở Làng."} =
               cmd(sc, %{"act" => "market_sell", "id" => "herb", "price" => 10})
    end
  end

  describe "bang hội" do
    setup do
      HacLong.RateLimit.reset()
      :ok
    end

    defp member(gold \\ 20_000) do
      u = create_user()
      p = player_at(u, %{map: "village", x: 12, y: 14}, %{gold: gold})
      {_, socket} = join_game(u)
      {u, p, socket}
    end

    defp gop(socket, op, payload \\ %{}) do
      ref = push(socket, "guild", Map.put(payload, "op", op))
      assert_reply ref, status, reply
      {status, reply}
    end

    test "hạ quái thì góp vào nhiệm vụ bang; xem nhiệm vụ và bảng xếp hạng bang" do
      MapServer.clear_monsters("forest_1")
      u = create_user()

      player_at(u, %{map: "forest_1", x: 13, y: 16}, %{
        gold: 20_000,
        level: 30,
        stats: %{str: 200, vit: 150, agi: 0, def: 100}
      })

      {_, s} = join_game(u)
      tag = "Q#{rem(System.unique_integer([:positive]), 1000)}"
      r = cmd(s, %{"act" => "guild_create", "name" => "Bang #{tag}", "tag" => tag})
      gid = r.player.guild.id

      assert {:ok, %{guild: %{quest: %{progress: 0, goal: goal, left: left}}}} = gop(s, "info")
      assert goal > 0 and left > 0

      # đặt việc tuần này là hạ 1 con quái để thử
      import Ecto.Query

      HacLong.Repo.update_all(from(g in "guilds", where: g.id == ^gid),
        set: [quest_kind: "kill", quest_goal: 1]
      )

      MapServer.put_monster("forest_1", "bat", {13, 15})
      r = cmd(s, %{"act" => "move", "dir" => "up"})
      assert r.player.battle

      Enum.reduce_while(1..50, r, fn _, _ ->
        r = cmd(s, %{"act" => "attack"})
        if r.player.battle.over, do: {:halt, r}, else: {:cont, r}
      end)

      wait_for(fn -> HacLong.GuildQuests.current(gid) end, & &1.done)
      assert [%{subject: "Nhiệm vụ bang hoàn thành"}] = HacLong.Mailbox.list(u.id)

      HacLong.GuildQuests.add_boss_damage(%{u.id => 1234})
      ref = push(s, "leaderboard", %{})
      assert_reply ref, :ok, %{guild_boss: rows}
      assert %{boss_damage: 1234, rank: _} = Enum.find(rows, &(&1.id == gid))
    end

    test "lập bang, vào bang, chat bang, góp quỹ lên cấp" do
      {ua, pa, sa} = member()
      tag = "T#{rem(System.unique_integer([:positive]), 1000)}"
      name = "Rồng Lửa #{tag}"

      assert %{ok: false, msg: "Ký hiệu bang gồm 2–4 chữ cái không dấu hoặc số."} =
               cmd(sa, %{"act" => "guild_create", "name" => name, "tag" => "!"})

      r = cmd(sa, %{"act" => "guild_create", "name" => name, "tag" => String.downcase(tag)})
      assert r.ok and r.player.gold == pa.gold - HacLong.Guilds.create_cost()
      assert %{tag: ^tag, role: "leader", level: 1} = r.player.guild
      assert_push "guild", %{guild: %{tag: ^tag}}
      gid = r.player.guild.id

      # tên trùng (khác hoa thường) thì không được
      {_ub, _pb, sb} = member()

      assert %{ok: false, msg: "Tên hoặc ký hiệu bang đã có người dùng."} =
               cmd(sb, %{"act" => "guild_create", "name" => String.upcase(name), "tag" => "ZZZ"})

      # bang mở: vào ngay
      assert {:ok, %{guild: %{members: [_, _]}, msg: "Đã vào bang " <> _}} =
               gop(sb, "join", %{"id" => gid})

      # chat bang: chỉ người trong bang nhận
      {_uc, _pc, sc} = member()
      ref = push(sb, "chat", %{"text" => "chào cả bang", "to" => "guild"})
      assert_reply ref, :ok
      assert_push "chat", %{text: "chào cả bang", guild: true, tag: ^tag}
      assert_push "chat", %{text: "chào cả bang", guild: true}
      refute_push "chat", %{text: "chào cả bang"}
      ref = push(sc, "chat", %{"text" => "tôi cũng muốn", "to" => "guild"})
      assert_reply ref, :error, %{msg: "Bạn chưa vào bang nào."}

      # bang đóng: phải xin, bang chủ duyệt
      assert {:ok, _} = gop(sa, "settings", %{"open" => false, "notice" => "Săn rồng tối nay"})
      assert {:ok, %{msg: "Đã gửi đơn" <> _}} = gop(sc, "join", %{"id" => gid})
      assert {:ok, %{guild: %{requests: [%{id: cid}]}}} = gop(sa, "info")
      assert {:ok, %{guild: %{members: members}}} = gop(sa, "accept", %{"uid" => cid})
      assert length(members) == 3

      # góp quỹ đủ 10.000 thì lên cấp 2: thêm kinh nghiệm mỗi trận
      assert %{ok: false, msg: "Góp ít nhất 100 vàng."} =
               cmd(sa, %{"act" => "guild_donate", "amount" => 5})

      r = cmd(sa, %{"act" => "guild_donate", "amount" => 10_000})
      assert r.ok and r.player.gold == pa.gold - 5000 - 10_000
      assert %{level: 2} = Session.get(ua.id).guild

      # phó bang không đuổi được phó bang khác; bang chủ đuổi được
      assert {:ok, _} = gop(sa, "promote", %{"uid" => cid})
      assert {:error, %{msg: "Chỉ bang chủ làm được."}} = gop(sb, "promote", %{"uid" => cid})
      assert {:ok, %{guild: %{members: [_, _]}}} = gop(sa, "kick", %{"uid" => cid})
      assert_push "guild", %{guild: nil}

      # bang chủ phải chuyển quyền trước khi rời
      assert {:error, %{msg: "Chuyển quyền" <> _}} = gop(sa, "leave")
      {:ok, %{guild: %{members: [_ | _]}}} = gop(sb, "info")
      [ub_id] = HacLong.Guilds.member_ids(gid) -- [ua.id]
      assert {:ok, _} = gop(sa, "transfer", %{"uid" => ub_id})
      assert {:ok, %{guild: nil}} = gop(sa, "leave")
      assert {:ok, %{guild: nil, msg: "Đã giải tán" <> _}} = gop(sb, "disband")
      assert HacLong.Guilds.member_ids(gid) == []
    end

    test "danh sách bang và bảng xếp hạng bang" do
      {_u, _p, s} = member()
      tag = "L#{rem(System.unique_integer([:positive]), 1000)}"
      %{ok: true} = cmd(s, %{"act" => "guild_create", "name" => "Bang #{tag}", "tag" => tag})

      assert {:ok, %{guilds: [%{tag: ^tag, members: 1, level: 1}]}} =
               gop(s, "list", %{"q" => tag})

      ref = push(s, "leaderboard", %{})
      assert_reply ref, :ok, %{guild: guilds}
      assert Enum.any?(guilds, &(&1.tag == tag))
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

  test "người cùng bản đồ thấy đồ đang mặc và thú cưng của nhau" do
    ua = create_user()

    player_at(ua, %{map: "village", x: 12, y: 14}, %{
      gold: 10_000,
      level: 10,
      inv: %{"broadsword" => 1}
    })

    {_, sa} = join_game(ua)
    ub = create_user()
    player_at(ub, %{map: "village", x: 13, y: 14})
    {_, _sb} = join_game(ub)

    cmd(sa, %{"act" => "equip", "id" => "broadsword"})
    look = fn -> Enum.find(MapServer.snapshot("village").players, &(&1.id == ua.id)).look end
    assert look.().weapon == "hand1/broadsword"

    # dắt thú: phải mua ở Người Nuôi Thú trước
    assert %{ok: false, msg: "Hãy đến gặp Người Nuôi Thú ở Làng."} =
             cmd(sa, %{"act" => "pet_buy", "id" => "sheep"})

    p = Session.get(ua.id)
    {_, p} = HacLong.Game.Pets.buy(p, "sheep")
    Characters.save!(ua.id, p)
    [{pid, _}] = Registry.lookup(HacLong.Game.Registry, ua.id)
    DynamicSupervisor.terminate_child(HacLong.Game.SessionSupervisor, pid)
    {_, sa} = join_game(ua)
    cmd(sa, %{"act" => "pet_choose", "id" => nil})
    assert look.().pet == nil
    cmd(sa, %{"act" => "pet_choose", "id" => "sheep"})
    assert look.().pet == "sheep"
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
