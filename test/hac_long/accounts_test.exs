defmodule HacLong.AccountsTest do
  use HacLong.DataCase, async: true

  alias HacLong.Accounts

  test "đăng ký rồi đăng nhập, không phân biệt hoa thường" do
    assert {:ok, user} =
             Accounts.register(%{"username" => " LangKhach ", "password" => "matkhau1"})

    assert user.username == "langkhach"
    refute user.password_hash =~ "matkhau1"

    assert {:ok, _} = Accounts.authenticate("LANGKHACH", "matkhau1")
    assert {:error, :invalid} = Accounts.authenticate("langkhach", "sai")
    assert {:error, :invalid} = Accounts.authenticate("khongco", "matkhau1")
  end

  test "kiểm tra tên và mật khẩu" do
    assert {:error, cs} = Accounts.register(%{"username" => "ab", "password" => "123"})
    assert %{username: [_], password: [_]} = errors_on(cs)
    assert {:error, _} = Accounts.register(%{"username" => "có dấu", "password" => "matkhau1"})

    {:ok, _} = Accounts.register(%{"username" => "trung", "password" => "matkhau1"})
    assert {:error, cs} = Accounts.register(%{"username" => "TRUNG", "password" => "matkhau1"})
    assert %{username: ["đã có người dùng"]} = errors_on(cs)
  end

  test "token" do
    {:ok, user} = Accounts.register(%{"username" => "token1", "password" => "matkhau1"})
    token = Accounts.sign_token(user)
    assert {:ok, %{id: id}} = Accounts.verify_token(token)
    assert id == user.id
    assert {:error, :invalid} = Accounts.verify_token(token <> "x")
    assert {:error, :invalid} = Accounts.verify_token(nil)
  end
end
