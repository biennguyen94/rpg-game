defmodule HacLong.Game.Engine do
  @moduledoc """
  Luật chơi: chỉ số nhân vật, sinh quái, chiến đấu, lên cấp, mua bán.

  Mọi hàm đều thuần: nhận trạng thái nhân vật (map) và trả về `{kết_quả, nhân_vật_mới}`.
  Trạng thái được gửi nguyên cho client (JSON) để vẽ giao diện, nên tên khóa
  theo kiểu JS (`maxHp`, `skillCd`...). Số ngẫu nhiên lấy qua `HacLong.Game.Rng`
  để test cố định được kết quả.
  """

  alias HacLong.Game.{Data, Rng}

  @save_version 1
  @points_per_level 3
  @max_level 50
  @log_limit 60
  @potions ~w(potion_s potion_m potion_l)
  @stats ~w(str vit agi def)a
  @max_batch 99
  @max_upgrade 5

  def points_per_level, do: @points_per_level
  def max_level, do: @max_level

  # ---------- Ngẫu nhiên ----------
  defp rand(a, b), do: a + Rng.uniform() * (b - a)
  defp chance(p), do: Rng.uniform() < p
  defp pick(list), do: Enum.at(list, floor(Rng.uniform() * length(list)))
  defp clamp(v, lo, hi), do: max(lo, min(hi, v))

  defp ok(msg \\ nil), do: if(msg, do: %{ok: true, msg: msg}, else: %{ok: true})
  defp err(msg), do: %{ok: false, msg: msg}

  # ---------- Nhân vật ----------
  def new_player(name, cls) do
    case Data.class(cls) do
      nil ->
        {:error, "Lớp nhân vật không hợp lệ"}

      c ->
        name =
          case name |> to_string() |> String.trim() |> String.slice(0, 16) do
            "" -> "Hiệp Khách"
            n -> n
          end

        p = %{
          version: @save_version,
          name: name,
          cls: cls,
          level: 1,
          xp: 0,
          gold: 30,
          stats: c.base,
          points: 0,
          equip: %{weapon: "club", armor: "vest", shield: nil},
          inv: %{"potion_s" => 3},
          upgrades: %{},
          fish_caught: 0,
          achievements: [],
          title: nil,
          bosses: [],
          kills: 0,
          deaths: 0,
          victory: false,
          battle: nil,
          hp: 0
        }

        {:ok, %{p | hp: derived(p).maxHp}}
    end
  end

  def derived(p) do
    s = p.stats
    w = Data.item(p.equip.weapon)
    a = Data.item(p.equip.armor)
    sh = p.equip.shield && Data.item(p.equip.shield)

    up = fn id -> if id, do: upgrade_bonus(p, id), else: 0 end

    %{
      maxHp: round(40 + s.vit * 12 + p.level * 10),
      atk:
        round(
          s.str * 2.2 + s.agi * 0.9 + if(w, do: w.atk, else: 0) + up.(p.equip.weapon) + p.level
        ),
      def:
        round(
          s.def * 1.6 + if(a, do: a.def, else: 0) + if(sh, do: sh.def, else: 0) +
            up.(p.equip.armor) + up.(p.equip.shield) + p.level * 0.5
        ),
      crit: clamp(0.04 + s.agi * 0.008, 0, 0.6),
      critMult: min(2.5, 1.6 + s.agi * 0.006),
      dodge: clamp(0.02 + s.agi * 0.005, 0, 0.4)
    }
  end

  @doc """
  Các chỉ số tính ra từ trạng thái, gửi kèm cho client để hiển thị
  (client không có công thức nào).
  """
  def view(p) do
    %{
      derived: derived(p),
      xpToNext: xp_to_next(p.level),
      restCost: rest_cost(p),
      unlocked: Enum.map(0..(Data.zone_count() - 1), &zone_unlocked?(p, &1)),
      # cộng thêm của đồ đã nâng cấp (để client so sánh đồ) và giá nâng cấp đồ đang mặc
      bonus: upgrades(p) |> Map.keys() |> Map.new(&{&1, upgrade_bonus(p, &1)}),
      forge:
        for {slot, id} <- p.equip, id != nil, into: %{} do
          {slot,
           %{id: id, level: upgrade_level(p, id), cost: upgrade_cost(id, upgrade_level(p, id))}}
        end
    }
  end

  def xp_to_next(lv), do: round(25 * :math.pow(lv, 1.75) + 15)

  def zone_unlocked?(_p, 0), do: true

  def zone_unlocked?(p, zi) do
    case Data.zone(zi - 1) do
      nil -> false
      z -> z.boss.id in p.bosses
    end
  end

  # ---------- Quái ----------
  def make_monster(spec, boss?) do
    l = spec.level
    m = Map.get(spec, :mult, 1)
    bm = if boss?, do: 2.4, else: 1

    %{
      id: spec.id,
      name: spec.name,
      level: l,
      boss: boss?,
      final: Map.get(spec, :final, false),
      special: Map.get(spec, :special),
      on_hit: Map.get(spec, :on_hit),
      maxHp: round((20 + l * 26 + l * l * 0.6) * m * bm),
      atk: round((10 + l * 6.4) * m * 1),
      def: round((1 + l * 2.0) * m),
      crit: 0.05,
      dodge: 0.03 + l * 0.001,
      xp: round((8 + l * 6 + l * l * 0.5) * m * if(boss?, do: 5, else: 1)),
      gold: round((3 + l * 2.2) * m * rand(0.8, 1.2) * if(boss?, do: 6, else: 1))
    }
  end

  def damage(atk, dfn), do: max(1, round(atk * atk / (atk + dfn) * rand(0.9, 1.1)))

  # ---------- Chiến đấu ----------
  @doc "Trận với một con quái ngẫu nhiên của vùng (dùng cho bot mô phỏng)."
  def start_battle(p, zi, boss?) do
    z = if is_integer(zi), do: Data.zone(zi)

    with :ok <- can_fight(p, zi, z) do
      # Quái thường: ưu tiên con không quá cấp người chơi + 1 để người mới không bị đánh úp.
      spec =
        if boss? do
          z.boss
        else
          fair = Enum.filter(z.monsters, &(&1.level <= p.level + 1))
          pick(if fair == [], do: [hd(z.monsters)], else: fair)
        end

      do_start_battle(p, zi, spec, boss?)
    end
  end

  @doc "Trận với đúng con quái `spec` (người chơi vừa chạm vào nó trên bản đồ)."
  def start_encounter(p, zi, spec, boss?) do
    with :ok <- can_fight(p, zi, Data.zone(zi)), do: do_start_battle(p, zi, spec, boss?)
  end

  defp can_fight(p, zi, z) do
    cond do
      p.battle -> {err("Đang trong trận đấu."), p}
      z == nil or not zone_unlocked?(p, zi) -> {err("Khu vực chưa mở."), p}
      p.hp <= 0 -> {err("Bạn cần hồi máu trước."), p}
      true -> :ok
    end
  end

  @doc "Trận với một con quái đã dựng sẵn `m` (trùm thế giới). `zi`: vùng lấy hình nền."
  def start_with_monster(p, zi, m) do
    cond do
      p.battle -> {err("Đang trong trận đấu."), p}
      p.hp <= 0 -> {err("Bạn cần hồi máu trước."), p}
      true -> put_battle(p, zi, m, true)
    end
  end

  defp do_start_battle(p, zi, spec, boss?) do
    m = make_monster(spec, boss?)
    put_battle(p, zi, Map.put(m, :hp, m.maxHp), boss?)
  end

  defp put_battle(p, zi, m, boss?) do
    battle = %{
      zone: zi,
      monster: m,
      turn: 0,
      # hồi chiêu từng kỹ năng: [%{id, turns}]
      cds: [],
      # hiệu ứng trạng thái: [%{id, turns, power}] của mỗi bên
      effects: %{player: [], monster: []},
      log: [],
      over: false,
      result: nil,
      reward: nil
    }

    text =
      if boss?,
        do: "⚔️ #{m.name} (Cấp #{m.level}) xuất hiện!",
        else: "Bạn gặp #{m.name} (Cấp #{m.level})."

    {ok(), p |> Map.put(:battle, battle) |> log(text, "info")}
  end

  defp log(p, text, kind) do
    entries = p.battle.log ++ [%{text: text, kind: kind}]
    entries = if length(entries) > @log_limit, do: tl(entries), else: entries
    put_in(p.battle.log, entries)
  end

  def best_potion(p, missing) do
    owned = Enum.filter(@potions, &(Map.get(p.inv, &1, 0) > 0))

    # Bình nhỏ nhất đủ hồi phần máu đã mất, nếu không có thì bình lớn nhất đang có.
    case owned do
      [] -> nil
      _ -> Enum.find(owned, &(Data.item(&1).heal >= missing)) || List.last(owned)
    end
  end

  defp drink(p, id) do
    d = derived(p)
    before = p.hp
    p = %{p | hp: min(d.maxHp, p.hp + Data.item(id).heal)} |> take_item(id)
    {p, p.hp - before}
  end

  # ---------- Kỹ năng ----------

  @doc "Các kỹ năng đã mở ở cấp hiện tại (mỗi lớp mở thêm kỹ năng ở cấp 10 và 25)."
  def skills(p), do: Enum.filter(Data.class(p.cls).skills, &(&1.level <= p.level))

  @doc "Số lượt còn phải chờ để dùng lại kỹ năng `id` trong trận hiện tại."
  def cooldown(%{battle: %{} = b}, id) do
    case Enum.find(Map.get(b, :cds) || [], &(&1.id == id)) do
      nil -> 0
      c -> c.turns
    end
  end

  def cooldown(_p, _id), do: 0

  defp set_cd(p, id, turns) do
    cds = (Map.get(p.battle, :cds) || []) |> Enum.reject(&(&1.id == id))
    %{p | battle: Map.put(p.battle, :cds, cds ++ [%{id: id, turns: turns}])}
  end

  # ---------- Hiệu ứng trạng thái ----------
  # Độc, bỏng, chảy máu (`power` là số máu mất mỗi lượt); choáng (mất lượt kế tiếp);
  # suy yếu (tấn công giảm `power`); cuồng nộ (tấn công tăng); thủ thế (sát thương nhận
  # giảm); ảnh bộ (né thêm). Cuối mỗi lượt tính độc rồi giảm số lượt còn lại.

  @dots ~w(poison burn bleed)
  @effect_names %{
    "poison" => "trúng độc",
    "burn" => "bị bỏng",
    "bleed" => "chảy máu",
    "stun" => "bị choáng",
    "weaken" => "suy yếu",
    "rage" => "cuồng nộ",
    "guard" => "thủ thế",
    "evade" => "ảnh bộ"
  }

  def effect_names, do: @effect_names

  defp effects(p, who), do: (Map.get(p.battle, :effects) || %{})[who] || []
  defp effect(p, who, id), do: Enum.find(effects(p, who), &(&1.id == id))

  defp power(p, who, id) do
    case effect(p, who, id) do
      nil -> 0
      e -> e.power
    end
  end

  defp set_effects(p, who, list) do
    all = Map.get(p.battle, :effects) || %{player: [], monster: []}
    %{p | battle: Map.put(p.battle, :effects, Map.put(all, who, list))}
  end

  defp put_effect(p, who, id, turns, power) do
    list = p |> effects(who) |> Enum.reject(&(&1.id == id))
    set_effects(p, who, list ++ [%{id: id, turns: turns, power: power}])
  end

  defp drop_effect(p, who, id),
    do: set_effects(p, who, p |> effects(who) |> Enum.reject(&(&1.id == id)))

  # ---------- Lượt đánh ----------

  @doc """
  action: "attack" | "skill" | "potion" | "flee". Với "skill", `skill_id` chọn kỹ năng
  (không có thì dùng kỹ năng đầu tiên).
  """
  def act(p, action, skill_id \\ nil) do
    b = p.battle

    cond do
      b == nil or b.over ->
        {err("Không có trận đấu."), p}

      action not in ~w(attack skill potion flee) ->
        {err("Thao tác không hợp lệ."), p}

      effect(p, :player, "stun") ->
        p
        |> next_turn()
        |> drop_effect(:player, "stun")
        |> log("💫 Bạn bị choáng, mất một lượt.", "bad")
        |> monster_turn(derived(p))

      action in ~w(attack skill) ->
        act_strike(p, action, skill_id, derived(p))

      action == "potion" ->
        act_potion(p, derived(p))

      true ->
        act_flee(p, derived(p))
    end
  end

  defp next_turn(p), do: update_in(p.battle.turn, &(&1 + 1))

  defp act_flee(p, d) do
    p = next_turn(p)

    if chance(if p.battle.monster.boss, do: 0.35, else: 0.7) do
      p |> log("Bạn đã bỏ chạy thành công.", "info") |> finish("fled")
    else
      p |> log("Bỏ chạy thất bại!", "bad") |> monster_turn(d)
    end
  end

  defp act_potion(p, d) do
    id = best_potion(p, d.maxHp - p.hp)
    poisoned = Enum.filter(effects(p, :player), &(&1.id in @dots))

    cond do
      id == nil ->
        {err("Hết bình máu."), p}

      p.hp >= d.maxHp and poisoned == [] ->
        {err("Máu đang đầy."), p}

      true ->
        {p, healed} = p |> next_turn() |> drink(id)
        p = log(p, "Bạn uống #{Data.item(id).name}, hồi #{healed} máu.", "good")

        # bình máu giải luôn độc, bỏng, chảy máu
        p =
          if poisoned == [],
            do: p,
            else:
              p
              |> set_effects(:player, Enum.reject(effects(p, :player), &(&1.id in @dots)))
              |> log("Hết #{Enum.map_join(poisoned, ", ", &@effect_names[&1.id])}.", "good")

        monster_turn(p, d)
    end
  end

  defp pick_skill(p, nil), do: List.first(skills(p))
  defp pick_skill(p, id), do: Enum.find(skills(p), &(&1.id == id))

  defp act_strike(p, action, skill_id, d) do
    m = p.battle.monster
    skill = if action == "skill", do: pick_skill(p, skill_id)

    cond do
      action == "skill" and skill == nil ->
        {err("Chưa học kỹ năng này."), p}

      skill && cooldown(p, skill.id) > 0 ->
        {err("#{skill.name} hồi sau #{cooldown(p, skill.id)} lượt."), p}

      true ->
        p = next_turn(p)

        atk =
          round(d.atk * (1 + power(p, :player, "rage")) * (1 - power(p, :player, "weaken")))

        {p, atk, dfn, crit, mult, name, on_hit} =
          strike_with(p, skill, d, atk, m.def, chance(d.crit))

        p =
          if skill == nil and chance(m.dodge) do
            log(p, "#{m.name} né được đòn #{name}.", "info")
          else
            dmg = round(damage(atk, dfn) * mult * if(crit, do: d.critMult, else: 1))
            p = update_in(p.battle.monster.hp, &max(0, &1 - dmg))
            prefix = if skill, do: "✨ #{name}: ", else: ""
            suffix = if crit, do: " (CHÍ MẠNG!)", else: ""

            p
            |> log(
              "#{prefix}Bạn gây #{dmg} sát thương#{suffix}.",
              if(crit, do: "crit", else: "hit")
            )
            |> on_hit.(dmg)
          end

        if p.battle.monster.hp <= 0, do: win(p), else: monster_turn(p, d)
    end
  end

  # Trả về {nhân_vật, tấn_công, phòng_thủ_quái, chí_mạng?, hệ_số, tên, hàm_sau_khi_trúng}.
  defp strike_with(p, nil, _d, atk, dfn, crit),
    do: {p, atk, dfn, crit, 1, "tấn công", fn p, _ -> p end}

  defp strike_with(p, skill, d, atk, dfn, crit) do
    # +1 vì cuối lượt sẽ trừ 1
    p = set_cd(p, skill.id, skill.cooldown + 1)
    m = p.battle.monster
    none = fn p, _ -> p end

    case skill.id do
      "cleave" ->
        {p, atk, dfn, crit, 2.2, skill.name, none}

      "backstab" ->
        {p, atk, round(dfn * 0.5), true, 1, skill.name, none}

      "holy" ->
        heal = round(d.maxHp * 0.25)
        before = p.hp
        p = %{p | hp: min(d.maxHp, p.hp + heal)}

        {log(p, "Khiên Thánh hồi #{p.hp - before} máu.", "good"), atk, dfn, crit, 1.3, skill.name,
         none}

      "stun_bash" ->
        {p, atk, dfn, crit, 1.2, skill.name,
         fn p, _ ->
           if (m.boss || m[:world]) && chance(0.5),
             do: log(p, "#{m.name} không bị choáng.", "info"),
             else:
               p |> put_effect(:monster, "stun", 1, 0) |> log("💫 #{m.name} bị choáng!", "good")
         end}

      "war_cry" ->
        {p, atk, dfn, crit, 1, skill.name,
         fn p, _ ->
           p
           |> put_effect(:player, "rage", 4, 0.4)
           |> log("Bạn nổi cuồng nộ: tấn công +40%.", "good")
         end}

      "venom" ->
        {p, atk, dfn, crit, 1, skill.name,
         fn p, dmg ->
           p
           |> put_effect(:monster, "poison", 3, max(1, round(dmg * 0.5)))
           |> log("☠ #{m.name} trúng độc.", "good")
         end}

      "shadow_step" ->
        {p, atk, dfn, crit, 1.3, skill.name,
         fn p, _ ->
           p |> put_effect(:player, "evade", 2, 0.6) |> log("Bạn nhập ảnh bộ: né +60%.", "good")
         end}

      "guard" ->
        {p, atk, dfn, crit, 1, skill.name,
         fn p, _ ->
           p
           |> put_effect(:player, "guard", 2, 0.5)
           |> log("Bạn giơ khiên thủ thế: sát thương nhận -50%.", "good")
         end}

      "judgement" ->
        {p, atk, dfn, crit, 1.8, skill.name,
         fn p, _ ->
           p
           |> put_effect(:monster, "weaken", 3, 0.3)
           |> log("#{m.name} bị suy yếu: tấn công -30%.", "good")
         end}
    end
  end

  defp monster_turn(p, d) do
    b = p.battle
    m = b.monster

    if effect(p, :monster, "stun") do
      p
      |> drop_effect(:monster, "stun")
      |> log("💫 #{m.name} bị choáng, không đánh được.", "good")
      |> round_end()
    else
      special = m.special != nil and rem(b.turn, m.special.every) == 0
      m_atk = if special, do: round(m.atk * m.special.mult), else: m.atk
      m_atk = round(m_atk * (1 - power(p, :monster, "weaken")))

      p =
        if not special and chance(d.dodge + power(p, :player, "evade")) do
          log(p, "Bạn né được đòn của #{m.name}.", "info")
        else
          mc = not special and chance(m.crit)

          dmg =
            round(
              damage(m_atk, d.def) * if(mc, do: 1.5, else: 1) * (1 - power(p, :player, "guard"))
            )

          p = %{p | hp: max(0, p.hp - dmg)}

          text =
            if special,
              do: "🔥 #{m.name} dùng #{m.special.name}! Bạn mất #{dmg} máu.",
              else: "#{m.name} đánh bạn #{dmg} máu#{if mc, do: " (chí mạng)", else: ""}."

          p = log(p, text, "bad")

          cond do
            special and m.special[:effect] ->
              inflict(p, m, m.special.effect)

            not special and m[:on_hit] && chance(m.on_hit.chance) ->
              inflict(p, m, m.on_hit)

            true ->
              p
          end
        end

      if p.hp <= 0, do: lose(p), else: round_end(p)
    end
  end

  # Quái gây hiệu ứng lên người chơi.
  defp inflict(p, m, e) do
    case e.id do
      id when id in @dots ->
        per = max(1, round(m.atk * e.power))

        p
        |> put_effect(:player, id, e.turns, per)
        |> log("Bạn #{@effect_names[id]} (-#{per} máu mỗi lượt, uống bình máu để giải).", "bad")

      "stun" ->
        p |> put_effect(:player, "stun", 1, 0) |> log("💫 Bạn bị choáng!", "bad")

      "weaken" ->
        p
        |> put_effect(:player, "weaken", e.turns, e.power)
        |> log("Bạn bị suy yếu: tấn công -#{round(e.power * 100)}%.", "bad")
    end
  end

  # Cuối lượt: độc trên quái rồi trên người chơi, sau đó giảm số lượt hiệu ứng và hồi chiêu.
  defp round_end(p) do
    m = p.battle.monster

    mdot =
      p
      |> effects(:monster)
      |> Enum.filter(&(&1.id in @dots))
      |> Enum.map(& &1.power)
      |> Enum.sum()

    p =
      if mdot > 0 do
        p
        |> update_in([:battle, :monster, :hp], &max(0, &1 - mdot))
        |> log("☠ #{m.name} mất #{mdot} máu vì độc.", "hit")
      else
        p
      end

    if p.battle.monster.hp <= 0 do
      win(p)
    else
      pdots = p |> effects(:player) |> Enum.filter(&(&1.id in @dots))
      pdot = pdots |> Enum.map(& &1.power) |> Enum.sum()

      p =
        if pdot > 0 do
          p = %{p | hp: max(0, p.hp - pdot)}

          log(
            p,
            "Bạn mất #{pdot} máu vì #{Enum.map_join(pdots, ", ", &@effect_names[&1.id])}.",
            "bad"
          )
        else
          p
        end

      if p.hp <= 0 do
        lose(p)
      else
        tick = fn list ->
          list
          |> Enum.map(fn e -> if e.id == "stun", do: e, else: %{e | turns: e.turns - 1} end)
          |> Enum.filter(&(&1.turns > 0))
        end

        p =
          p
          |> set_effects(:player, tick.(effects(p, :player)))
          |> set_effects(:monster, tick.(effects(p, :monster)))

        cds =
          (Map.get(p.battle, :cds) || [])
          |> Enum.map(&%{&1 | turns: &1.turns - 1})
          |> Enum.filter(&(&1.turns > 0))

        {ok(), %{p | battle: Map.put(p.battle, :cds, cds)}}
      end
    end
  end

  defp win(p) do
    m = p.battle.monster
    p = %{p | kills: p.kills + 1, gold: p.gold + m.gold}
    reward = %{xp: m.xp, gold: m.gold, items: [], levels: 0}

    p =
      if m[:world],
        do: log(p, "🏆 #{m.name} gục ngã dưới đòn của bạn!", "win"),
        else: log(p, "🏆 Bạn đã hạ #{m.name}! +#{m.xp} kinh nghiệm, +#{m.gold} vàng.", "win")

    {p, reward} =
      if not m.boss and !m[:world] and chance(0.12) do
        id =
          cond do
            m.level >= 20 -> "potion_l"
            m.level >= 9 -> "potion_m"
            true -> "potion_s"
          end

        p = p |> add_item(id) |> log("Nhặt được #{Data.item(id).name}.", "good")
        {p, %{reward | items: reward.items ++ [id]}}
      else
        {p, reward}
      end

    {p, reward} =
      if m.boss and m.id not in p.bosses, do: first_boss_kill(p, m, reward), else: {p, reward}

    {levels, p} = gain_xp(p, m.xp)

    p =
      if levels > 0,
        do:
          log(
            p,
            "⭐ Lên cấp #{p.level}! Nhận #{levels * @points_per_level} điểm tiềm năng.",
            "win"
          ),
        else: p

    p = put_in(p.battle.reward, %{reward | levels: levels})
    finish(p, "win")
  end

  defp first_boss_kill(p, m, reward) do
    p = %{p | bosses: p.bosses ++ [m.id]}

    {p, reward} =
      case Data.boss_drop(m.id) do
        nil ->
          {p, reward}

        drop ->
          p = p |> add_item(drop) |> log("Trùm rơi ra #{Data.item(drop).name}!", "win")
          {p, %{reward | items: reward.items ++ [drop]}}
      end

    next = Data.zone(p.battle.zone + 1)

    p =
      cond do
        m.final ->
          %{p | victory: true} |> log("Hắc Long đã gục ngã. Vùng đất được giải phóng!", "win")

        next ->
          log(p, "Đã mở khu vực mới: #{next.name}.", "win")

        true ->
          p
      end

    {p, reward}
  end

  defp lose(p) do
    lost = floor(p.gold * 0.1)
    p = %{p | gold: p.gold - lost, deaths: p.deaths + 1}
    p = log(p, "💀 Bạn đã gục ngã... Mất #{lost} vàng. Dân làng đưa bạn về nhà trọ.", "bad")
    p = %{p | hp: round(derived(p).maxHp * 0.5)}
    finish(p, "lose")
  end

  defp finish(p, result) do
    p = update_in(p.battle, &%{&1 | over: true, result: result})
    {%{ok: true, result: result}, p}
  end

  def leave_battle(%{battle: %{over: true}} = p), do: {ok(), %{p | battle: nil}}
  def leave_battle(%{battle: nil} = p), do: {ok(), p}
  def leave_battle(p), do: {err("Trận đấu chưa kết thúc."), p}

  def gain_xp(p, xp), do: level_up(%{p | xp: p.xp + xp}, 0)

  defp level_up(p, levels) do
    if p.level < @max_level and p.xp >= xp_to_next(p.level) do
      g = Data.class(p.cls).growth
      stats = Map.new(p.stats, fn {k, v} -> {k, v + Map.get(g, k, 0)} end)

      %{
        p
        | xp: p.xp - xp_to_next(p.level),
          level: p.level + 1,
          stats: stats,
          points: p.points + @points_per_level
      }
      |> level_up(levels + 1)
    else
      p = if p.level >= @max_level, do: %{p | xp: 0}, else: p
      p = if levels > 0, do: %{p | hp: derived(p).maxHp}, else: p
      {levels, p}
    end
  end

  # ---------- Nâng cấp đồ (Thợ Rèn) ----------
  # Cấp nâng cấp lưu theo loại đồ (`upgrades: %{id => cấp}`), giữ nguyên khi tháo ra mặc lại.

  def max_upgrade, do: @max_upgrade

  defp upgrades(p), do: Map.get(p, :upgrades) || %{}

  def upgrade_level(p, id), do: Map.get(upgrades(p), id, 0)

  @doc "Tấn công/phòng thủ cộng thêm: mỗi cấp +8% chỉ số gốc của món đồ (ít nhất +1)."
  def upgrade_bonus(p, id) do
    case {upgrade_level(p, id), Data.item(id)} do
      {0, _} -> 0
      {_, nil} -> 0
      {l, it} -> l * max(1, round((it[:atk] || it[:def] || 0) * 0.08))
    end
  end

  @doc """
  Giá nâng món `id` từ cấp `level` lên cấp tiếp theo: `%{gold, items}` hoặc `nil` nếu đã tối
  đa. Đồ dưới cấp 17 dùng Quặng Sắt, từ cấp 17 dùng Mithril; cấp cuối cần thêm Vảy Cổ Long.
  """
  def upgrade_cost(_id, level) when level >= @max_upgrade, do: nil

  def upgrade_cost(id, level) do
    it = Data.item(id)
    n = level + 1
    ore = if (it[:level] || 1) >= 17, do: "ore_rare", else: "ore"
    items = %{ore => n}
    items = if n == @max_upgrade, do: Map.put(items, "dragon_scale", 1), else: items
    %{gold: round(max(it.price, 100) * 0.08 * n), items: items}
  end

  def upgrade(p, slot) do
    id = slot in ~w(weapon armor shield) && p.equip[String.to_existing_atom(slot)]
    level = if id, do: upgrade_level(p, id), else: 0
    cost = id && upgrade_cost(id, level)

    cond do
      !id ->
        {err("Chưa mặc đồ ở chỗ này."), p}

      p.battle ->
        {err("Đang trong trận."), p}

      cost == nil ->
        {err("#{Data.item(id).name} đã nâng cấp tối đa."), p}

      p.gold < cost.gold ->
        {err("Cần #{cost.gold} vàng."), p}

      not Enum.all?(cost.items, fn {m, n} -> Map.get(p.inv, m, 0) >= n end) ->
        missing =
          cost.items
          |> Enum.filter(fn {m, n} -> Map.get(p.inv, m, 0) < n end)
          |> Enum.map_join(", ", fn {m, n} ->
            "#{Data.item(m).name} #{Map.get(p.inv, m, 0)}/#{n}"
          end)

        {err("Thiếu nguyên liệu: #{missing}."), p}

      true ->
        hp_ratio = p.hp / derived(p).maxHp

        p =
          Enum.reduce(cost.items, %{p | gold: p.gold - cost.gold}, fn {m, n}, p ->
            take_item(p, m, n)
          end)

        p = Map.put(p, :upgrades, Map.put(upgrades(p), id, level + 1))
        p = %{p | hp: round(hp_ratio * derived(p).maxHp)}
        {ok("Đã nâng #{Data.item(id).name} lên +#{level + 1}."), p}
    end
  end

  # ---------- Đồ đạc ----------
  def add_item(p, id, n \\ 1), do: %{p | inv: Map.update(p.inv, id, n, &(&1 + n))}

  defp take_item(p, id, n \\ 1) do
    inv =
      case Map.get(p.inv, id, 0) do
        have when have > n -> Map.put(p.inv, id, have - n)
        _ -> Map.delete(p.inv, id)
      end

    %{p | inv: inv}
  end

  defp count_ok?(n), do: is_integer(n) and n >= 1 and n <= @max_batch

  def buy(p, id, n \\ 1) do
    it = Data.item(id)

    cond do
      # Chỉ bán những món có trong cửa hàng (đồ khởi đầu giá 0 và đồ rơi từ trùm thì không).
      it == nil || it[:drop] || id not in Data.shop() ->
        {err("Không bán món này."), p}

      not count_ok?(n) ->
        {err("Số lượng không hợp lệ."), p}

      it[:level] && p.level < it.level ->
        {err("Cần cấp #{it.level}."), p}

      p.gold < it.price * n ->
        {err("Không đủ vàng."), p}

      true ->
        {ok("Đã mua #{if n > 1, do: "#{n} ", else: ""}#{it.name}."),
         %{p | gold: p.gold - it.price * n} |> add_item(id, n)}
    end
  end

  def sell_price(id) do
    price = Data.item(id).price
    floor(if(price == 0, do: 200, else: price) * 0.4)
  end

  def sell(p, id) do
    if Map.get(p.inv, id, 0) > 0 and Data.item(id) do
      g = sell_price(id)
      p = %{take_item(p, id) | gold: p.gold + g}

      # bán hết món đã nâng cấp (không còn trong túi, không đang mặc) thì mất cấp nâng
      gone = not Map.has_key?(p.inv, id) and id not in Map.values(p.equip)
      p = if gone, do: Map.put(p, :upgrades, Map.delete(upgrades(p), id)), else: p
      {ok("Đã bán #{Data.item(id).name} được #{g} vàng."), p}
    else
      {err("Không có món này."), p}
    end
  end

  def equip(p, id) do
    it = Data.item(id)

    cond do
      it == nil or Map.get(p.inv, id, 0) <= 0 or it.slot not in ~w(weapon armor shield) ->
        {err("Không trang bị được."), p}

      it[:level] && p.level < it.level ->
        {err("Cần cấp #{it.level}."), p}

      true ->
        slot = String.to_existing_atom(it.slot)
        hp_ratio = p.hp / derived(p).maxHp
        old = p.equip[slot]
        p = take_item(p, id)
        p = if old, do: add_item(p, old), else: p
        p = %{p | equip: Map.put(p.equip, slot, id)}
        {ok("Đã trang bị #{it.name}."), %{p | hp: round(hp_ratio * derived(p).maxHp)}}
    end
  end

  def unequip(p, "shield") when p.equip.shield != nil do
    {ok("Đã tháo khiên."), %{add_item(p, p.equip.shield) | equip: %{p.equip | shield: nil}}}
  end

  def unequip(p, _slot), do: {err("Không tháo được."), p}

  def use_potion(p, id) do
    it = Data.item(id)

    cond do
      p.battle ->
        {err("Dùng nút Uống máu trong trận."), p}

      it == nil or Map.get(p.inv, id, 0) <= 0 or it.slot != "potion" ->
        {err("Không có bình này."), p}

      p.hp >= derived(p).maxHp ->
        {err("Máu đang đầy."), p}

      true ->
        {p, h} = drink(p, id)
        {ok("Hồi #{h} máu."), p}
    end
  end

  def rest_cost(p), do: if(p.hp >= derived(p).maxHp, do: 0, else: max(0, p.level * 4 - 4))

  def rest(p) do
    c = rest_cost(p)

    cond do
      p.battle ->
        {err("Đang trong trận."), p}

      p.hp >= derived(p).maxHp ->
        {err("Máu đang đầy."), p}

      p.gold < c ->
        {err("Cần #{c} vàng."), p}

      c > 0 ->
        {ok("Nghỉ trọ hết #{c} vàng. Máu đã đầy."), %{p | gold: p.gold - c, hp: derived(p).maxHp}}

      true ->
        {ok("Nghỉ ngơi miễn phí. Máu đã đầy."), %{p | hp: derived(p).maxHp}}
    end
  end

  def allocate(p, stat, n \\ 1) do
    stat = Enum.find(@stats, &(Atom.to_string(&1) == stat))

    cond do
      stat == nil ->
        {err("Chỉ số không hợp lệ."), p}

      not count_ok?(n) ->
        {err("Số điểm không hợp lệ."), p}

      p.points < n ->
        {err("Hết điểm tiềm năng."), p}

      true ->
        before = derived(p).maxHp
        p = %{p | stats: Map.update!(p.stats, stat, &(&1 + n)), points: p.points - n}
        # tăng thể lực thì cộng luôn máu
        {ok(), %{p | hp: p.hp + derived(p).maxHp - before}}
    end
  end
end
