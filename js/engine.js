/* Logic game thuần (không đụng tới DOM) để chạy được cả trên trình duyệt lẫn Node
 * (dùng cho mô phỏng cân bằng). Mọi thay đổi trạng thái đi qua các hàm ở đây. */
(function (root) {
  const D = (typeof module !== 'undefined' && module.exports) ? require('./data.js') : root.GAME_DATA;
  const { CLASSES, ZONES, ITEMS, BOSS_DROPS } = D;

  const SAVE_VERSION = 1;
  const POINTS_PER_LEVEL = 3;
  const MAX_LEVEL = 50;
  let rng = Math.random;

  const rand = (a, b) => a + rng() * (b - a);
  const chance = (p) => rng() < p;
  const pick = (arr) => arr[Math.floor(rng() * arr.length)];
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

  // ---------- Nhân vật ----------
  function newPlayer(name, cls) {
    const c = CLASSES[cls];
    if (!c) throw new Error('Lớp nhân vật không hợp lệ');
    const p = {
      version: SAVE_VERSION,
      name: String(name || 'Hiệp Khách').trim().slice(0, 16) || 'Hiệp Khách',
      cls,
      level: 1,
      xp: 0,
      gold: 30,
      stats: { ...c.base },
      points: 0,
      equip: { weapon: 'club', armor: 'vest', shield: null },
      inv: { potion_s: 3 },
      bosses: [],        // id các trùm đã hạ
      kills: 0,
      deaths: 0,
      victory: false,
      battle: null,
      hp: 0,
    };
    p.hp = derived(p).maxHp;
    return p;
  }

  function derived(p) {
    const s = p.stats;
    const w = ITEMS[p.equip.weapon], a = ITEMS[p.equip.armor], sh = p.equip.shield ? ITEMS[p.equip.shield] : null;
    return {
      maxHp: Math.round(40 + s.vit * 12 + p.level * 10),
      atk: Math.round(s.str * 2.2 + s.agi * 0.9 + (w ? w.atk : 0) + p.level),
      def: Math.round(s.def * 1.6 + (a ? a.def : 0) + (sh ? sh.def : 0) + p.level * 0.5),
      crit: clamp(0.04 + s.agi * 0.008, 0, 0.6),
      critMult: Math.min(2.5, 1.6 + s.agi * 0.006),
      dodge: clamp(0.02 + s.agi * 0.005, 0, 0.4),
    };
  }

  const xpToNext = (lv) => Math.round(25 * Math.pow(lv, 1.75) + 15);

  function zoneUnlocked(p, zi) {
    if (zi === 0) return true;
    return p.bosses.includes(ZONES[zi - 1].boss.id);
  }

  // ---------- Quái ----------
  function makeMonster(def, isBoss) {
    const L = def.level, m = def.mult || 1;
    return {
      id: def.id, name: def.name, level: L, boss: !!isBoss, final: !!def.final,
      special: def.special || null,
      maxHp: Math.round((40 + L * 30 + L * L * 0.5) * m * (isBoss ? 2.4 : 1)),
      atk: Math.round((18 + L * 6) * m * (isBoss ? 0.85 : 1)),
      def: Math.round((1 + L * 2.0) * m),
      crit: 0.05,
      dodge: 0.03 + L * 0.001,
      xp: Math.round((8 + L * 6 + L * L * 0.5) * m * (isBoss ? 5 : 1)),
      gold: Math.round((3 + L * 2.2) * m * rand(0.8, 1.2) * (isBoss ? 6 : 1)),
    };
  }

  function damage(atk, def) {
    return Math.max(1, Math.round((atk * atk) / (atk + def) * rand(0.9, 1.1)));
  }

  // ---------- Chiến đấu ----------
  function startBattle(p, zi, boss) {
    if (p.battle) return { ok: false, msg: 'Đang trong trận đấu.' };
    if (!zoneUnlocked(p, zi)) return { ok: false, msg: 'Khu vực chưa mở.' };
    if (p.hp <= 0) return { ok: false, msg: 'Bạn cần hồi máu trước.' };
    const z = ZONES[zi];
    const m = makeMonster(boss ? z.boss : pick(z.monsters), boss);
    m.hp = m.maxHp;
    p.battle = { zone: zi, monster: m, turn: 0, skillCd: 0, log: [], over: false, result: null, reward: null };
    log(p, boss ? `⚔️ ${m.name} (Cấp ${m.level}) xuất hiện!` : `Bạn gặp ${m.name} (Cấp ${m.level}).`, 'info');
    return { ok: true };
  }

  function log(p, text, kind) {
    p.battle.log.push({ text, kind: kind || '' });
    if (p.battle.log.length > 60) p.battle.log.shift();
  }

  function bestPotion(p, missing) {
    const owned = ['potion_s', 'potion_m', 'potion_l'].filter((id) => (p.inv[id] || 0) > 0);
    if (!owned.length) return null;
    // Bình nhỏ nhất đủ hồi phần máu đã mất, nếu không có thì bình lớn nhất đang có.
    return owned.find((id) => ITEMS[id].heal >= missing) || owned[owned.length - 1];
  }

  function drink(p, id) {
    const d = derived(p);
    const before = p.hp;
    p.hp = Math.min(d.maxHp, p.hp + ITEMS[id].heal);
    p.inv[id]--;
    if (!p.inv[id]) delete p.inv[id];
    return p.hp - before;
  }

  // action: 'attack' | 'skill' | 'potion' | 'flee'
  function act(p, action) {
    const b = p.battle;
    if (!b || b.over) return { ok: false, msg: 'Không có trận đấu.' };
    const d = derived(p), m = b.monster, skill = CLASSES[p.cls].skill;
    b.turn++;

    if (action === 'flee') {
      if (chance(m.boss ? 0.35 : 0.7)) {
        log(p, 'Bạn đã bỏ chạy thành công.', 'info');
        return finish(p, 'fled');
      }
      log(p, 'Bỏ chạy thất bại!', 'bad');
    } else if (action === 'potion') {
      const id = bestPotion(p, d.maxHp - p.hp);
      if (!id) { b.turn--; return { ok: false, msg: 'Hết bình máu.' }; }
      if (p.hp >= d.maxHp) { b.turn--; return { ok: false, msg: 'Máu đang đầy.' }; }
      const healed = drink(p, id);
      log(p, `Bạn uống ${ITEMS[id].name}, hồi ${healed} máu.`, 'good');
    } else {
      let atk = d.atk, def = m.def, crit = chance(d.crit), mult = 1, name = 'tấn công';
      if (action === 'skill') {
        if (b.skillCd > 0) { b.turn--; return { ok: false, msg: `Kỹ năng hồi sau ${b.skillCd} lượt.` }; }
        b.skillCd = skill.cooldown + 1; // +1 vì cuối lượt sẽ trừ 1
        name = skill.name;
        if (skill.id === 'cleave') mult = 2.2;
        if (skill.id === 'backstab') { crit = true; def = Math.round(def * 0.5); }
        if (skill.id === 'holy') {
          mult = 1.3;
          const heal = Math.round(d.maxHp * 0.25);
          const before = p.hp; p.hp = Math.min(d.maxHp, p.hp + heal);
          log(p, `Khiên Thánh hồi ${p.hp - before} máu.`, 'good');
        }
      }
      if (action !== 'skill' && chance(m.dodge)) {
        log(p, `${m.name} né được đòn ${name}.`, 'info');
      } else {
        let dmg = Math.round(damage(atk, def) * mult * (crit ? d.critMult : 1));
        m.hp = Math.max(0, m.hp - dmg);
        log(p, `${action === 'skill' ? '✨ ' + name + ': ' : ''}Bạn gây ${dmg} sát thương${crit ? ' (CHÍ MẠNG!)' : ''}.`, crit ? 'crit' : 'hit');
      }
      if (m.hp <= 0) return win(p);
    }

    // Lượt quái
    let mAtk = m.atk, special = false;
    if (m.special && b.turn % m.special.every === 0) { mAtk = Math.round(m.atk * m.special.mult); special = true; }
    if (!special && chance(d.dodge)) {
      log(p, `Bạn né được đòn của ${m.name}.`, 'info');
    } else {
      const mc = !special && chance(m.crit);
      const dmg = Math.round(damage(mAtk, d.def) * (mc ? 1.5 : 1));
      p.hp = Math.max(0, p.hp - dmg);
      log(p, special ? `🔥 ${m.name} dùng ${m.special.name}! Bạn mất ${dmg} máu.` : `${m.name} đánh bạn ${dmg} máu${mc ? ' (chí mạng)' : ''}.`, 'bad');
    }
    if (p.hp <= 0) return lose(p);
    if (b.skillCd > 0) b.skillCd--;
    return { ok: true };
  }

  function win(p) {
    const b = p.battle, m = b.monster;
    p.kills++;
    const reward = { xp: m.xp, gold: m.gold, items: [], levels: 0 };
    p.gold += m.gold;
    log(p, `🏆 Bạn đã hạ ${m.name}! +${m.xp} kinh nghiệm, +${m.gold} vàng.`, 'win');
    if (!m.boss && chance(0.12)) {
      const id = m.level >= 20 ? 'potion_l' : m.level >= 9 ? 'potion_m' : 'potion_s';
      addItem(p, id); reward.items.push(id);
      log(p, `Nhặt được ${ITEMS[id].name}.`, 'good');
    }
    if (m.boss) {
      const first = !p.bosses.includes(m.id);
      if (first) {
        p.bosses.push(m.id);
        const drop = BOSS_DROPS[m.id];
        if (drop) { addItem(p, drop); reward.items.push(drop); log(p, `Trùm rơi ra ${ITEMS[drop].name}!`, 'win'); }
        const zi = b.zone;
        if (m.final) { p.victory = true; log(p, 'Hắc Long đã gục ngã. Vùng đất được giải phóng!', 'win'); }
        else if (ZONES[zi + 1]) log(p, `Đã mở khu vực mới: ${ZONES[zi + 1].name}.`, 'win');
      }
    }
    reward.levels = gainXp(p, m.xp);
    if (reward.levels) log(p, `⭐ Lên cấp ${p.level}! Nhận ${reward.levels * POINTS_PER_LEVEL} điểm tiềm năng.`, 'win');
    b.reward = reward;
    return finish(p, 'win');
  }

  function lose(p) {
    const lost = Math.floor(p.gold * 0.1);
    p.gold -= lost;
    p.deaths++;
    log(p, `💀 Bạn đã gục ngã... Mất ${lost} vàng. Dân làng đưa bạn về nhà trọ.`, 'bad');
    p.hp = Math.round(derived(p).maxHp * 0.5);
    return finish(p, 'lose');
  }

  function finish(p, result) {
    p.battle.over = true;
    p.battle.result = result;
    return { ok: true, result };
  }

  function leaveBattle(p) {
    if (p.battle && p.battle.over) p.battle = null;
  }

  function gainXp(p, xp) {
    let levels = 0;
    p.xp += xp;
    while (p.level < MAX_LEVEL && p.xp >= xpToNext(p.level)) {
      p.xp -= xpToNext(p.level);
      p.level++;
      levels++;
      const g = CLASSES[p.cls].growth;
      for (const k in g) p.stats[k] += g[k];
      p.points += POINTS_PER_LEVEL;
    }
    if (p.level >= MAX_LEVEL) p.xp = 0;
    if (levels) p.hp = derived(p).maxHp;
    return levels;
  }

  // ---------- Đồ đạc ----------
  function addItem(p, id, n) { p.inv[id] = (p.inv[id] || 0) + (n || 1); }

  function buy(p, id, n) {
    n = n || 1;
    const it = ITEMS[id];
    if (!it || it.drop) return { ok: false, msg: 'Không bán món này.' };
    if (it.level && p.level < it.level) return { ok: false, msg: `Cần cấp ${it.level}.` };
    const cost = it.price * n;
    if (p.gold < cost) return { ok: false, msg: 'Không đủ vàng.' };
    p.gold -= cost;
    addItem(p, id, n);
    return { ok: true, msg: `Đã mua ${n > 1 ? n + ' ' : ''}${it.name}.` };
  }

  const sellPrice = (id) => Math.floor((ITEMS[id].price || 200) * 0.4);

  function sell(p, id) {
    if (!p.inv[id]) return { ok: false, msg: 'Không có món này.' };
    const g = sellPrice(id);
    p.inv[id]--;
    if (!p.inv[id]) delete p.inv[id];
    p.gold += g;
    return { ok: true, msg: `Đã bán ${ITEMS[id].name} được ${g} vàng.` };
  }

  function equip(p, id) {
    const it = ITEMS[id];
    if (!it || !p.inv[id] || !['weapon', 'armor', 'shield'].includes(it.slot)) return { ok: false, msg: 'Không trang bị được.' };
    if (it.level && p.level < it.level) return { ok: false, msg: `Cần cấp ${it.level}.` };
    const hpRatio = p.hp / derived(p).maxHp;
    const old = p.equip[it.slot];
    p.inv[id]--; if (!p.inv[id]) delete p.inv[id];
    if (old) addItem(p, old);
    p.equip[it.slot] = id;
    p.hp = Math.round(hpRatio * derived(p).maxHp);
    return { ok: true, msg: `Đã trang bị ${it.name}.` };
  }

  function unequip(p, slot) {
    if (slot !== 'shield' || !p.equip.shield) return { ok: false, msg: 'Không tháo được.' };
    addItem(p, p.equip.shield);
    p.equip.shield = null;
    return { ok: true, msg: 'Đã tháo khiên.' };
  }

  function usePotion(p, id) {
    if (p.battle) return { ok: false, msg: 'Dùng nút Uống máu trong trận.' };
    if (!p.inv[id] || ITEMS[id].slot !== 'potion') return { ok: false, msg: 'Không có bình này.' };
    if (p.hp >= derived(p).maxHp) return { ok: false, msg: 'Máu đang đầy.' };
    const h = drink(p, id);
    return { ok: true, msg: `Hồi ${h} máu.` };
  }

  const restCost = (p) => (p.hp >= derived(p).maxHp ? 0 : Math.max(0, p.level * 4 - 4));

  function rest(p) {
    if (p.battle) return { ok: false, msg: 'Đang trong trận.' };
    const c = restCost(p);
    if (p.hp >= derived(p).maxHp) return { ok: false, msg: 'Máu đang đầy.' };
    if (p.gold < c) return { ok: false, msg: `Cần ${c} vàng.` };
    p.gold -= c;
    p.hp = derived(p).maxHp;
    return { ok: true, msg: c ? `Nghỉ trọ hết ${c} vàng. Máu đã đầy.` : 'Nghỉ ngơi miễn phí. Máu đã đầy.' };
  }

  function allocate(p, stat, n) {
    n = n || 1;
    if (!['str', 'vit', 'agi', 'def'].includes(stat)) return { ok: false, msg: 'Chỉ số không hợp lệ.' };
    if (p.points < n) return { ok: false, msg: 'Hết điểm tiềm năng.' };
    const before = derived(p).maxHp;
    p.stats[stat] += n;
    p.points -= n;
    p.hp += derived(p).maxHp - before; // tăng thể lực thì cộng luôn máu
    return { ok: true };
  }

  // ---------- Lưu game ----------
  function serialize(p) { return JSON.stringify(p); }

  function deserialize(str) {
    const p = JSON.parse(str);
    if (!p || p.version !== SAVE_VERSION || !CLASSES[p.cls]) throw new Error('File lưu không hợp lệ');
    return p;
  }

  const Engine = {
    newPlayer, derived, xpToNext, zoneUnlocked, makeMonster, startBattle, act, leaveBattle,
    buy, sell, sellPrice, equip, unequip, usePotion, rest, restCost, allocate, gainXp, addItem,
    serialize, deserialize, bestPotion,
    setRng(f) { rng = f; },
    POINTS_PER_LEVEL, MAX_LEVEL,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = Engine;
  else root.Engine = Engine;
})(typeof window !== 'undefined' ? window : globalThis);
