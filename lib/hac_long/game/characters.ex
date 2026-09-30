defmodule HacLong.Game.Characters do
  @moduledoc """
  Đọc/ghi nhân vật trong PostgreSQL và chuyển qua lại giữa dòng trong bảng
  và map trạng thái mà `HacLong.Game.Engine` dùng.
  """

  import Ecto.Query
  alias HacLong.Repo
  alias HacLong.Game.Character

  @save_version 1

  def load(user_id) do
    case Repo.get_by(Character, user_id: user_id) do
      nil -> nil
      c -> to_player(c)
    end
  end

  @doc "Ghi đè toàn bộ trạng thái nhân vật (tạo mới nếu chưa có)."
  def save!(user_id, player) do
    attrs = Map.take(player, Character.fields())
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(
      struct(Character, Map.merge(attrs, %{user_id: user_id, inserted_at: now, updated_at: now})),
      on_conflict: {:replace, Character.fields() ++ [:updated_at]},
      conflict_target: :user_id
    )

    :ok
  end

  def delete!(user_id) do
    Repo.delete_all(from c in Character, where: c.user_id == ^user_id)
    :ok
  end

  # Cột kiểu map được Postgres trả về với khóa chuỗi; đổi lại thành atom như engine dùng.
  defp to_player(%Character{} = c) do
    %{
      version: @save_version,
      name: c.name,
      cls: c.cls,
      level: c.level,
      xp: c.xp,
      gold: c.gold,
      hp: c.hp,
      points: c.points,
      stats: Map.new(~w(str vit agi def)a, &{&1, Map.fetch!(c.stats, Atom.to_string(&1))}),
      equip: Map.new(~w(weapon armor shield)a, &{&1, Map.get(c.equip, Atom.to_string(&1))}),
      inv: c.inv,
      bosses: c.bosses,
      kills: c.kills,
      deaths: c.deaths,
      victory: c.victory,
      battle: c.battle && atomize(c.battle)
    }
  end

  # Tên các trường có trong trận đấu (trận, quái, nhật ký, phần thưởng).
  @battle_keys Map.new(
                 ~w(zone monster turn skillCd log over result reward
                    id name level boss final special maxHp atk def crit dodge xp gold hp
                    every mult text kind items levels)a,
                 &{Atom.to_string(&1), &1}
               )

  defp atomize(m) when is_map(m),
    do: Map.new(m, fn {k, v} -> {Map.fetch!(@battle_keys, k), atomize(v)} end)

  defp atomize(l) when is_list(l), do: Enum.map(l, &atomize/1)
  defp atomize(v), do: v
end
