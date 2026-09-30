defmodule HacLong.Game.GearTest do
  use HacLong.DataCase, async: true

  alias HacLong.Game.{Characters, Engine, Gear, Rng}

  setup do
    on_exit(&Rng.clear/0)
  end

  defp player do
    {:ok, p} = Engine.new_player("Thử", "warrior")
    %{p | level: 25}
  end

  defp sword(bonus \\ %{str: 5, agi: 2}),
    do: %{uid: "#KIEM", base: "greatsword", rarity: 2, bonus: bonus}

  test "tạo món ngẫu nhiên theo cấp quái" do
    # 0.1: vũ khí; 0.1: đồ gốc mạnh nhất (Chùy Gai, cấp 12); 0.1: Hiếm (2 dòng chỉ số)
    Rng.put_sequence([0.1])
    g = Gear.roll(12)
    assert g.base == "mace" and g.rarity == 2 and map_size(g.bonus) == 2
    # giá trị mỗi dòng: 1 + phần ngẫu nhiên tới cấp/6
    assert Enum.all?(Map.values(g.bonus), &(&1 in 1..3))
    assert String.starts_with?(g.uid, "#")

    # cấp quá thấp, không có đồ gốc nào (trừ đồ khởi đầu giá 0) thì không rơi
    Rng.put_sequence([0.99])
    assert Gear.roll(2) == nil
  end

  test "mặc đồ ngẫu nhiên cộng chỉ số, tháo ra thì về túi" do
    p = player()
    base = Engine.derived(p)
    {p, _} = Gear.add(p, sword())
    assert [%{name: "Đại Kiếm Sức Mạnh"}] = Enum.map(Gear.bag(p), &Gear.resolve/1)

    {%{ok: true, msg: "Đã trang bị Đại Kiếm Sức Mạnh."}, p} = Engine.equip(p, "#KIEM")
    d = Engine.derived(p)

    # Đại Kiếm 44 tấn công thay Gậy Gỗ 3; +5 sức mạnh (×2.2) và +2 nhanh nhẹn (×0.9)
    assert d.atk == base.atk + 41 + round(5 * 2.2 + 2 * 0.9)
    assert Gear.bag(p) == []
    # gậy cũ về túi đồ thường
    assert p.inv["club"] == 1
    assert {%{ok: false, msg: "Đang mặc món này."}, _} = Engine.sell(p, "#KIEM")

    {_, p} = Engine.equip(p, "club")
    assert [%{uid: "#KIEM"}] = Gear.bag(p)
    gold = p.gold
    {%{ok: true}, p} = Engine.sell(p, "#KIEM")
    assert p.gold > gold and p.gear == []
  end

  test "nâng cấp đồ ngẫu nhiên như đồ thường" do
    p = %{player() | gold: 10_000} |> Engine.add_item("ore_rare", 5)
    {p, _} = Gear.add(p, sword())
    {_, p} = Engine.equip(p, "#KIEM")
    {%{ok: true, msg: "Đã nâng Đại Kiếm Sức Mạnh lên +1."}, p} = Engine.upgrade(p, "weapon")
    assert Engine.upgrade_level(p, "#KIEM") == 1
  end

  test "túi đầy thì món mới bán luôn" do
    p = player()

    p =
      Enum.reduce(1..Gear.max_bag(), p, fn i, p ->
        elem(Gear.add(p, %{sword() | uid: "##{i}"}), 0)
      end)

    assert {p2, {:sold, gold}} = Gear.add(p, sword())
    assert p2.gold == p.gold + gold and length(p2.gear) == Gear.max_bag()
  end

  test "lưu và nạp lại từ database" do
    {:ok, user} =
      HacLong.Accounts.register(%{
        "username" => "luudo#{System.unique_integer([:positive])}",
        "password" => "matkhau1"
      })

    {:ok, p} = Engine.new_player("Lưu Đồ #{System.unique_integer([:positive])}", "rogue")
    {p, _} = Gear.add(%{p | level: 25}, sword())
    {_, p} = Engine.equip(p, "#KIEM")
    p = p |> Map.merge(%{pos: %{map: "village", x: 12, y: 14}, upgrades: %{"#KIEM" => 2}})
    Characters.save!(user.id, p)
    q = Characters.load(user.id)
    assert q.gear == p.gear and q.equip.weapon == "#KIEM"
    assert q.upgrades == %{"#KIEM" => 2}
    assert Engine.derived(q) == Engine.derived(p)
  end

  test "trận đang đánh có hiệu ứng, hồi chiêu, đồ rơi vẫn lưu và nạp lại đúng" do
    {:ok, user} =
      HacLong.Accounts.register(%{
        "username" => "tran#{System.unique_integer([:positive])}",
        "password" => "matkhau1"
      })

    Rng.put_sequence([0.99])
    {:ok, p} = Engine.new_player("Trận #{System.unique_integer([:positive])}", "rogue")
    p = %{p | level: 10} |> Map.put(:pos, %{map: "forest_1", x: 5, y: 5})
    {_, p} = Engine.start_battle(p, 0, false)
    p = put_in(p.battle.monster.hp, 10_000)
    {_, p} = Engine.act(p, "skill", "venom")
    p = put_in(p.battle.reward, %{xp: 1, gold: 1, items: [], levels: 0, gear: ["Kiếm"]})
    Characters.save!(user.id, p)
    q = Characters.load(user.id)
    assert q.battle.effects == p.battle.effects and q.battle.cds == p.battle.cds
    assert q.battle.reward.gear == ["Kiếm"]
    assert {%{ok: true}, _} = Engine.act(q, "attack")
  end
end
