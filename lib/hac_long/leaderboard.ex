defmodule HacLong.Leaderboard do
  @moduledoc """
  Bảng xếp hạng, đọc thẳng từ bảng `characters` (có chỉ mục cho từng kiểu xếp).

  - `:level`: cấp cao nhất (bằng cấp thì ai nhiều kinh nghiệm hơn xếp trên).
  - `:kills`: hạ nhiều quái nhất.
  - `:dragon`: những người đã hạ Hắc Long, ai hạ trước xếp trên.
  - `:tower`: tầng cao nhất đã vượt ở Tháp Vô Tận.
  """
  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.Game.Character

  @kinds [:level, :kills, :dragon, :tower]

  def kinds, do: @kinds

  def top(kind, n \\ 10) when kind in @kinds do
    kind
    |> query()
    |> limit(^n)
    |> select([c], %{
      user_id: c.user_id,
      name: c.name,
      cls: c.cls,
      level: c.level,
      kills: c.kills,
      victory_at: c.victory_at,
      tower_best: c.tower_best
    })
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {row, i} -> Map.put(row, :rank, i) end)
  end

  defp query(:level), do: from(c in Character, order_by: [desc: c.level, desc: c.xp, asc: c.id])
  defp query(:kills), do: from(c in Character, order_by: [desc: c.kills, asc: c.id])

  defp query(:tower),
    do: from(c in Character, where: c.tower_best > 0, order_by: [desc: c.tower_best, asc: c.id])

  defp query(:dragon),
    do:
      from(c in Character,
        where: not is_nil(c.victory_at),
        order_by: [asc: c.victory_at, asc: c.id]
      )

  @doc "Hạng theo cấp của nhân vật thuộc `user_id` (nil nếu chưa có nhân vật)."
  def level_rank(user_id) do
    case Repo.one(
           from c in Character, where: c.user_id == ^user_id, select: {c.level, c.xp, c.id}
         ) do
      nil ->
        nil

      {lv, xp, id} ->
        Repo.one(
          from c in Character,
            where:
              c.level > ^lv or (c.level == ^lv and c.xp > ^xp) or
                (c.level == ^lv and c.xp == ^xp and c.id < ^id),
            select: count()
        ) + 1
    end
  end
end
