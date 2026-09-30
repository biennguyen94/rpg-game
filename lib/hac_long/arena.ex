defmodule HacLong.Arena do
  @moduledoc """
  Đấu trường (PvP bất đồng bộ): đánh với bản sao chỉ số của người chơi khác, người đó không
  cần online.

  - Bản sao dựng từ nhân vật đã lưu của đối thủ (`opponent/1`): máu, tấn công, phòng thủ, chí
    mạng, né như lúc họ mặc đồ; dùng kỹ năng đầu của lớp như đòn đặc biệt mỗi 3 lượt.
  - Thắng/thua đổi điểm Elo của cả hai (`finish/3`, K = 32). Thua không mất vàng, không về
    Nhà, máu trở lại như trước trận. Người thắng (người thách đấu) được một ít vàng.
  - Mỗi ngày (giờ Việt Nam) đấu tối đa `@per_day` trận.
  """
  import Ecto.Query

  alias HacLong.Repo
  alias HacLong.Game.{Character, Characters, Daily, Data, Engine}

  @per_day 15
  @k 32

  def per_day, do: @per_day

  # ---------- Điểm ----------

  @doc "Điểm của người chơi: `%{rating, wins, losses, today}` (chưa đấu trận nào thì 1000)."
  def stats(uid) do
    today = Daily.today()

    case Repo.one(
           from r in "pvp",
             where: r.user_id == ^uid,
             select: map(r, [:rating, :wins, :losses, :day, :today])
         ) do
      nil ->
        %{rating: 1000, wins: 0, losses: 0, today: 0}

      r ->
        %{
          rating: r.rating,
          wins: r.wins,
          losses: r.losses,
          today: if(r.day == today, do: r.today, else: 0)
        }
    end
  end

  defp ensure(uid) do
    Repo.insert_all("pvp", [%{user_id: uid}], on_conflict: :nothing)
  end

  @doc "Điểm Elo thay đổi của người có điểm `a` khi đấu với người có điểm `b`."
  def delta(a, b, won?) do
    expected = 1 / (1 + :math.pow(10, (b - a) / 400))
    round(@k * (if(won?, do: 1, else: 0) - expected))
  end

  # ---------- Thách đấu ----------

  @doc """
  Kiểm tra được thách đấu `target` không, và dựng quái-bản-sao của đối thủ.
  Trả về `{:ok, quái}` hoặc `{:error, lý_do}`.
  """
  def challenge(uid, target) do
    s = stats(uid)
    opp = is_integer(target) && target != uid && Characters.load(target)

    cond do
      target == uid -> {:error, "Không tự thách đấu mình được."}
      !opp -> {:error, "Không tìm thấy đối thủ."}
      s.today >= @per_day -> {:error, "Hôm nay đã đấu đủ #{@per_day} trận. Mai quay lại nhé."}
      true -> {:ok, opponent(opp, target)}
    end
  end

  @doc "Bản sao chỉ số của nhân vật `p` dùng làm đối thủ trong trận."
  def opponent(p, uid) do
    d = Engine.derived(p)
    skill = hd(Data.class(p.cls).skills)

    %{
      id: "hero",
      name: p.name,
      level: p.level,
      boss: false,
      final: false,
      special: %{name: skill.name, every: 3, mult: 1.8},
      on_hit: nil,
      maxHp: d.maxHp,
      hp: d.maxHp,
      atk: d.atk,
      def: d.def,
      crit: d.crit,
      dodge: d.dodge,
      xp: 0,
      gold: 0,
      pvp: uid,
      look: Engine.look(p)
    }
  end

  @doc """
  Trận với `target` vừa xong (`result`: "win" | "lose" | "fled"). Cập nhật điểm hai bên.
  Trả về `%{won, delta, gold}` (vàng thưởng cho người thách đấu nếu thắng).
  """
  def finish(uid, target, result) do
    won? = result == "win"
    me = stats(uid)
    them = stats(target)
    dm = delta(me.rating, them.rating, won?)
    dt = delta(them.rating, me.rating, not won?)
    today = Daily.today()

    Repo.transaction(fn ->
      ensure(uid)
      ensure(target)

      Repo.update_all(from(r in "pvp", where: r.user_id == ^uid),
        set: [rating: max(0, me.rating + dm), day: today, today: me.today + 1],
        inc: [wins: if(won?, do: 1, else: 0), losses: if(won?, do: 0, else: 1)]
      )

      Repo.update_all(from(r in "pvp", where: r.user_id == ^target),
        set: [rating: max(0, them.rating + dt)],
        inc: [wins: if(won?, do: 0, else: 1), losses: if(won?, do: 1, else: 0)]
      )
    end)

    %{won: won?, delta: dm, their_delta: dt, gold: if(won?, do: 30 + 5 * max(0, dm), else: 0)}
  end

  # ---------- Danh sách ----------

  @doc "Đối thủ gợi ý: những người có điểm gần mình nhất (trừ mình)."
  def suggestions(uid, n \\ 5) do
    me = stats(uid).rating

    from(c in Character,
      left_join: r in "pvp",
      on: r.user_id == c.user_id,
      where: c.user_id != ^uid,
      order_by: [asc: fragment("abs(coalesce(?, 1000) - ?)", r.rating, ^me), desc: c.level],
      limit: ^n,
      select: %{
        user_id: c.user_id,
        name: c.name,
        cls: c.cls,
        level: c.level,
        rating: coalesce(r.rating, 1000)
      }
    )
    |> Repo.all()
  end

  @doc "Bảng xếp hạng đấu trường."
  def top(n \\ 10) do
    from(r in "pvp",
      join: c in Character,
      on: c.user_id == r.user_id,
      where: r.wins + r.losses > 0,
      order_by: [desc: r.rating, desc: r.wins],
      limit: ^n,
      select: %{
        user_id: c.user_id,
        name: c.name,
        cls: c.cls,
        level: c.level,
        rating: r.rating,
        wins: r.wins,
        losses: r.losses
      }
    )
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {row, i} -> Map.put(row, :rank, i) end)
  end
end
