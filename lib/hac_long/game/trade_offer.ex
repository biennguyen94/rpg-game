defmodule HacLong.Game.TradeOffer do
  @moduledoc """
  Phần hàm thuần của giao dịch trực tiếp (`HacLong.Trade`): kiểm tra món mình đưa ra, lấy
  đồ khỏi nhân vật và trao đồ cho nhân vật kia.

  Món đưa ra (`offer`): `%{items: %{id => số}, gear: [%{uid, base, name, rarity, up}], gold: số}`.
  Đồ chỉ số ngẫu nhiên phải đang ở trong túi (không mặc); đồ nâng cấp giữ nguyên cấp.
  """

  alias HacLong.Game.{Data, Engine, Gear}

  @max_lines 8
  @max_gold 10_000_000

  def max_lines, do: @max_lines

  def empty, do: %{items: %{}, gear: [], gold: 0}

  @doc """
  Đọc món đưa ra từ client (`%{"items" => %{id => số}, "gear" => [uid], "gold" => số}`) và
  kiểm tra với nhân vật `p`. Trả về `{:ok, offer}` hoặc `{:error, lý_do}`.
  """
  def parse(p, raw) when is_map(raw) do
    items = raw["items"] || %{}
    gear = raw["gear"] || []
    gold = raw["gold"] || 0

    cond do
      not (is_map(items) and is_list(gear) and is_integer(gold)) ->
        {:error, "Món đưa ra không hợp lệ."}

      gold < 0 or gold > @max_gold ->
        {:error, "Số vàng không hợp lệ."}

      map_size(items) + length(gear) > @max_lines ->
        {:error, "Mỗi lần đổi tối đa #{@max_lines} món."}

      not Enum.all?(items, fn {id, n} -> is_binary(id) and Data.item(id) && is_integer(n) end) ->
        {:error, "Món đưa ra không hợp lệ."}

      not Enum.all?(gear, &is_binary/1) or length(Enum.uniq(gear)) != length(gear) ->
        {:error, "Món đưa ra không hợp lệ."}

      true ->
        offer = %{
          items: items |> Enum.filter(fn {_, n} -> n > 0 end) |> Map.new(),
          gear: Enum.map(gear, &%{uid: &1}),
          gold: gold
        }

        with :ok <- check(p, offer), do: {:ok, describe(p, offer)}
    end
  end

  def parse(_p, _raw), do: {:error, "Món đưa ra không hợp lệ."}

  # thêm tên, độ hiếm, cấp nâng của đồ chỉ số ngẫu nhiên để người kia thấy
  defp describe(p, offer) do
    gear =
      for %{uid: uid} <- offer.gear do
        it = Gear.item(p, uid)

        %{
          uid: uid,
          base: it.base,
          name: it.name,
          rarity: it.rarity,
          up: Engine.upgrade_level(p, uid)
        }
      end

    %{offer | gear: gear}
  end

  @doc "Nhân vật `p` còn đủ những món trong `offer` không."
  def check(p, offer) do
    cond do
      p.gold < offer.gold ->
        {:error, "Không đủ vàng."}

      not Enum.all?(offer.items, fn {id, n} -> Map.get(p.inv, id, 0) >= n end) ->
        {:error, "Không đủ đồ trong túi."}

      not Enum.all?(offer.gear, &Gear.find(p, &1.uid)) ->
        {:error, "Không còn món đồ đã đưa ra."}

      Enum.any?(offer.gear, &Gear.equipped?(p, &1.uid)) ->
        {:error, "Tháo đồ đang mặc ra trước khi đổi."}

      true ->
        :ok
    end
  end

  @doc """
  Lấy những món trong `offer` ra khỏi `p`, biết sẽ nhận về `incoming` món đồ chỉ số ngẫu
  nhiên (để chắc túi còn chỗ). Trả về `{:ok, nhân_vật, gói_hàng}` hoặc `{:error, lý_do}`;
  `gói_hàng` đưa cho `give/2` của người kia.
  """
  def take(p, offer, incoming) do
    room = Gear.max_bag() - length(Gear.bag(p)) + length(offer.gear)

    with :ok <- check(p, offer),
         :ok <- if(incoming <= room, do: :ok, else: {:error, "Túi đồ hiếm không đủ chỗ."}) do
      inv =
        Enum.reduce(offer.items, p.inv, fn {id, n}, inv ->
          if inv[id] > n, do: Map.put(inv, id, inv[id] - n), else: Map.delete(inv, id)
        end)

      gear = for %{uid: uid} <- offer.gear, do: {Gear.find(p, uid), Engine.upgrade_level(p, uid)}
      ups = Map.get(p, :upgrades) || %{}

      p =
        offer.gear
        |> Enum.reduce(%{p | inv: inv, gold: p.gold - offer.gold}, &Gear.remove(&2, &1.uid))
        |> Map.put(:upgrades, Map.drop(ups, Enum.map(offer.gear, & &1.uid)))

      {:ok, p, %{items: offer.items, gear: gear, gold: offer.gold}}
    end
  end

  @doc "Trao gói hàng (từ `take/3`) cho `p`."
  def give(p, goods) do
    p =
      Enum.reduce(goods.items, %{p | gold: p.gold + goods.gold}, fn {id, n}, p ->
        Engine.add_item(p, id, n)
      end)

    Enum.reduce(goods.gear, p, fn {g, up}, p ->
      {p, _} = Gear.add(p, g)

      if up > 0,
        do: Map.put(p, :upgrades, Map.put(Map.get(p, :upgrades) || %{}, g.uid, up)),
        else: p
    end)
  end

  @doc "Tóm tắt một bên cho thông báo: \"Bình Máu Nhỏ ×2, Kiếm Sắt, 100 vàng\"."
  def summary(offer) do
    items =
      Enum.map(offer.items, fn {id, n} ->
        Data.item(id).name <> if(n > 1, do: " ×#{n}", else: "")
      end)

    gear = Enum.map(offer.gear, & &1.name)
    gold = if offer.gold > 0, do: ["#{offer.gold} vàng"], else: []

    case items ++ gear ++ gold do
      [] -> "không gì"
      all -> Enum.join(all, ", ")
    end
  end
end
