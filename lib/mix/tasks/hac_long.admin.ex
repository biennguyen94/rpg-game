defmodule Mix.Tasks.HacLong.Admin do
  @shortdoc "Cấp hoặc thu quyền quản trị cho một tài khoản"
  @moduledoc """
  Cấp quyền quản trị (thấy tab Quản trị trong game):

      mix hac_long.admin ten_dang_nhap
      mix hac_long.admin ten_dang_nhap --revoke

  Người đó đăng nhập lại (hoặc tải lại trang) để thấy tab. Khi chạy bản release:
  `bin/hac_long eval 'HacLong.Moderation.set_admin("ten_dang_nhap", true)'`.
  """
  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, names, _} = OptionParser.parse(args, strict: [revoke: :boolean])

    case names do
      [name] ->
        admin? = !opts[:revoke]

        case HacLong.Moderation.set_admin(name, admin?) do
          {:ok, u} ->
            Mix.shell().info(
              "#{u.username}: #{if admin?, do: "đã cấp", else: "đã thu"} quyền quản trị."
            )

          {:error, msg} ->
            Mix.raise(msg)
        end

      _ ->
        Mix.raise("Cách dùng: mix hac_long.admin TEN_DANG_NHAP [--revoke]")
    end
  end
end
