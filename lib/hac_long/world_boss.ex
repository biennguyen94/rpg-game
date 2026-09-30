defmodule HacLong.WorldBoss do
  @moduledoc """
  Trùm thế giới: Cổ Long Ba Đầu xuất hiện định kỳ ở Tế Đàn, cả server đánh chung một
  thanh máu.

  - Mỗi người vẫn đánh theo lượt như trận thường (trùm đánh trả từng người), nhưng sát
    thương gây ra được trừ vào thanh máu chung ở tiến trình này (`hit/3`).
  - Trùm gục: ai có gây sát thương đều được thưởng theo phần sát thương của mình (so với
    tổng máu trùm), 3 người gây nhiều nhất được thêm Vảy Cổ Long, người ra đòn cuối thêm
    vàng. Hết `duration_minutes` mà chưa hạ được thì trùm bay đi, không ai được thưởng.
  - Thưởng được gửi tới `HacLong.Game.Session` của từng người (tự khởi động nếu người đó
    đã rời game), nên không mất phần của ai.
  - Trạng thái (còn sống, máu, top sát thương) phát qua PubSub `"world_boss"`.

  Cấu hình `config :hac_long, :world_boss, every_minutes:, duration_minutes:, hp:,
  first_after_minutes:`; `every_minutes: nil` thì không tự xuất hiện (dùng `spawn_now/1`).
  """
  use GenServer

  alias HacLong.Chat
  alias HacLong.Game.{Engine, Session}

  @topic "world_boss"
  @flush_ms 300
  @spec_ %{
    id: "ancient_dragon",
    name: "Cổ Long Ba Đầu",
    level: 34,
    special: %{name: "Hơi Thở Ba Đầu", every: 4, mult: 2.2}
  }

  def topic, do: @topic
  def name, do: @spec_.name

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Trạng thái công khai: `%{alive, hp, maxHp, endsAt, nextAt, top}` (thời gian: ms)."
  def status, do: GenServer.call(__MODULE__, :status)

  @doc "Cho trùm xuất hiện ngay (thử nghiệm, quản trị). `hp:` để đổi lượng máu."
  def spawn_now(opts \\ []), do: GenServer.call(__MODULE__, {:spawn, opts})

  @doc "Cho trùm bay đi ngay (thử nghiệm, quản trị)."
  def despawn, do: GenServer.call(__MODULE__, :despawn)

  @doc "Bắt đầu đánh: `{:ok, quái}` (quái dùng cho trận của người này) hoặc `{:error, lý_do}`."
  def engage(uid), do: GenServer.call(__MODULE__, {:engage, uid})

  @doc "Máu hiện tại, hoặc nil nếu trùm không còn."
  def hp, do: GenServer.call(__MODULE__, :hp)

  @doc """
  Người `uid` gây `dmg` sát thương. Trả về `{:alive, máu_còn}`, `:killed` (đòn này hạ trùm)
  hoặc `:gone` (trùm đã gục hoặc bay đi trước đó).
  """
  def hit(uid, name, dmg), do: GenServer.call(__MODULE__, {:hit, uid, name, dmg})

  # ---------- Tiến trình ----------

  defp conf(key), do: Keyword.get(Application.get_env(:hac_long, :world_boss, []), key)

  @impl true
  def init(_) do
    s = %{boss: nil, next_at: nil, timer: nil, flush: false}
    {:ok, schedule(s, conf(:first_after_minutes))}
  end

  defp schedule(s, nil), do: %{s | next_at: nil}

  defp schedule(s, minutes) do
    ms = round(minutes * 60_000)
    ref = Process.send_after(self(), :spawn, ms)
    %{s | next_at: now() + ms, timer: ref}
  end

  defp now, do: System.system_time(:millisecond)

  @impl true
  def handle_call(:status, _from, s), do: {:reply, public(s), s}
  def handle_call(:hp, _from, s), do: {:reply, s.boss && s.boss.hp, s}

  def handle_call({:spawn, opts}, _from, s) do
    s = if s.boss, do: s, else: spawn_boss(s, opts)
    {:reply, public(s), s}
  end

  def handle_call(:despawn, _from, %{boss: nil} = s), do: {:reply, :ok, s}
  def handle_call(:despawn, _from, s), do: {:reply, :ok, finish(s, :escaped)}

  def handle_call({:engage, _uid}, _from, %{boss: nil} = s),
    do: {:reply, {:error, "#{@spec_.name} chưa xuất hiện."}, s}

  def handle_call({:engage, uid}, _from, s) do
    b = s.boss
    m = Engine.make_monster(@spec_, false)

    monster =
      Map.merge(m, %{maxHp: b.max_hp, hp: b.hp, xp: 0, gold: 0, world: true})

    s = put_in(s.boss.fighters, MapSet.put(b.fighters, uid))
    {:reply, {:ok, monster}, s}
  end

  def handle_call({:hit, _uid, _name, _dmg}, _from, %{boss: nil} = s), do: {:reply, :gone, s}

  def handle_call({:hit, uid, name, dmg}, _from, s) when is_integer(dmg) and dmg > 0 do
    b = s.boss
    dmg = min(dmg, b.hp)

    damage =
      Map.update(b.damage, uid, %{name: name, dmg: dmg}, &%{&1 | dmg: &1.dmg + dmg, name: name})

    b = %{b | hp: b.hp - dmg, damage: damage, fighters: MapSet.put(b.fighters, uid)}

    if b.hp <= 0 do
      {:reply, :killed, finish(%{s | boss: b}, {:killed, uid})}
    else
      {:reply, {:alive, b.hp}, changed(%{s | boss: b})}
    end
  end

  def handle_call({:hit, _uid, _name, _dmg}, _from, s), do: {:reply, {:alive, s.boss.hp}, s}

  @impl true
  def handle_info(:spawn, s), do: {:noreply, if(s.boss, do: s, else: spawn_boss(s, []))}

  def handle_info({:escape, id}, %{boss: %{id: id}} = s), do: {:noreply, finish(s, :escaped)}
  def handle_info({:escape, _}, s), do: {:noreply, s}

  def handle_info(:flush, s) do
    Phoenix.PubSub.broadcast(HacLong.PubSub, @topic, {:world_boss, public(s)})
    {:noreply, %{s | flush: false}}
  end

  # ---------- Nội bộ ----------

  defp spawn_boss(s, opts) do
    if s.timer, do: Process.cancel_timer(s.timer)
    hp = opts[:hp] || conf(:hp) || 20_000
    minutes = conf(:duration_minutes) || 30
    id = System.unique_integer([:positive])
    Process.send_after(self(), {:escape, id}, minutes * 60_000)

    boss = %{
      id: id,
      hp: hp,
      max_hp: hp,
      ends_at: now() + minutes * 60_000,
      damage: %{},
      fighters: MapSet.new()
    }

    Chat.system(
      "⚔️ #{@spec_.name} đã xuất hiện ở Tế Đàn (cổng phía dưới bên trái Làng)! Cả server cùng đánh, #{minutes} phút."
    )

    changed(%{s | boss: boss, next_at: nil, timer: nil})
  end

  defp finish(s, outcome) do
    b = s.boss

    top =
      b.damage |> Enum.sort_by(fn {_, d} -> -d.dmg end) |> Enum.take(3) |> Enum.map(&elem(&1, 0))

    for uid <- MapSet.to_list(b.fighters) do
      info =
        case outcome do
          {:killed, killer} ->
            case b.damage[uid] do
              nil -> %{result: "win", reward: nil}
              d -> %{result: "win", reward: reward(d.dmg, b.max_hp, uid in top, uid == killer)}
            end

          :escaped ->
            %{result: "fled", reward: nil}
        end

      # không chờ: Session của người này có thể đang gọi sang đây
      Task.start(fn -> Session.world_boss_end(uid, info) end)
    end

    case outcome do
      {:killed, killer} ->
        who = b.damage[killer].name
        best = top |> Enum.map(&b.damage[&1].name) |> Enum.join(", ")

        Chat.system(
          "🏆 #{@spec_.name} đã gục ngã! Đòn cuối: #{who}. Gây nhiều sát thương nhất: #{best}."
        )

      :escaped ->
        Chat.system("#{@spec_.name} đã bay đi. Hẹn lần sau!")
    end

    s = %{s | boss: nil} |> schedule(conf(:every_minutes))
    changed(s)
  end

  # Phần thưởng theo tỷ lệ sát thương trên tổng máu trùm.
  defp reward(dmg, max_hp, top?, killer?) do
    share = dmg / max_hp

    %{
      gold: round(300 + 5000 * share) + if(killer?, do: 500, else: 0),
      xp: round(1000 + 30_000 * share),
      items: if(top?, do: %{"dragon_scale" => 1}, else: %{}),
      share: Float.round(share * 100, 1)
    }
  end

  defp changed(%{flush: true} = s), do: s

  defp changed(s) do
    Process.send_after(self(), :flush, @flush_ms)
    %{s | flush: true}
  end

  defp public(%{boss: nil} = s),
    do: %{alive: false, name: @spec_.name, nextAt: s.next_at, now: now()}

  defp public(%{boss: b}) do
    top =
      b.damage
      |> Enum.sort_by(fn {_, d} -> -d.dmg end)
      |> Enum.take(5)
      |> Enum.map(fn {uid, d} -> %{id: uid, name: d.name, dmg: d.dmg} end)

    %{
      alive: true,
      name: @spec_.name,
      hp: b.hp,
      maxHp: b.max_hp,
      endsAt: b.ends_at,
      now: now(),
      fighters: MapSet.size(b.fighters),
      top: top
    }
  end
end
