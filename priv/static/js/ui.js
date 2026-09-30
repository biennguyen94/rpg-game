/* Giao diện: vẽ lại từng màn hình từ trạng thái người chơi (P) do server gửi về.
 * Mọi thao tác gửi lên server qua Net (net.js); server tính toán rồi trả trạng thái mới.
 * P.view chứa các chỉ số server tính sẵn (máu tối đa, tấn công, giá nghỉ trọ...). */
(function () {
  const { CLASSES, ZONES, ITEMS, SHOP, RULES } = window.GAME_DATA;
  const Net = window.Net;

  let P = null;          // trạng thái người chơi
  let tab = 'town';      // tab đang mở
  let pickCls = 'warrior';
  let confirmReset = false;
  let fx = null;         // hiệu ứng trận đấu của lượt vừa rồi
  let authMode = 'login'; // 'login' | 'register'
  let loading = true;    // đang kết nối server
  let busy = false;      // đang chờ server trả lời

  const $ = (s) => document.querySelector(s);
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const fmt = (n) => Math.round(n).toLocaleString('vi-VN');

  const asset = (path) => 'assets/' + path;
  const icon = (name, cls) => `<img class="ic ${cls || ''}" src="${asset('icons/' + name + '.svg')}" alt="">`;
  const sprite = (id, cls, alt) => `<img class="sprite ${cls || ''}" src="${asset('monsters/' + id + '.png')}" alt="${esc(alt || '')}">`;

  let toastTimer;
  function toast(msg, err) {
    if (!msg) return;
    const t = $('#toast');
    t.textContent = msg;
    t.className = 'show' + (err ? ' err' : '');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { t.className = err ? 'err' : ''; }, 1800);
  }

  function result(r) {
    if (!r) return;
    if (!r.ok) toast(r.msg, true); else if (r.msg) toast(r.msg);
  }

  // ---------- Khung ----------
  function render() {
    const hud = $('#hud'), tabs = $('#tabs'), view = $('#view');
    if (loading || !Net.username) {
      hud.hidden = true; tabs.hidden = true;
      view.innerHTML = loading ? viewLoading() : viewLogin();
      return;
    }
    if (!P) {
      hud.hidden = true; tabs.hidden = true;
      view.innerHTML = viewCreate();
      return;
    }
    hud.hidden = false;
    hud.innerHTML = viewHud();
    if (P.battle) {
      tabs.hidden = true;
      view.innerHTML = viewBattle();
      const log = view.querySelector('.log');
      if (log) log.scrollTop = log.scrollHeight;
      fx = null;
      return;
    }
    tabs.hidden = false;
    tabs.innerHTML = [
      ['town', 'village', 'Làng'],
      ['hunt', 'crossed-swords', 'Săn quái'],
      ['hero', 'person', 'Nhân vật'],
      ['bag', 'backpack', 'Túi đồ'],
      ['shop', 'shop', 'Cửa hàng'],
    ].map(([id, ic, label]) => `<button data-tab="${id}" ${tab === id ? 'aria-current="page"' : ''}>${icon(ic)}<span>${label}${id === 'hero' && P.points ? `<span class="points-dot">${P.points}</span>` : ''}</span></button>`).join('');
    view.innerHTML = P.victory && tab === 'town' ? viewVictory() + viewTown() : ({ town: viewTown, hunt: viewHunt, hero: viewHero, bag: viewBag, shop: viewShop }[tab])();
  }

  function bar(kind, cur, max, label) {
    const w = max ? Math.max(0, Math.min(100, (cur / max) * 100)) : 0;
    return `<div class="bar ${kind}"><i style="width:${w}%"></i><span>${label || `${fmt(cur)} / ${fmt(max)}`}</span></div>`;
  }

  function viewHud() {
    const d = P.view.derived, need = P.view.xpToNext;
    return `
      <div class="hud-top">
        ${sprite('hero', '', 'Nhân vật')}
        <div class="hud-who">
          <div class="hud-name">${esc(P.name)}</div>
          <div class="small muted">${CLASSES[P.cls].name} · Cấp ${P.level}</div>
        </div>
        <div class="gold">${icon('two-coins')}${fmt(P.gold)}</div>
      </div>
      <div class="bars">
        ${bar('hp', P.hp, d.maxHp, `❤ ${fmt(P.hp)} / ${fmt(d.maxHp)}`)}
        ${P.level >= RULES.maxLevel ? bar('xp', 1, 1, 'Cấp tối đa') : bar('xp', P.xp, need, `EXP ${Math.floor((P.xp / need) * 100)}%`)}
      </div>`;
  }

  // ---------- Tạo nhân vật ----------
  function viewCreate() {
    return `
      <div class="intro">
        ${sprite('shadow_dragon', '', 'Hắc Long')}
        <h1>Hắc Long</h1>
        <p>Hắc Long đã khủng bố vùng đất này nhiều năm. Rèn luyện qua sáu vùng đất, hạ các trùm canh giữ và tiêu diệt nó.</p>
      </div>
      <form id="create" class="card" autocomplete="off">
        <label class="field" for="hero-name">Tên nhân vật
          <input type="text" id="hero-name" maxlength="16" placeholder="Ví dụ: Lãng Khách" required>
        </label>
        <div class="field" style="display:grid;gap:6px"><span style="font-weight:600">Chọn lớp</span>
          <div class="classes">
            ${Object.entries(CLASSES).map(([id, c]) => `
              <button type="button" class="class-opt" data-cls="${id}" aria-pressed="${pickCls === id}">
                ${icon(c.icon, 'lg')}
                <span class="grow" style="display:grid;gap:2px;min-width:0">
                  <b>${c.name}</b>
                  <span class="small muted">${c.desc}</span>
                  <span class="stats">Sức mạnh ${c.base.str} · Thể lực ${c.base.vit} · Nhanh nhẹn ${c.base.agi} · Phòng thủ ${c.base.def}</span>
                  <span class="small" style="color:var(--gold)">Kỹ năng: ${c.skill.name}. ${c.skill.desc}</span>
                </span>
              </button>`).join('')}
          </div>
        </div>
        <button class="btn primary block" type="submit">Bắt đầu hành trình</button>
      </form>
      <p class="small muted" style="text-align:center">Tài khoản <b>${esc(Net.username)}</b> · <button class="btn" data-act="logout">Đăng xuất</button></p>`;
  }

  // ---------- Đăng nhập ----------
  function viewLoading() {
    return `<div class="intro">${sprite('shadow_dragon', '', 'Hắc Long')}<h1>Hắc Long</h1><p>Đang kết nối máy chủ...</p></div>`;
  }

  function viewLogin() {
    const reg = authMode === 'register';
    return `
      <div class="intro">
        ${sprite('shadow_dragon', '', 'Hắc Long')}
        <h1>Hắc Long</h1>
        <p>${reg ? 'Tạo tài khoản để lưu nhân vật trên máy chủ và chơi trên mọi thiết bị.' : 'Đăng nhập để tiếp tục hành trình.'}</p>
      </div>
      <form id="auth" class="card">
        <label class="field" for="auth-user">Tên đăng nhập
          <input type="text" id="auth-user" maxlength="20" autocomplete="username" autocapitalize="none" spellcheck="false" required>
        </label>
        <label class="field" for="auth-pass">Mật khẩu
          <input type="password" id="auth-pass" maxlength="72" autocomplete="${reg ? 'new-password' : 'current-password'}" required>
        </label>
        ${reg ? '<p class="small muted">Tên đăng nhập 3–20 ký tự: chữ không dấu, số, dấu gạch dưới. Mật khẩu từ 6 ký tự.</p>' : ''}
        <button class="btn primary block" type="submit" ${busy ? 'disabled' : ''}>${reg ? 'Tạo tài khoản' : 'Đăng nhập'}</button>
        <button class="btn block" type="button" data-auth="${reg ? 'login' : 'register'}">${reg ? 'Đã có tài khoản? Đăng nhập' : 'Chưa có tài khoản? Đăng ký'}</button>
      </form>`;
  }

  // ---------- Làng ----------
  function nextBossIndex() {
    return ZONES.findIndex((z) => !P.bosses.includes(z.boss.id));
  }

  function viewTown() {
    const d = P.view.derived, cost = P.view.restCost, full = P.hp >= d.maxHp;
    const ni = nextBossIndex();
    const pots = ['potion_s', 'potion_m', 'potion_l'].reduce((s, id) => s + (P.inv[id] || 0), 0);
    return `
      <div class="card">
        <div class="row">${icon('campfire', 'lg')}<div class="grow"><h3>Nhà trọ</h3><p class="small muted">Ngủ một đêm để hồi đầy máu.</p></div></div>
        <button class="btn ${full ? '' : 'primary'} block" data-act="rest" ${full ? 'disabled' : ''}>${full ? 'Máu đang đầy' : cost ? `Nghỉ trọ · ${fmt(cost)} vàng` : 'Nghỉ trọ · miễn phí'}</button>
      </div>

      <div class="card">
        <div class="row"><h3 class="grow">Hành trình diệt rồng</h3><span class="tag gold num">${P.bosses.length}/${ZONES.length} trùm</span></div>
        <div class="journey">
          ${ZONES.map((z, i) => `<div class="step ${P.bosses.includes(z.boss.id) ? 'done' : i === ni ? 'next' : ''}">${sprite(z.boss.id, '', z.boss.name)}<span>${z.boss.name}</span></div>`).join('')}
        </div>
        ${ni >= 0 ? `<p class="small muted">Mục tiêu kế tiếp: hạ <b style="color:var(--parch)">${ZONES[ni].boss.name}</b> (cấp ${ZONES[ni].boss.level}) ở ${ZONES[ni].name}.</p>` : '<p class="small" style="color:var(--gold)">Bạn đã hạ tất cả trùm. Vùng đất đã bình yên.</p>'}
        <button class="btn block" data-tab="hunt">${icon('crossed-swords')} Đi săn quái</button>
      </div>

      ${pots === 0 ? `<div class="card"><div class="row">${icon('health-potion', 'lg')}<div class="grow"><h3>Hết bình máu</h3><p class="small muted">Mua vài bình ở cửa hàng trước khi đi săn xa.</p></div><button class="btn" data-tab="shop">Mua</button></div></div>` : ''}

      <div class="card">
        <h3>Thành tích</h3>
        <div class="stat-grid">
          <div class="stat"><span class="small muted">Quái đã hạ</span><b>${fmt(P.kills)}</b></div>
          <div class="stat"><span class="small muted">Số lần gục ngã</span><b>${fmt(P.deaths)}</b></div>
        </div>
      </div>

      <div class="card">
        <h3>Dữ liệu</h3>
        <p class="small muted">Nhân vật lưu trên máy chủ, tài khoản <b>${esc(Net.username)}</b>.</p>
        <div class="btn-row" style="margin-bottom:8px"><button class="btn" data-act="logout">Đăng xuất</button></div>
        ${confirmReset
          ? `<p class="small" style="color:var(--bad)">Xóa nhân vật ${esc(P.name)} và chơi lại từ đầu? Không thể hoàn tác.</p>
             <div class="btn-row"><button class="btn" data-act="reset-cancel">Giữ lại</button><button class="btn danger" data-act="reset-yes">Xóa và chơi lại</button></div>`
          : `<button class="btn" data-act="reset-ask">Chơi lại từ đầu</button>`}
      </div>`;
  }

  function viewVictory() {
    return `
      <div class="card victory">
        ${sprite('shadow_dragon', '', 'Hắc Long đã chết')}
        <h1>Chiến thắng!</h1>
        <p>${esc(P.name)} đã tiêu diệt Hắc Long ở cấp ${P.level} sau ${fmt(P.kills)} trận đánh. Bạn vẫn có thể tiếp tục luyện cấp và săn quái.</p>
      </div>`;
  }

  // ---------- Săn quái ----------
  function viewHunt() {
    return `<h2 class="display">Vùng đất</h2>` + ZONES.map((z, i) => {
      const open = P.view.unlocked[i], cleared = P.bosses.includes(z.boss.id);
      return `
      <div class="card zone ${open ? '' : 'locked'} ${cleared ? 'cleared' : ''}">
        <div class="row">
          ${icon(z.icon, 'lg')}
          <div class="grow">
            <h3>${z.name}</h3>
            <div class="small muted">Cấp ${z.levels}</div>
          </div>
          <span class="tag ${cleared ? 'good' : open ? 'gold' : ''} zone-status">${cleared ? 'Đã hạ trùm' : open ? 'Đã mở' : 'Chưa mở'}</span>
        </div>
        <p class="small muted">${z.desc}</p>
        <div class="mobs">${z.monsters.map((m) => sprite(m.id, '', m.name)).join('')}${sprite(z.boss.id, 'boss', z.boss.name)}</div>
        ${open ? `
          <div class="btn-row">
            <button class="btn primary" data-act="hunt" data-zone="${i}">${icon('crossed-swords')} Săn quái</button>
            <button class="btn" data-act="boss" data-zone="${i}">${icon('crowned-skull')} ${z.boss.final ? 'Đấu Hắc Long' : 'Đấu trùm'} · Cấp ${z.boss.level}</button>
          </div>`
        : `<p class="small">Hạ <b>${ZONES[i - 1].boss.name}</b> để mở.</p>`}
      </div>`;
    }).join('');
  }

  // ---------- Nhân vật ----------
  const STAT_INFO = {
    str: ['Sức mạnh', 'Tăng tấn công'],
    vit: ['Thể lực', 'Tăng máu tối đa'],
    agi: ['Nhanh nhẹn', 'Tăng chí mạng, né, một ít tấn công'],
    def: ['Phòng thủ', 'Giảm sát thương nhận vào'],
  };

  function itemStat(it) {
    if (it.atk) return `Tấn công +${it.atk}`;
    if (it.def) return `Phòng thủ +${it.def}`;
    if (it.heal) return `Hồi ${it.heal} máu`;
    return '';
  }

  function viewHero() {
    const d = P.view.derived, c = CLASSES[P.cls];
    return `
      <div class="card">
        <div class="row">
          ${sprite('hero', '', '')}
          <div class="grow"><h2 class="display">${esc(P.name)}</h2><div class="small muted">${c.name} · Cấp ${P.level}</div></div>
        </div>
        <div class="stat-grid">
          <div class="stat"><span class="small muted">Tấn công</span><b>${d.atk}</b></div>
          <div class="stat"><span class="small muted">Phòng thủ</span><b>${d.def}</b></div>
          <div class="stat"><span class="small muted">Chí mạng</span><b>${Math.round(d.crit * 100)}% <span class="small muted">×${d.critMult.toFixed(2)}</span></b></div>
          <div class="stat"><span class="small muted">Né đòn</span><b>${Math.round(d.dodge * 100)}%</b></div>
        </div>
      </div>

      <div class="card">
        <div class="row"><h3 class="grow">Tiềm năng</h3><span class="tag ${P.points ? 'gold' : ''} num">${P.points} điểm</span></div>
        <p class="small muted">Mỗi lần lên cấp nhận ${RULES.pointsPerLevel} điểm để cộng vào chỉ số.</p>
        <div class="list alloc">
          ${Object.entries(STAT_INFO).map(([k, [n, hint]]) => `
            <div class="item">
              <div class="grow"><div class="name">${n} <span class="num">${P.stats[k]}</span></div><div class="small muted">${hint}</div></div>
              <button class="btn" data-act="alloc" data-stat="${k}" ${P.points ? '' : 'disabled'} aria-label="Cộng 1 điểm ${n}">+1</button>
              <button class="btn" data-act="alloc5" data-stat="${k}" ${P.points >= 5 ? '' : 'disabled'} aria-label="Cộng 5 điểm ${n}">+5</button>
            </div>`).join('')}
        </div>
      </div>

      <div class="card">
        <h3>Trang bị</h3>
        <div class="list">
          ${[['weapon', 'Vũ khí'], ['armor', 'Giáp'], ['shield', 'Khiên']].map(([slot, label]) => {
            const id = P.equip[slot], it = id ? ITEMS[id] : null;
            return `<div class="item">
              ${it ? icon(it.icon, 'lg') : `<span class="ic lg"></span>`}
              <div class="grow"><div class="small muted">${label}</div><div class="name">${it ? it.name : 'Trống'}</div>${it ? `<div class="small muted">${itemStat(it)}</div>` : ''}</div>
              ${slot === 'shield' && it ? `<button class="btn" data-act="unequip" data-slot="shield">Tháo</button>` : ''}
            </div>`;
          }).join('')}
        </div>
      </div>

      <div class="card">
        <div class="row">${icon(c.skill.icon, 'lg')}<div class="grow"><h3>${c.skill.name}</h3><p class="small muted">${c.skill.desc} Hồi chiêu ${c.skill.cooldown} lượt.</p></div></div>
      </div>`;
  }

  // ---------- Túi đồ ----------
  function compare(it) {
    const cur = P.equip[it.slot] ? ITEMS[P.equip[it.slot]] : null;
    const v = (x) => (x ? (x.atk || 0) + (x.def || 0) : 0);
    const diff = v(it) - v(cur);
    return diff > 0 ? `<span class="up">▲ ${diff}</span>` : '';
  }

  function viewBag() {
    const ids = Object.keys(P.inv).filter((id) => P.inv[id] > 0);
    const gear = ids.filter((id) => ITEMS[id].slot !== 'potion');
    const pots = ids.filter((id) => ITEMS[id].slot === 'potion');
    const d = P.view.derived;
    const rowFor = (id) => {
      const it = ITEMS[id], n = P.inv[id];
      const low = it.level && P.level < it.level;
      const main = it.slot === 'potion'
        ? `<button class="btn" data-act="use" data-id="${id}" ${P.hp >= d.maxHp ? 'disabled' : ''}>Dùng</button>`
        : `<button class="btn primary" data-act="equip" data-id="${id}" ${low ? 'disabled' : ''}>Trang bị</button>`;
      return `<div class="item">
        ${icon(it.icon, 'lg')}
        <div class="grow">
          <div class="name">${it.name}${n > 1 ? ` <span class="muted num">×${n}</span>` : ''}</div>
          <div class="small muted">${itemStat(it)} ${it.slot !== 'potion' ? compare(it) : ''}${low ? ` · <span style="color:var(--bad)">Cần cấp ${it.level}</span>` : ''}</div>
        </div>
        ${main}
        <button class="btn" data-act="sell" data-id="${id}" aria-label="Bán ${it.name}">Bán ${fmt(it.sell)}</button>
      </div>`;
    };
    return `
      <div class="card">
        <h3>Bình máu</h3>
        ${pots.length ? `<div class="list">${pots.map(rowFor).join('')}</div>` : `<p class="small muted">Chưa có bình máu. Mua ở cửa hàng.</p>`}
      </div>
      <div class="card">
        <h3>Trang bị trong túi</h3>
        ${gear.length ? `<div class="list">${gear.map(rowFor).join('')}</div>` : `<p class="small muted">Đồ bạn mua hoặc nhặt được sẽ nằm ở đây. Đồ đang mặc xem ở tab Nhân vật.</p>`}
      </div>`;
  }

  // ---------- Cửa hàng ----------
  function viewShop() {
    const groups = [['potion', 'Bình máu'], ['weapon', 'Vũ khí'], ['armor', 'Giáp'], ['shield', 'Khiên']];
    return `<h2 class="display">Lò rèn & Tiệm thuốc</h2>` + groups.map(([slot, title]) => `
      <div class="card">
        <h3>${title}</h3>
        <div class="list">
          ${SHOP.filter((id) => ITEMS[id].slot === slot).map((id) => {
            const it = ITEMS[id];
            const low = it.level && P.level < it.level;
            const worn = P.equip[slot] === id;
            const owned = P.inv[id] || 0;
            const poor = P.gold < it.price;
            return `<div class="item">
              ${icon(it.icon, 'lg')}
              <div class="grow">
                <div class="name">${it.name}</div>
                <div class="small muted">${itemStat(it)} ${slot !== 'potion' ? compare(it) : ''}${low ? ` · <span style="color:var(--bad)">Cần cấp ${it.level}</span>` : ''}${worn ? ' · <span style="color:var(--good)">Đang dùng</span>' : ''}${owned ? ` · có ${owned}` : ''}</div>
              </div>
              ${slot === 'potion' ? `<button class="btn" data-act="buy5" data-id="${id}" ${P.gold < it.price * 5 ? 'disabled' : ''}>×5</button>` : ''}
              <button class="btn ${!low && !poor ? 'primary' : ''}" data-act="buy" data-id="${id}" ${low || poor ? 'disabled' : ''}>${icon('two-coins')}${fmt(it.price)}</button>
            </div>`;
          }).join('')}
        </div>
      </div>`).join('') + `<p class="small muted">Trùm Vua Khổng Lồ và Kim Long giữ những món đồ không bán ở đây.</p>`;
  }

  // ---------- Trận đấu ----------
  function viewBattle() {
    const b = P.battle, m = b.monster, d = P.view.derived, z = ZONES[b.zone];
    const skill = CLASSES[P.cls].skill;
    const pots = ['potion_s', 'potion_m', 'potion_l'].reduce((s, id) => s + (P.inv[id] || 0), 0);
    const floatHtml = fx && fx.mDmg != null
      ? `<span class="float ${fx.crit ? 'crit' : ''} ${fx.mDmg === 0 ? 'miss' : ''}">${fx.mDmg === 0 ? 'Trượt' : '-' + fmt(fx.mDmg)}</span>` : '';
    let bottom;
    if (!b.over) {
      bottom = `
        <div class="actions">
          <button class="btn primary" data-act="attack">${icon('broadsword')} Tấn công</button>
          <button class="btn" data-act="skill" ${b.skillCd ? 'disabled' : ''}>${icon(skill.icon)} ${skill.name}${b.skillCd ? ` (${b.skillCd})` : ''}</button>
          <button class="btn" data-act="potion" ${pots && P.hp < d.maxHp ? '' : 'disabled'}>${icon('health-potion')} Uống máu (${pots})</button>
          <button class="btn" data-act="flee">${icon('walk')} Bỏ chạy</button>
        </div>`;
    } else {
      const r = b.result, rw = b.reward;
      const title = r === 'win' ? (m.final ? 'Hắc Long đã chết!' : 'Chiến thắng!') : r === 'lose' ? 'Gục ngã' : 'Đã thoát';
      bottom = `
        <div class="card result ${r}">
          <h2>${title}</h2>
          ${rw ? `<p class="num">+${fmt(rw.xp)} kinh nghiệm · +${fmt(rw.gold)} vàng${rw.items.length ? ' · ' + rw.items.map((id) => ITEMS[id].name).join(', ') : ''}</p>` : ''}
          ${rw && rw.levels ? `<p style="color:var(--gold);font-weight:600">Lên cấp ${P.level}! Vào tab Nhân vật để cộng điểm.</p>` : ''}
          <div class="btn-row">
            ${!m.boss && r !== 'lose' ? `<button class="btn primary" data-act="again">${icon('crossed-swords')} Đánh tiếp</button>` : ''}
            <button class="btn" data-act="leave">${icon('village')} Về làng</button>
          </div>
          ${!m.boss && r !== 'lose' && P.hp < d.maxHp * 0.35 ? '<p class="small" style="color:var(--bad)">Máu đang thấp. Nên uống máu hoặc về làng nghỉ.</p>' : ''}
        </div>`;
    }
    return `
      <div class="stage ${m.boss ? 'boss' : ''}" style="background-image:url('${asset('floors/' + z.id + '.png')}')">
        <span class="eyebrow">${z.name}${m.boss ? ' · Trùm' : ''}</span>
        ${sprite(m.id, fx && fx.mDmg ? 'hit' : '', m.name)}
        ${floatHtml}
        <h2>${m.name}</h2>
        <span class="small muted">Cấp ${m.level} · Tấn công ${m.atk} · Phòng thủ ${m.def}${m.special ? ` · ${m.special.name} mỗi ${m.special.every} lượt` : ''}</span>
        ${bar(m.boss ? 'boss' : 'hp', m.hp, m.maxHp)}
      </div>
      <div class="me ${fx && fx.pDmg ? 'hurt' : ''}">
        ${sprite('hero', '', '')}
        <div class="grow" style="flex:1;min-width:0">${bar('hp', P.hp, d.maxHp, `${esc(P.name)} · ${fmt(P.hp)} / ${fmt(d.maxHp)}`)}</div>
      </div>
      <div class="log" aria-live="polite">${b.log.map((l) => `<div class="${l.kind}">${esc(l.text)}</div>`).join('')}</div>
      ${bottom}`;
  }

  // ---------- Xử lý thao tác ----------
  // Ghi lại trạng thái trước một lượt đánh để tính hiệu ứng (số sát thương bay lên, rung).
  function snapBattle() {
    return { mHp: P.battle.monster.hp, pHp: P.hp, logLen: P.battle.log.length };
  }

  function battleFx(before, action) {
    if (!P || !P.battle) return;
    // Nhật ký giới hạn 60 dòng; khi đã đầy thì xem vài dòng cuối.
    const newLog = before.logLen < 60 ? P.battle.log.slice(before.logLen) : P.battle.log.slice(-4);
    const struck = action === 'attack' || action === 'skill';
    fx = {
      mDmg: struck ? before.mHp - P.battle.monster.hp : null,
      pDmg: before.pHp - P.hp > 0 ? before.pHp - P.hp : 0,
      crit: newLog.some((l) => l.kind === 'crit'),
    };
  }

  // Tên thao tác của nút → lệnh gửi server (xem lib/hac_long/game/commands.ex).
  function command(act, t) {
    const d = t.dataset;
    switch (act) {
      case 'hunt': case 'boss': return { act, zone: +d.zone };
      case 'alloc': return { act, stat: d.stat, n: 1 };
      case 'alloc5': return { act: 'alloc', stat: d.stat, n: 5 };
      case 'buy': return { act, id: d.id, n: 1 };
      case 'buy5': return { act: 'buy', id: d.id, n: 5 };
      case 'equip': case 'use': case 'sell': return { act, id: d.id };
      case 'unequip': return { act, slot: d.slot };
      case 'reset-yes': return { act: 'reset' };
      default: return { act };
    }
  }

  async function sendCommand(cmd) {
    if (busy) return;
    busy = true;
    const battle = ['attack', 'skill', 'potion', 'flee'].includes(cmd.act) && P && P.battle;
    const before = battle ? snapBattle() : null;
    const scroll = $('#view').scrollTop;
    try {
      const r = await Net.send(cmd);
      P = r.player;
      result(r);
      if (r.ok) {
        if (before) battleFx(before, cmd.act);
        if (cmd.act === 'leave' || cmd.act === 'reset' || cmd.act === 'create') { tab = 'town'; confirmReset = false; }
      }
    } catch (e) {
      toast(e.msg, true);
    }
    busy = false;
    render();
    if (cmd.act === 'create' || cmd.act === 'reset') $('#view').scrollTop = 0;
    else if (!P || !P.battle) $('#view').scrollTop = scroll;
  }

  function enter(r) {
    P = r ? r.player : null;
    tab = 'town';
    loading = false;
    render();
  }

  function logout() {
    Net.logout();
    P = null;
    confirmReset = false;
    render();
  }

  function onClick(e) {
    const t = e.target.closest('button');
    if (!t) return;
    if (t.dataset.cls) { pickCls = t.dataset.cls; document.querySelectorAll('.class-opt').forEach((b) => b.setAttribute('aria-pressed', b.dataset.cls === pickCls)); return; }
    if (t.dataset.tab) { tab = t.dataset.tab; confirmReset = false; render(); $('#view').scrollTop = 0; return; }
    if (t.dataset.auth) { authMode = t.dataset.auth; render(); return; }
    const act = t.dataset.act;
    if (act === 'logout') return logout();
    if (!act || !P) return;
    if (act === 'reset-ask' || act === 'reset-cancel') { confirmReset = act === 'reset-ask'; render(); return; }
    sendCommand(command(act, t));
  }

  async function onAuth() {
    if (busy) return;
    const user = $('#auth-user').value.trim(), pass = $('#auth-pass').value;
    if (!user || !pass) { toast('Nhập tên đăng nhập và mật khẩu.', true); return; }
    busy = true;
    try {
      enter(await Net.login(user, pass, authMode === 'register'));
      toast(authMode === 'register' ? 'Đã tạo tài khoản.' : `Xin chào ${Net.username}!`);
    } catch (err) {
      toast(err.msg, true);
    }
    busy = false;
  }

  function onSubmit(e) {
    if (e.target.id === 'auth') { e.preventDefault(); onAuth(); return; }
    if (e.target.id !== 'create') return;
    e.preventDefault();
    const name = $('#hero-name').value.trim();
    if (!name) { toast('Hãy đặt tên cho nhân vật.', true); return; }
    sendCommand({ act: 'create', name, cls: pickCls });
  }

  function start() {
    document.addEventListener('click', onClick);
    document.addEventListener('submit', onSubmit);
    Net.onPlayer((p) => { if (!busy) { P = p; render(); } });
    render();
    Net.resume().then(enter).catch((e) => { toast(e.msg, true); enter(null); });
  }

  start();
})();
