// Chạy lại một chuỗi lệnh trên engine JS với dãy số ngẫu nhiên cho trước và in ra
// trạng thái sau mỗi lệnh. Dùng bởi test/hac_long/game/engine_parity_test.exs.
// Đầu vào (stdin): { rng: [số], name, cls, commands: [{op, ...}] }
const E = require('../../../js/engine.js');

const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
let i = 0;
E.setRng(() => input.rng[i++ % input.rng.length]);

const p = E.newPlayer(input.name, input.cls);
const out = [];
for (const c of input.commands) {
  let r;
  switch (c.op) {
    case 'start': r = E.startBattle(p, c.zone, c.boss); break;
    case 'act': r = E.act(p, c.action); break;
    case 'leave': E.leaveBattle(p); r = { ok: true }; break;
    case 'buy': r = E.buy(p, c.id, c.n); break;
    case 'sell': r = E.sell(p, c.id); break;
    case 'equip': r = E.equip(p, c.id); break;
    case 'unequip': r = E.unequip(p, c.slot); break;
    case 'use': r = E.usePotion(p, c.id); break;
    case 'rest': r = E.rest(p); break;
    case 'alloc': r = E.allocate(p, c.stat, c.n); break;
    default: throw new Error('lệnh lạ ' + c.op);
  }
  out.push({ result: r, player: JSON.parse(JSON.stringify(p)) });
}
process.stdout.write(JSON.stringify(out));
