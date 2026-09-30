defmodule HacLongWeb.GameChannelTest do
  use HacLongWeb.ChannelCase

  alias HacLong.Accounts
  alias HacLong.Game.{Characters, Session}
  alias HacLongWeb.UserSocket

  defp join_game(user) do
    {:ok, socket} = connect(UserSocket, %{"token" => Accounts.sign_token(user)})
    {:ok, reply, socket} = subscribe_and_join(socket, "game", %{})
    {reply, socket}
  end

  defp cmd(socket, payload) do
    ref = push(socket, "cmd", payload)
    assert_reply ref, :ok, reply
    reply
  end

  test "từ chối kết nối khi token sai" do
    assert :error = connect(UserSocket, %{"token" => "sai"})
    assert :error = connect(UserSocket, %{})
  end

  test "tạo nhân vật, chiến đấu và lưu vào database" do
    user = create_user()
    {reply, socket} = join_game(user)
    assert reply.player == nil
    assert reply.username == user.username

    r = cmd(socket, %{"act" => "create", "name" => "Hiệp", "cls" => "knight"})
    assert r.ok and r.player.cls == "knight"
    assert Characters.load(user.id).name == "Hiệp"

    r = cmd(socket, %{"act" => "hunt", "zone" => 0})
    assert r.ok and r.player.battle.monster

    # đánh tới khi xong trận
    r =
      Enum.reduce_while(1..200, r, fn _, _ ->
        r = cmd(socket, %{"act" => "attack"})
        if r.player.battle.over, do: {:halt, r}, else: {:cont, r}
      end)

    assert r.player.battle.result in ~w(win lose)

    # trận đấu (kể cả nhật ký) được lưu và đọc lại đúng như trong bộ nhớ
    assert Characters.load(user.id) == r.player

    r = cmd(socket, %{"act" => "leave"})
    assert r.player.battle == nil
    assert Characters.load(user.id).battle == nil
  end

  test "trạng thái sống sót khi tiến trình session tắt và nạp lại từ database" do
    user = create_user()
    {_, socket} = join_game(user)
    cmd(socket, %{"act" => "create", "name" => "Bền", "cls" => "rogue"})
    r = cmd(socket, %{"act" => "hunt", "zone" => 0})

    [{pid, _}] = Registry.lookup(HacLong.Game.Registry, user.id)
    DynamicSupervisor.terminate_child(HacLong.Game.SessionSupervisor, pid)

    assert Session.get(user.id) == r.player
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
