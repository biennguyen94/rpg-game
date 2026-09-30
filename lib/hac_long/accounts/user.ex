defmodule HacLong.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    timestamps(type: :utc_datetime)
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password])
    |> update_change(:username, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:username, :password], message: "không được để trống")
    |> validate_length(:username, min: 3, max: 20, message: "phải dài 3–20 ký tự")
    |> validate_format(:username, ~r/^[a-z0-9_]+$/,
      message: "chỉ gồm chữ không dấu, số và dấu gạch dưới"
    )
    |> validate_length(:password, min: 6, max: 72, message: "phải dài 6–72 ký tự")
    |> unique_constraint(:username, message: "đã có người dùng")
    |> hash_password()
  end

  defp hash_password(%{valid?: true, changes: %{password: pw}} = cs) do
    cs |> put_change(:password_hash, Pbkdf2.hash_pwd_salt(pw)) |> delete_change(:password)
  end

  defp hash_password(cs), do: cs
end
