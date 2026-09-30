defmodule HacLong.Game.TradeOfferTest do
  use ExUnit.Case, async: true

  alias HacLong.Game.{Engine, Gear, TradeOffer}

  defp player do
    {:ok, p} = Engine.new_player("Buôn", "warrior")
    g = %{uid: "#G1", base: "club", rarity: 1, bonus: %{str: 1}}
    %{p | gold: 1000, inv: %{"potion_s" => 3}} |> Map.put(:gear, [g])
  end

  test "đọc món đưa ra từ client và kiểm tra" do
    p = player()
    assert {:ok, o} = TradeOffer.parse(p, %{"items" => %{"potion_s" => 2}, "gear" => ["#G1"]})
    assert o.items == %{"potion_s" => 2} and o.gold == 0
    assert [%{uid: "#G1", up: 0}] = o.gear

    for bad <- [
          %{"gold" => -1},
          %{"gold" => 5000},
          %{"items" => %{"nope" => 1}},
          %{"items" => %{"potion_s" => "2"}},
          %{"gear" => ["#G1", "#G1"]},
          %{"gear" => ["#KHONG"]},
          %{"items" => []},
          "x"
        ] do
      assert {:error, _} = TradeOffer.parse(p, bad), inspect(bad)
    end

    # số âm hay 0 thì bỏ qua
    assert {:ok, %{items: items}} = TradeOffer.parse(p, %{"items" => %{"potion_s" => 0}})
    assert items == %{}

    worn = %{p | equip: %{p.equip | weapon: "#G1"}}

    assert {:error, "Tháo đồ đang mặc ra trước khi đổi."} =
             TradeOffer.parse(worn, %{"gear" => ["#G1"]})
  end

  test "túi đồ hiếm đầy thì không nhận thêm được" do
    p = player()

    full =
      Map.put(
        p,
        :gear,
        for(
          i <- 1..Gear.max_bag(),
          do: %{uid: "##{i}", base: "club", rarity: 1, bonus: %{str: 1}}
        )
      )

    {:ok, o} = TradeOffer.parse(p, %{"gold" => 10})
    assert {:error, "Túi đồ hiếm không đủ chỗ."} = TradeOffer.take(full, o, 1)
    assert {:ok, _, _} = TradeOffer.take(full, o, 0)

    # đưa đi một món thì nhận về được một món
    {:ok, o} = TradeOffer.parse(full, %{"gear" => ["#1"]})
    assert {:ok, left, goods} = TradeOffer.take(full, o, 1)
    assert length(left.gear) == Gear.max_bag() - 1
    back = TradeOffer.give(left, goods)
    assert length(back.gear) == Gear.max_bag()
    assert TradeOffer.summary(%{items: %{"potion_s" => 2}, gear: [], gold: 5}) =~ "×2, 5 vàng"
    assert TradeOffer.summary(TradeOffer.empty()) == "không gì"
  end
end
