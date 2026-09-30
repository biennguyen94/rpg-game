defmodule HacLong.Game.Daily do
  @moduledoc """
  Việc hằng ngày ở Bảng Tin trong Làng. Hàm thuần, như `Engine`.

  Mỗi ngày (theo giờ Việt Nam) mỗi nhân vật có 3 việc, chọn ngẫu nhiên nhưng cố định trong
  ngày (theo tên nhân vật và ngày), lấy từ hai vùng cao nhất đã mở:

  - `kill`: hạ N con một loại quái;
  - `zone`: hạ N quái bất kỳ ở một vùng;
  - `gather`: hái/đào N một loại nguyên liệu.

  Việc tự nhận, không cần đến Bảng Tin; làm xong thì đến Bảng Tin nhận thưởng.
  Trạng thái trong nhân vật: `daily: %{date: "2026-10-01", tasks: [...]}`.
  """

  alias HacLong.Game.{Data, Engine}

  # giờ Việt Nam: việc mới lúc 0 giờ
  @utc_offset 7 * 3600

  def today(now \\ DateTime.utc_now()),
    do: now |> DateTime.add(@utc_offset, :second) |> DateTime.to_date() |> Date.to_iso8601()

  @doc "Giây còn lại tới lúc có việc mới."
  def seconds_left(now \\ DateTime.utc_now()) do
    local = DateTime.add(now, @utc_offset, :second)
    86_400 - (local.hour * 3600 + local.minute * 60 + local.second)
  end

  @doc "Đổi sang việc của ngày `date` nếu đang giữ việc của ngày khác."
  def ensure(nil, _date), do: nil
  def ensure(%{daily: %{date: date}} = p, date), do: p
  def ensure(p, date), do: Map.put(p, :daily, %{date: date, tasks: generate(p, date)})

  def generate(p, date) do
    <<a::32, b::32, c::32, _::binary>> = :crypto.hash(:sha256, "#{p.name}|#{date}")
    rng = :rand.seed_s(:exsss, {a, b, c})

    top = Enum.filter(0..(Data.zone_count() - 1), &Engine.zone_unlocked?(p, &1)) |> List.last()
    zones = Enum.uniq([top, max(top - 1, 0)])

    {zk, rng} = pick(zones, rng)
    {monster, rng} = pick(Data.zone(zk).monsters, rng)
    {nk, rng} = range(6, 10, rng)
    {zz, rng} = pick(zones, rng)
    {nz, rng} = range(12, 16, rng)
    {zg, rng} = pick(zones, rng)
    {item, rng} = pick(if(zg < 3, do: ~w(herb ore), else: ~w(herb_rare ore_rare)), rng)
    {ng, _rng} = range(4, 6, rng)

    [
      task("kill", monster.id, zk, nk, "Hạ #{nk} #{monster.name}"),
      task("zone", nil, zz, nz, "Hạ #{nz} quái ở #{Data.zone(zz).name}"),
      task(
        "gather",
        item,
        zg,
        ng,
        "#{if(String.starts_with?(item, "ore"), do: "Đào", else: "Hái")} #{ng} #{Data.item(item).name}"
      )
    ]
  end

  defp pick(list, rng) do
    {i, rng} = :rand.uniform_s(length(list), rng)
    {Enum.at(list, i - 1), rng}
  end

  defp range(lo, hi, rng) do
    {i, rng} = :rand.uniform_s(hi - lo + 1, rng)
    {lo + i - 1, rng}
  end

  defp task(kind, target, zone, count, name) do
    lv =
      zone
      |> Data.zone()
      |> Map.fetch!(:monsters)
      |> Enum.map(& &1.level)
      |> then(&(Enum.sum(&1) / length(&1)))

    gold_each = 3 + lv * 2.2
    xp_each = 8 + lv * 6 + lv * lv * 0.5

    reward =
      case kind do
        "gather" ->
          %{
            gold: round(Data.item(target).price * 0.6 * count + gold_each * 3),
            xp: round(xp_each * count / 3)
          }

        _ ->
          %{gold: round(gold_each * count * 1.2), xp: round(xp_each * count * 0.6)}
      end

    %{
      kind: kind,
      target: target,
      zone: zone,
      count: count,
      progress: 0,
      claimed: false,
      name: name,
      reward: reward
    }
  end

  defp update(p, fun) do
    case p do
      %{daily: %{tasks: tasks} = d} -> %{p | daily: %{d | tasks: Enum.map(tasks, fun)}}
      _ -> p
    end
  end

  defp bump(t), do: %{t | progress: min(t.count, t.progress + 1)}

  @doc "Vừa hạ quái `monster_id` ở vùng `zone`."
  def on_kill(p, monster_id, zone) do
    update(p, fn
      %{kind: "kill", target: ^monster_id} = t -> bump(t)
      %{kind: "zone", zone: ^zone} = t -> bump(t)
      t -> t
    end)
  end

  @doc "Vừa hái/đào được nguyên liệu `item`."
  def on_gather(p, item) do
    update(p, fn
      %{kind: "gather", target: ^item} = t -> bump(t)
      t -> t
    end)
  end

  def ready?(%{daily: %{tasks: tasks}}),
    do: Enum.any?(tasks, &(&1.progress >= &1.count and not &1.claimed))

  def ready?(_), do: false

  @doc "Nhận thưởng việc thứ `i` (tính từ 0)."
  def claim(p, i) do
    tasks = get_in(p, [:daily, :tasks]) || []
    t = is_integer(i) and i >= 0 and Enum.at(tasks, i)

    cond do
      !t ->
        {%{ok: false, msg: "Không có việc này."}, p}

      t.claimed ->
        {%{ok: false, msg: "Đã nhận thưởng rồi."}, p}

      t.progress < t.count ->
        {%{ok: false, msg: "Chưa làm xong."}, p}

      true ->
        p = %{p | gold: p.gold + t.reward.gold}
        p = put_in(p.daily.tasks, List.replace_at(tasks, i, %{t | claimed: true}))
        {_levels, p} = Engine.gain_xp(p, t.reward.xp)

        {%{
           ok: true,
           msg: "Xong việc: #{t.name}! +#{t.reward.gold} vàng, +#{t.reward.xp} kinh nghiệm."
         }, p}
    end
  end
end
