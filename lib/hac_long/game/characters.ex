defmodule HacLong.Game.Characters do
  @moduledoc """
  Đọc/ghi nhân vật trong PostgreSQL và chuyển qua lại giữa dòng trong bảng
  và map trạng thái mà `HacLong.Game.Engine` dùng.
  """

  import Ecto.Query
  alias HacLong.Repo
  alias HacLong.Game.{Character, Names}
  alias HacLong.World
  alias HacLong.World.Maps

  @save_version 1

  def load(user_id) do
    case Repo.get_by(Character, user_id: user_id) do
      nil -> nil
      c -> to_player(c)
    end
  end

  @doc "Ghi đè toàn bộ trạng thái nhân vật (tạo mới nếu chưa có)."
  def save!(user_id, player) do
    attrs =
      player
      |> Map.merge(%{
        map_id: player.pos.map,
        x: player.pos.x,
        y: player.pos.y,
        name_key: Names.key(player.name)
      })
      |> Map.take(Character.fields())

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(
      struct(Character, Map.merge(attrs, %{user_id: user_id, inserted_at: now, updated_at: now})),
      on_conflict: {:replace, Character.fields() ++ [:updated_at]},
      conflict_target: :user_id
    )

    :ok
  end

  @doc "Tên đã có người khác dùng chưa (không phân biệt hoa thường)."
  def name_taken?(name) do
    Repo.exists?(from c in Character, where: c.name_key == ^Names.key(name))
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
      battle: c.battle && atomize(c.battle),
      pos: pos(c),
      waystones: Enum.filter(c.waystones || [], &(&1 in Maps.waystone_ids())),
      quests: quests(c.quests),
      victory_at: c.victory_at,
      daily: daily(c.daily),
      tower: tower(c.tower),
      tower_best: c.tower_best || 0,
      tutorial: c.tutorial,
      upgrades:
        Map.filter(c.upgrades || %{}, fn {id, _} ->
          HacLong.Game.Data.item(id) || HacLong.Game.Gear.instance?(id)
        end),
      fish_caught: c.fish_caught || 0,
      achievements: c.achievements || [],
      title: c.title,
      gear: HacLong.Game.Gear.load(c.gear),
      bestiary: c.bestiary || %{},
      rebirths: c.rebirths || 0
    }
  end

  # Bỏ nhiệm vụ không còn trong dữ liệu game (đổi tên, xóa bớt).
  defp quests(%{"active" => active, "done" => done}) do
    known = MapSet.new(Enum.map(HacLong.Game.Data.quests(), & &1.id))

    %{
      active: Map.filter(active, fn {id, _} -> id in known end),
      done: Enum.filter(done, &(&1 in known))
    }
  end

  defp quests(_), do: HacLong.Game.Quests.empty()

  defp daily(%{"date" => date, "tasks" => tasks}) do
    %{
      date: date,
      tasks:
        Enum.map(tasks, fn t ->
          %{
            kind: t["kind"],
            target: t["target"],
            zone: t["zone"],
            count: t["count"],
            progress: t["progress"],
            claimed: t["claimed"],
            name: t["name"],
            reward: %{gold: t["reward"]["gold"], xp: t["reward"]["xp"]}
          }
        end)
    }
  end

  defp daily(_), do: nil

  # Trong tháp thì giữ vị trí (tầng tháp không có trong priv/maps nên valid_pos không biết).
  defp pos(%Character{map_id: "tower", tower: %{}, x: x, y: y}), do: %{map: "tower", x: x, y: y}

  defp pos(%Character{map_id: "tower"}), do: HacLong.World.Maps.home_spawn()

  defp pos(c), do: World.valid_pos(%{map: c.map_id, x: c.x, y: c.y})

  defp tower(%{"floor" => floor} = t) do
    %{
      floor: floor,
      tiles: t["tiles"],
      stairs: t["stairs"],
      exit: t["exit"],
      monsters:
        Enum.map(t["monsters"], fn m ->
          %{
            id: m["id"],
            kind: m["kind"],
            name: m["name"],
            level: m["level"],
            x: m["x"],
            y: m["y"],
            elite: m["elite"]
          }
        end)
    }
  end

  defp tower(_), do: nil

  # Tên các trường có trong trận đấu (trận, quái, nhật ký, phần thưởng).
  @battle_keys Map.new(
                 ~w(zone monster turn skillCd cds effects player turns power on_hit effect chance
                    log over result reward encounter map mid world world_boss tower elite
                    id name level boss final special maxHp atk def crit dodge xp gold hp
                    every mult text kind items levels gear night)a,
                 &{Atom.to_string(&1), &1}
               )

  defp atomize(m) when is_map(m),
    do: Map.new(m, fn {k, v} -> {Map.fetch!(@battle_keys, k), atomize(v)} end)

  defp atomize(l) when is_list(l), do: Enum.map(l, &atomize/1)
  defp atomize(v), do: v
end
