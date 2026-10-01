defmodule HacLong.Homes do
  @moduledoc """
  Thăm nhà người khác: xem nhà đã trang trí (chỉ xem, không đi vào bản đồ của họ) và
  "khen nhà". Mỗi người khen nhà của một người khác tối đa một lần; chủ nhà được báo.
  """
  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.Game.{Engine, Home, Session}

  @doc "Số lượt khen nhà của `owner`."
  def likes(owner) do
    Repo.one(from l in "home_likes", where: l.owner_id == ^owner, select: count()) || 0
  end

  def liked?(owner, liker) do
    Repo.exists?(from l in "home_likes", where: l.owner_id == ^owner and l.liker_id == ^liker)
  end

  @doc "Những gì khách thấy khi ghé nhà `p` (nhân vật của `owner`)."
  def view(p, owner, viewer) do
    %{
      id: owner,
      name: p.name,
      look: Engine.look(p),
      decor: Home.decor(p),
      comfort: Home.comfort(p),
      likes: likes(owner),
      liked: owner == viewer or liked?(owner, viewer)
    }
  end

  @doc "`liker` (tên `name`) khen nhà `owner`. Trả về `{:ok, số_lượt_khen}` hoặc `{:error, lý_do}`."
  def like(owner, liker, name) do
    if owner == liker,
      do: {:error, "Không tự khen nhà mình được."},
      else: insert(owner, liker, name)
  end

  defp insert(owner, liker, name) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.insert_all(
           "home_likes",
           [%{owner_id: owner, liker_id: liker, inserted_at: now}],
           on_conflict: :nothing
         ) do
      {1, _} ->
        Phoenix.PubSub.broadcast(
          HacLong.PubSub,
          Session.topic(owner),
          {:notice, "🏡 #{name} vừa ghé thăm và khen nhà bạn đẹp!"}
        )

        {:ok, likes(owner)}

      {0, _} ->
        {:error, "Bạn đã khen nhà này rồi."}
    end
  end
end
