defmodule HacLong.Game.TutorialTest do
  use ExUnit.Case, async: true

  alias HacLong.Game.{Commands, Quests, Tutorial}

  defp player do
    {_, p} = Commands.run(nil, %{"act" => "create", "name" => "Tân Binh", "cls" => "warrior"})
    p
  end

  defp at(p, map, x, y), do: %{p | pos: %{map: map, x: x, y: y}}

  test "đi hết 5 bước thì xong và nhận quà tân thủ" do
    p = player()
    assert p.tutorial == 0
    assert {^p, nil} = Tutorial.check(p)
    assert %{step: 1, total: 5, target: %{map: "home", x: 5, y: 7}} = Tutorial.view(p)

    {p, note} = Tutorial.check(at(p, "village", 12, 15))
    assert p.tutorial == 1 and note =~ "Hướng dẫn 2/5"
    # đang ở Làng: mũi tên chỉ Trưởng Làng
    assert %{target: %{map: "village", x: 12, y: 3}} = Tutorial.view(p)

    {_, p} = Quests.accept(p, "forest_kill")
    {p, _} = Tutorial.check(p)
    assert p.tutorial == 2
    # chỉ cổng sang Rừng Mê
    assert %{target: %{map: "village", x: 6, y: 0}} = Tutorial.view(p)

    {p, _} = Tutorial.check(at(p, "forest_1", 13, 16))
    assert p.tutorial == 3 and Tutorial.view(p).target == nil

    p = Enum.reduce(1..5, p, fn _, p -> Quests.on_kill(p, "bat") end)
    {p, _} = Tutorial.check(p)
    assert p.tutorial == 4
    # đang ở rừng: chỉ cổng về Làng
    assert %{target: %{map: "forest_1", x: 13, y: 17}} = Tutorial.view(p)

    {_, p} = Quests.turn_in(p, "forest_kill")
    gold = p.gold
    {p, note} = Tutorial.check(p)
    assert p.tutorial == nil and note =~ "Xong phần hướng dẫn"
    assert p.gold == gold + Tutorial.reward().gold
    assert Tutorial.view(p) == nil
  end

  test "làm nhanh hơn hướng dẫn thì qua nhiều bước một lúc" do
    p = player()
    {_, p} = Quests.accept(p, "forest_kill")
    {p, note} = Tutorial.check(at(p, "forest_1", 13, 16))
    assert p.tutorial == 3 and note =~ "4/5"
  end

  test "bỏ qua hướng dẫn; nhân vật cũ không có hướng dẫn" do
    {%{ok: true}, p} = Commands.run(player(), %{"act" => "tutorial_skip"})
    assert p.tutorial == nil and Tutorial.view(p) == nil
    assert {^p, nil} = Tutorial.check(p)
  end
end
