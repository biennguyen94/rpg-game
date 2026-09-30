defmodule HacLong.Game.Names do
  @moduledoc """
  Tên nhân vật: 2–16 ký tự gồm chữ (có dấu), số, khoảng trắng, `-` và `_`.
  Hai tên trùng nhau nếu giống nhau sau khi bỏ khoảng trắng thừa và chuyển chữ thường
  (`key/1`); database có ràng buộc duy nhất trên khóa này.
  """

  @doc "Chuẩn hóa tên người chơi gõ: NFC, bỏ khoảng trắng đầu cuối và khoảng trắng thừa."
  def normalize(name) do
    name
    |> to_string()
    |> :unicode.characters_to_nfc_binary()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  def key(name), do: name |> normalize() |> String.downcase()

  @doc "`{:ok, tên_đã_chuẩn_hóa}` hoặc `{:error, lý_do}`."
  def validate(name) do
    name = normalize(name)
    len = String.length(name)

    cond do
      len < 2 or len > 16 ->
        {:error, "Tên nhân vật phải dài 2–16 ký tự."}

      not Regex.match?(~r/^[\p{L}\p{M}\p{N} _\-]+$/u, name) ->
        {:error, "Tên chỉ gồm chữ, số, khoảng trắng, - và _."}

      true ->
        {:ok, name}
    end
  end
end
