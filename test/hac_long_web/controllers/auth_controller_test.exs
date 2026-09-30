defmodule HacLongWeb.AuthControllerTest do
  # Bộ đếm giới hạn tần suất dùng chung nên không chạy song song.
  use HacLongWeb.ConnCase, async: false

  setup do
    HacLong.RateLimit.reset()
    :ok
  end

  defp api(method, path, body \\ %{}, token \\ nil) do
    conn = build_conn()
    conn = if token, do: put_req_header(conn, "authorization", "Bearer " <> token), else: conn
    conn = dispatch(conn, @endpoint, method, path, body)
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  defp new_account(name) do
    {201, %{"token" => t}} = api(:post, "/api/register", %{username: name, password: "matkhau1"})
    t
  end

  test "đăng xuất thu hồi đúng token của thiết bị đó" do
    t1 = new_account("haithietbi")

    {200, %{"token" => t2}} =
      api(:post, "/api/login", %{username: "haithietbi", password: "matkhau1"})

    assert {200, _} = api(:post, "/api/logout", %{}, t1)
    assert {401, _} = api(:get, "/api/me", %{}, t1)
    assert {200, _} = api(:get, "/api/me", %{}, t2)

    # kết nối game (UserSocket) cũng kiểm tra token bằng hàm này
    assert {:error, :invalid} = HacLong.Accounts.verify_token(t1)
  end

  test "đăng xuất mọi thiết bị" do
    t1 = new_account("moithietbi")

    {200, %{"token" => t2}} =
      api(:post, "/api/login", %{username: "moithietbi", password: "matkhau1"})

    assert {200, _} = api(:post, "/api/logout_all", %{}, t2)
    assert {401, _} = api(:get, "/api/me", %{}, t1)
    assert {401, _} = api(:get, "/api/me", %{}, t2)
  end

  test "đổi mật khẩu: kiểm tra mật khẩu cũ, thiết bị khác bị đăng xuất" do
    t1 = new_account("doimatkhau")

    {200, %{"token" => t2}} =
      api(:post, "/api/login", %{username: "doimatkhau", password: "matkhau1"})

    assert {401, %{"error" => "Mật khẩu hiện tại không đúng."}} =
             api(:post, "/api/password", %{current: "sai", password: "moi123456"}, t1)

    assert {422, %{"error" => "Mật khẩu phải dài 6–72 ký tự."}} =
             api(:post, "/api/password", %{current: "matkhau1", password: "123"}, t1)

    assert {200, %{"token" => t3}} =
             api(:post, "/api/password", %{current: "matkhau1", password: "moi123456"}, t1)

    assert {401, _} = api(:get, "/api/me", %{}, t1)
    assert {401, _} = api(:get, "/api/me", %{}, t2)
    assert {200, _} = api(:get, "/api/me", %{}, t3)
    assert {401, _} = api(:post, "/api/login", %{username: "doimatkhau", password: "matkhau1"})
    assert {200, _} = api(:post, "/api/login", %{username: "doimatkhau", password: "moi123456"})
  end

  test "dò mật khẩu một tài khoản bị chặn sau 10 lần trong 5 phút" do
    new_account("bido")

    for _ <- 1..10,
        do: assert({401, _} = api(:post, "/api/login", %{username: "bido", password: "sai"}))

    assert {429, %{"error" => msg}} =
             api(:post, "/api/login", %{username: "BiDo", password: "matkhau1"})

    assert msg =~ "Thử quá nhiều lần"
    # tài khoản khác vẫn đăng nhập bình thường
    new_account("khongbido")
    assert {200, _} = api(:post, "/api/login", %{username: "khongbido", password: "matkhau1"})
  end

  test "một địa chỉ IP chỉ tạo được 5 tài khoản mỗi giờ" do
    for i <- 1..5, do: new_account("nick#{i}")
    assert {429, _} = api(:post, "/api/register", %{username: "nick6", password: "matkhau1"})
  end

  test "đăng ký, đăng nhập, /api/me", %{conn: conn} do
    r =
      conn
      |> post("/api/register", %{username: "Anh_Hung", password: "matkhau1"})
      |> json_response(201)

    assert r["username"] == "anh_hung" and is_binary(r["token"])

    r =
      build_conn()
      |> post("/api/login", %{username: "anh_hung", password: "matkhau1"})
      |> json_response(200)

    me =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> r["token"])
      |> get("/api/me")
      |> json_response(200)

    assert me == %{"username" => "anh_hung"}
  end

  test "lỗi đăng ký, sai mật khẩu, token hỏng", %{conn: conn} do
    r =
      conn |> post("/api/register", %{username: "a", password: "matkhau1"}) |> json_response(422)

    assert r["error"] =~ "Tên đăng nhập"

    build_conn() |> post("/api/register", %{username: "dunghoa", password: "matkhau1"})

    assert build_conn()
           |> post("/api/login", %{username: "dunghoa", password: "x"})
           |> json_response(401)

    assert build_conn() |> post("/api/login", %{}) |> json_response(401)

    assert build_conn()
           |> put_req_header("authorization", "Bearer x")
           |> get("/api/me")
           |> json_response(401)
  end

  test "trang chủ trả về giao diện kèm dữ liệu game", %{conn: conn} do
    html = conn |> get("/") |> html_response(200)
    assert html =~ ~s(<script src="js/net.js"></script>)
    assert html =~ "/vendor/phoenix.js"
    assert html =~ "window.GAME_DATA = "
    assert html =~ ~s("maxLevel":50)
    refute html =~ "<!--GAME_DATA-->"
    assert build_conn() |> get("/js/ui.js") |> response(200) =~ "GAME_DATA"
    assert build_conn() |> get("/vendor/phoenix.js") |> response(200)
    assert build_conn() |> get("/assets/monsters/hero.png") |> response(200)
  end

  test "không lộ file ngoài js/, css/, assets/" do
    for path <-
          ~w(/mix.exs /config/dev.exs /.git/config /README.md /js/../../mix.exs /game_data.json /repo/seeds.exs) do
      status =
        try do
          get(build_conn(), path).status
        rescue
          e -> Plug.Exception.status(e)
        end

      assert status in [400, 404], "#{path} trả về #{status}"
    end
  end
end
