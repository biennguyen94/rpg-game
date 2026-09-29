// Mô phỏng một người chơi "hợp lý" để kiểm tra cân bằng.
// Chạy: node tools/simulate.js [số lần chạy]
const E = require('../js/engine.js');
const { ZONES, ITEMS, SHOP } = require('../js/data.js');

const ALLOC = {
  warrior: ['str', 'str', 'vit'],
  rogue: ['agi', 'str', 'vit'],
  knight: ['vit', 'def', 'str'],
};

function shopUp(p) {
  for (const slot of ['weapon', 'armor', 'shield']) {
    const cur = p.equip[slot] ? ITEMS[p.equip[slot]] : null;
    const val = (it) => (it ? (it.atk || 0) + (it.def || 0) : 0);
    let best = null;
    for (const id of SHOP) {
      const it = ITEMS[id];
      if (it.slot !== slot || it.level > p.level || it.price > p.gold - 40) continue;
      if (val(it) > val(cur) && (!best || val(it) > val(ITEMS[best]))) best = id;
    }
    // đồ rơi trong túi
    for (const id in p.inv) if (ITEMS[id].slot === slot && val(ITEMS[id]) > val(best ? ITEMS[best] : cur) && ITEMS[id].level <= p.level) { E.equip(p, id); best = null; }
    if (best) { E.buy(p, best); E.equip(p, best); }
  }
  const pot = p.level >= 20 ? 'potion_l' : p.level >= 9 ? 'potion_m' : 'potion_s';
  while ((p.inv[pot] || 0) < 5 && p.gold >= ITEMS[pot].price + 20) E.buy(p, pot);
}

function run(cls, verbose) {
  const p = E.newPlayer('Bot', cls);
  let fights = 0, restGold = 0, cooldown = 0;
  const milestones = [];
  while (!p.victory && fights < 5000) {
    while (p.points > 0) E.allocate(p, ALLOC[cls][p.points % 3]);
    shopUp(p);
    if (p.hp < E.derived(p).maxHp * 0.6) { restGold += E.restCost(p); E.rest(p); }
    let zi = 0;
    for (let i = 0; i < ZONES.length; i++) if (E.zoneUnlocked(p, i)) zi = i;
    const z = ZONES[zi];
    const boss = cooldown <= 0 && p.level >= z.boss.level - 1 && !p.bosses.includes(z.boss.id);
    cooldown--;
    // lùi một khu nếu còn quá yếu
    if (!boss && p.level < z.monsters[0].level - 1 && zi > 0) zi--;
    E.startBattle(p, zi, boss);
    fights++;
    while (!p.battle.over) {
      const d = E.derived(p);
      if (p.hp < d.maxHp * 0.35 && E.bestPotion(p, d.maxHp - p.hp)) E.act(p, 'potion');
      else if (p.battle.skillCd === 0) E.act(p, 'skill');
      else E.act(p, 'attack');
    }
    if (boss && p.battle.result === 'win') milestones.push(`${z.boss.name}@Lv${p.level}(trận ${fights})`);
    if (boss && p.battle.result !== 'win') cooldown = 15;
    if (boss && p.battle.result === 'lose' && verbose) console.log(`  thua ${z.boss.name} ở Lv${p.level}`);
    E.leaveBattle(p);
  }
  return { cls, fights, level: p.level, deaths: p.deaths, gold: p.gold, restGold, milestones };
}

const N = +process.argv[2] || 5;
for (const cls of ['warrior', 'rogue', 'knight']) {
  const rs = [];
  for (let i = 0; i < N; i++) rs.push(run(cls, i === 0));
  const avg = (k) => Math.round(rs.reduce((s, r) => s + r[k], 0) / rs.length);
  console.log(`${cls}: trận=${avg('fights')} cấp cuối=${avg('level')} chết=${avg('deaths')} vàng=${avg('gold')}`);
  console.log('  ' + rs[0].milestones.join(' → '));
}
