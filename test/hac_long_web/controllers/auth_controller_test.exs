defmodule HacLongWeb.AuthControllerTest do
  use HacLongWeb.ConnCase, async: true

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
