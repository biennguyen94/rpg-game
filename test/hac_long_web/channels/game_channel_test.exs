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
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Hiệp", "cls" => "knight"})
    p = p |> Map.merge(attrs) |> Map.put(:pos, pos)
    Characters.save!(user.id, p)
    p
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
    assert Characters.load(user.id).name == "Hiệp"

    # bước xuống cửa nhà thì ra Làng
    r = cmd(socket, %{"act" => "move", "dir" => "down"})
    assert r.ok and r.player.pos == %{map: "village", x: 12, y: 15}
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
