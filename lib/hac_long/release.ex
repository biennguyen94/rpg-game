defmodule HacLong.Release do
  @moduledoc """
  Việc chạy trong bản release (không có `mix`), vd. trong container Docker:

      bin/hac_long eval "HacLong.Release.migrate()"
      bin/hac_long eval 'HacLong.Release.admin("ten_dang_nhap")'

  `rel/overlays/bin/start` gọi `migrate/0` rồi mới khởi động server.
  """
  @app :hac_long

  @doc "Chạy các migration còn thiếu."
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc "Cấp (hoặc thu hồi với `false`) quyền quản trị cho tài khoản `username`."
  def admin(username, admin? \\ true) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(HacLong.Repo, fn _ ->
        case HacLong.Moderation.set_admin(username, admin?) do
          {:ok, _} ->
            IO.puts("Đã #{if admin?, do: "cấp", else: "thu hồi"} quyền quản trị: #{username}")

          {:error, msg} when is_binary(msg) ->
            IO.puts("Lỗi: " <> msg)

          {:error, other} ->
            IO.puts("Lỗi: #{inspect(other)}")
        end
      end)
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
