defmodule HacLong.Market do
  @moduledoc """
  Chợ giữa người chơi (gặp Chủ Chợ trong Làng).

  - Rao bán (`list/5`): đồ thường (một số lượng) hoặc một món đồ chỉ số ngẫu nhiên (không
    đang mặc; giữ nguyên cấp nâng). Món đồ rời túi ngay, giữ ở chợ tới khi bán được hoặc rút về.
  - Mua (`buy/4`): trừ vàng người mua, đưa đồ vào túi; người bán nhận tiền qua hộp thư, trừ
    `@fee_pct`% phí chợ. Đánh dấu hàng đã bán chỉ thành công một lần (`sold_at IS NULL`) nên
    hai người cùng mua thì chỉ một người được; mọi bước ở trong một transaction nên không
    nhân đôi đồ hay vàng.
  - Rút về (`cancel/4`): hàng chưa bán thì trả lại túi.
  - Mỗi người rao tối đa `@max_active` món cùng lúc.

  Các hàm nhận nhân vật `p` và hàm `save` để ghi nhân vật trong cùng transaction (gọi từ
  `HacLong.Game.Session`), trả về `{:ok, thông_báo, nhân_vật}` hoặc `{:error, lý_do}`.
  """
  import Ecto.Query

  alias HacLong.{Mailbox, Repo}
  alias HacLong.Accounts.User
  alias HacLong.Game.{Character, Data, Engine, Gear}

  @fee_pct 5
  @max_active 10
  @max_price 10_000_000

  def fee_pct, do: @fee_pct
  def max_active, do: @max_active

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  # ---------- Xem ----------

  @doc "Hàng đang bán (mới trước), lọc theo tên (`q`) nếu có."
  def listings(q \\ "", viewer \\ nil) do
    q = q |> to_string() |> String.trim() |> String.downcase()

    from(l in "market_listings",
      join: u in User,
      on: u.id == l.seller_id,
      left_join: c in Character,
      on: c.user_id == l.seller_id,
      where: is_nil(l.sold_at),
      order_by: [desc: l.id],
      limit: 300,
      select: %{
        id: l.id,
        seller_id: l.seller_id,
        seller: coalesce(c.name, u.username),
        item: l.item,
        count: l.count,
        gear: l.gear,
        price: l.price,
        at: l.inserted_at
      }
    )
    |> Repo.all()
    |> Enum.map(&present/1)
    |> Enum.filter(&(q == "" or String.contains?(String.downcase(&1.name), q)))
    |> Enum.map(&Map.put(&1, :mine, &1.seller_id == viewer))
  end

  @doc "Hàng mình đang rao."
  def mine(uid), do: listings("", uid) |> Enum.filter(& &1.mine)

  defp present(l) do
    info =
      case l.gear do
        nil ->
          it = Data.item(l.item)
          %{name: it.name, slot: it.slot, gear: nil}

        g ->
          g = gear_of(g)
          it = Gear.resolve(g)
          %{name: it.name, slot: it.slot, gear: Map.put(it, :up, g.up)}
      end

    Map.merge(Map.drop(l, [:gear]), info)
  end

  # đồ chỉ số ngẫu nhiên lưu trong cột gear (khóa chuỗi) → dạng engine dùng
  defp gear_of(g) do
    %{
      uid: g["uid"],
      base: g["base"],
      rarity: g["rarity"],
      bonus: Map.new(g["bonus"], fn {k, v} -> {String.to_existing_atom(k), v} end),
      up: g["up"] || 0
    }
  end

  defp active_count(uid) do
    Repo.aggregate(
      from(l in "market_listings", where: l.seller_id == ^uid and is_nil(l.sold_at)),
      :count
    )
  end

  # ---------- Rao bán ----------

  @doc "Rao bán `count` món `id` (id đồ thường hoặc `#...` đồ chỉ số ngẫu nhiên) giá `price`."
  def list(uid, p, id, count, price, save) do
    gear? = Gear.instance?(id)

    cond do
      not (is_integer(price) and price >= 1 and price <= @max_price) ->
        {:error, "Giá phải từ 1 tới #{@max_price} vàng."}

      active_count(uid) >= @max_active ->
        {:error, "Bạn đang rao đủ #{@max_active} món. Chờ bán hoặc rút bớt."}

      gear? ->
        list_gear(uid, p, id, price, save)

      true ->
        list_item(uid, p, id, count, price, save)
    end
  end

  defp list_item(uid, p, id, count, price, save) do
    it = is_binary(id) && Data.item(id)

    cond do
      !it ->
        {:error, "Không có món này."}

      not (is_integer(count) and count >= 1 and Map.get(p.inv, id, 0) >= count) ->
        {:error, "Không đủ số lượng trong túi."}

      true ->
        left = p.inv[id] - count
        inv = if left > 0, do: Map.put(p.inv, id, left), else: Map.delete(p.inv, id)
        p = %{p | inv: inv}
        row = %{seller_id: uid, item: id, count: count, price: price, inserted_at: now()}

        commit(
          p,
          save,
          row,
          "Đã rao bán #{it.name}#{if count > 1, do: " ×#{count}", else: ""} giá #{price} vàng."
        )
    end
  end

  defp list_gear(uid, p, uid_gear, price, save) do
    case Gear.find(p, uid_gear) do
      nil ->
        {:error, "Không có món này."}

      g ->
        if Gear.equipped?(p, uid_gear) do
          {:error, "Tháo món này ra trước khi bán."}
        else
          up = Engine.upgrade_level(p, uid_gear)
          p = Gear.remove(p, uid_gear)
          p = Map.put(p, :upgrades, Map.delete(Map.get(p, :upgrades) || %{}, uid_gear))

          row = %{
            seller_id: uid,
            gear: %{uid: g.uid, base: g.base, rarity: g.rarity, bonus: g.bonus, up: up},
            count: 1,
            price: price,
            inserted_at: now()
          }

          commit(p, save, row, "Đã rao bán #{Gear.resolve(g).name} giá #{price} vàng.")
        end
    end
  end

  defp commit(p, save, row, msg) do
    Repo.transaction(fn ->
      Repo.insert_all("market_listings", [row])
      save.(p)
    end)

    {:ok, msg, p}
  end

  # ---------- Mua ----------

  def buy(uid, p, listing_id, save) when is_integer(listing_id) do
    Repo.transaction(fn ->
      row =
        Repo.one(
          from l in "market_listings",
            where: l.id == ^listing_id and is_nil(l.sold_at),
            lock: "FOR UPDATE",
            select: %{
              id: l.id,
              seller_id: l.seller_id,
              item: l.item,
              count: l.count,
              gear: l.gear,
              price: l.price
            }
        )

      cond do
        row == nil -> Repo.rollback("Món này đã có người mua hoặc đã rút về.")
        row.seller_id == uid -> Repo.rollback("Đây là hàng của bạn.")
        p.gold < row.price -> Repo.rollback("Không đủ vàng.")
        row.gear && length(Gear.bag(p)) >= Gear.max_bag() -> Repo.rollback("Túi đồ hiếm đầy.")
        true -> :ok
      end

      Repo.update_all(from(l in "market_listings", where: l.id == ^row.id),
        set: [sold_at: now(), buyer_id: uid]
      )

      p = %{p | gold: p.gold - row.price} |> receive_goods(row)
      save.(p)

      earned = row.price - div(row.price * @fee_pct, 100)
      name = present(row).name

      Mailbox.send(row.seller_id, %{
        subject: "Chợ: bán được #{name}",
        body:
          "Có người mua #{name}#{if row.count > 1, do: " ×#{row.count}", else: ""} giá #{row.price} vàng. Phí chợ #{@fee_pct}%.",
        gold: earned
      })

      {"Đã mua #{name}#{if row.count > 1, do: " ×#{row.count}", else: ""}.", p}
    end)
    |> case do
      {:ok, {msg, p}} -> {:ok, msg, p}
      {:error, msg} -> {:error, msg}
    end
  end

  def buy(_uid, _p, _id, _save), do: {:error, "Món hàng không hợp lệ."}

  # ---------- Rút về ----------

  def cancel(uid, p, listing_id, save) when is_integer(listing_id) do
    Repo.transaction(fn ->
      {n, rows} =
        Repo.delete_all(
          from(l in "market_listings",
            where: l.id == ^listing_id and l.seller_id == ^uid and is_nil(l.sold_at),
            select: %{item: l.item, count: l.count, gear: l.gear, price: l.price}
          )
        )

      if n == 0, do: Repo.rollback("Không còn món này ở chợ.")
      row = hd(rows)

      if row.gear && length(Gear.bag(p)) >= Gear.max_bag(),
        do: Repo.rollback("Túi đồ hiếm đầy, bán bớt đồ trước khi rút về.")

      p = receive_goods(p, row)
      save.(p)
      {"Đã rút #{present(Map.merge(row, %{id: nil, seller_id: uid})).name} về túi.", p}
    end)
    |> case do
      {:ok, {msg, p}} -> {:ok, msg, p}
      {:error, msg} -> {:error, msg}
    end
  end

  def cancel(_uid, _p, _id, _save), do: {:error, "Món hàng không hợp lệ."}

  defp receive_goods(p, %{gear: nil, item: id, count: n}), do: Engine.add_item(p, id, n)

  defp receive_goods(p, %{gear: g}) do
    g = gear_of(g)
    {p, :kept} = Gear.add(p, Map.delete(g, :up))

    if g.up > 0,
      do: Map.put(p, :upgrades, Map.put(Map.get(p, :upgrades) || %{}, g.uid, g.up)),
      else: p
  end
end
