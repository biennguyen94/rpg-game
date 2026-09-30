/* Giao diện: vẽ lại từng màn hình từ trạng thái người chơi (P) do server gửi về.
 * Mọi thao tác gửi lên server qua Net (net.js); server tính toán rồi trả trạng thái mới.
 * P.view chứa các chỉ số server tính sẵn (máu tối đa, tấn công, giá nghỉ trọ...). */
(function () {
  const { CLASSES, ZONES, ITEMS, RULES, RECIPES, QUESTS, WORLD } = window.GAME_DATA;
  const Net = window.Net;

  let P = null;          // trạng thái người chơi
  let tab = 'map';       // tab đang mở
  let pickCls = 'warrior';
  let confirmReset = false;
  let fx = null;         // hiệu ứng trận đấu của lượt vừa rồi
  let authMode = 'login'; // 'login' | 'register'
  let loading = true;    // đang kết nối server
  let busy = false;      // đang chờ server trả lời
  let walk = null;       // đích đang đi tới trên bản đồ: { x, y, monster, id }
  let dialog = null;     // bảng trên bản đồ: { type: 'boss', dir, boss } | { type: 'waystone' }
  let npc = null;        // NPC đang nói chuyện: { map, id, line }
  let pwForm = false;    // đang mở form đổi mật khẩu
  let chats = [];        // tin chat gần nhất
  let chatDraft = '';    // chữ đang gõ dở (giữ lại khi vẽ lại trang)
  let board = { kind: 'level', data: null, at: 0 }; // bảng xếp hạng
  let wb = { alive: false }; // trùm thế giới; `skew`: lệch đồng hồ máy chủ - máy này
  const Map_ = window.MapView;

  const $ = (s) => document.querySelector(s);
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const fmt = (n) => Math.round(n).toLocaleString('vi-VN');

  const asset = (path) => 'assets/' + path;
  const icon = (name, cls) => `<img class="ic ${cls || ''}" src="${asset('icons/' + name + '.svg')}" alt="">`;
  // Hình vật phẩm: nguyên liệu dùng ảnh PNG (`sprite`), còn lại dùng icon SVG.
  const itemIcon = (it) => (it.sprite ? `<img class="ic lg px" src="${asset(it.sprite + '.png')}" alt="">` : icon(it.icon, 'lg'));
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
      ['map', 'walk', 'Bản đồ'],
      ['town', 'trophy', 'Hành trình'],
      ['hero', 'person', 'Nhân vật'],
      ['bag', 'backpack', 'Túi đồ'],
      ['quests', 'scroll-unfurled', 'Nhiệm vụ'],
    ].map(([id, ic, label]) => `<button data-tab="${id}" ${tab === id ? 'aria-current="page"' : ''}>${icon(ic)}<span>${label}${id === 'hero' && P.points ? `<span class="points-dot">${P.points}</span>` : ''}</span></button>`).join('');
    view.innerHTML = P.victory && tab === 'town' ? viewVictory() + viewTown() : ({ map: () => (npc ? viewNpc() : viewBossBanner() + Map_.html(P, viewDialog()) + viewChat()), town: viewTown, hero: viewHero, bag: viewBag, quests: viewQuests }[tab])();
    if (tab === 'map' && !npc) {
      Map_.mount(() => P);
      const log = $('#chat-log');
      if (log) log.scrollTop = log.scrollHeight;
    }
    if (tab === 'town') loadBoard();
  }

  // Bảng nổi trên bản đồ: hỏi đấu trùm, chọn nơi dịch chuyển.
  function viewDialog() {
    if (!dialog) return '';
    if (dialog.type === 'boss') {
      const b = dialog.boss, weak = P.level < b.level - 1;
      return `<div class="map-dialog card">
        <div class="row">${sprite(b.id, '', b.name)}<div class="grow"><h3>Đấu ${esc(b.name)}?</h3><p class="small muted">Trùm cấp ${b.level}.${weak ? ` <span style="color:var(--bad)">Bạn mới cấp ${P.level}, nên luyện thêm.</span>` : ''}</p></div></div>
        <div class="btn-row"><button class="btn" data-act="dialog-close">Thôi</button><button class="btn primary" data-act="boss-yes">${icon('crowned-skull')} Đấu</button></div>
      </div>`;
    }
    const W = window.GAME_DATA.WORLD.maps;
    const places = ['village'].concat(P.waystones || []);
    return `<div class="map-dialog card">
      <h3>Đá dịch chuyển</h3>
      <p class="small muted">Chạm vào đá ở nơi khác để ghi nhớ nó.</p>
      <div class="list">${places.map((id) => `<button class="btn" data-act="teleport" data-to="${id}" ${id === P.pos.map ? 'disabled' : ''}>${esc(W[id].name)}${id === P.pos.map ? ' · đang ở đây' : ''}</button>`).join('')}</div>
      <button class="btn" data-act="dialog-close">Đóng</button>
    </div>`;
  }

  // ---------- Trùm thế giới ----------
  const clock = (ms) => { const t = Math.max(0, Math.round(ms / 1000)); return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`; };

  function viewBossBanner() {
    if (!wb.alive) return '';
    const pct = Math.max(0, Math.round((wb.hp / wb.maxHp) * 100));
    const here = P.pos.map === 'altar';
    return `<div class="card wb" id="wb">
      <div class="row">${sprite('ancient_dragon', '', wb.name)}<div class="grow">
        <b>${esc(wb.name)}</b> <span class="small muted">${here ? 'ngay trước mặt' : 'ở Tế Đàn (cổng dưới bên trái Làng)'}</span>
        ${bar('boss', wb.hp, wb.maxHp, `${pct}% · còn <span id="wb-left">${clock(wb.endsAt - wb.skew - Date.now())}</span> · ${wb.fighters} người đánh`)}
      </div></div>
      ${here && wb.top.length ? `<ol class="board">${wb.top.map((t, i) => `<li class="${t.id === Net.userId ? 'me' : ''}"><span class="num rank">${i + 1}</span><span class="grow">${esc(t.name)}</span><span class="num">${fmt(t.dmg)}</span></li>`).join('')}</ol>` : ''}
    </div>`;
  }

  function onWorldBoss(st) {
    const wasAlive = wb.alive;
    wb = Object.assign(st, { skew: st.now - Date.now() });
    Map_.setBoss(wb);
    // đang đánh trùm: thanh máu theo máu chung
    if (P && P.battle && P.battle.monster.world && !P.battle.over && wb.alive) {
      P.battle.monster.hp = wb.hp;
      render();
      return;
    }
    if (!P || P.battle) return;
    if (tab === 'map' && !npc) {
      const el = $('#wb');
      if (el && wb.alive) el.outerHTML = viewBossBanner();
      else if (el || wb.alive !== wasAlive) render();
    }
  }

  // ---------- Chat ----------
  const mapName = (id) => (WORLD.maps[id] ? WORLD.maps[id].name : id);

  function chatLine(m) {
    if (!m.uid) return `<div class="chat-line system">${esc(m.text)}</div>`;
    const mine = m.uid === Net.userId;
    return `<div class="chat-line ${mine ? 'mine' : ''}"><b>${esc(m.name)}</b> <span class="muted small">${esc(mapName(m.map))}</span> ${esc(m.text)}</div>`;
  }

  function viewChat() {
    return `<div class="card chat">
      <div class="chat-log" id="chat-log" aria-live="polite">${chats.length ? chats.map(chatLine).join('') : '<p class="small muted">Chưa có ai nói gì. Chào mọi người đi!</p>'}</div>
      <form id="chat-form" class="chat-form" autocomplete="off">
        <input type="text" id="chat-input" maxlength="120" placeholder="Nói với mọi người…" value="${esc(chatDraft)}" aria-label="Tin nhắn">
        <button class="btn" type="submit">Gửi</button>
      </form>
    </div>`;
  }

  function onChatMessage(m) {
    chats.push(m);
    if (chats.length > 50) chats.shift();
    // người nói đang ở cùng bản đồ thì hiện bong bóng trên đầu
    if (P && m.map === P.pos.map) Map_.say(m.uid, m.text);
    const log = $('#chat-log');
    if (log) {
      const atBottom = log.scrollHeight - log.scrollTop - log.clientHeight < 30;
      log.innerHTML = chats.map(chatLine).join('');
      if (atBottom || m.uid === Net.userId) log.scrollTop = log.scrollHeight;
    }
  }

  async function onChatSubmit() {
    const input = $('#chat-input');
    const text = input.value.trim();
    if (!text) return;
    try {
      await Net.chat(text);
      input.value = ''; chatDraft = '';
    } catch (err) {
      toast(err.msg, true);
    }
  }

  // ---------- Bảng xếp hạng ----------
  async function loadBoard(force) {
    if (!force && board.data && Date.now() - board.at < 30000) return;
    board.at = Date.now();
    try {
      board.data = await Net.leaderboard();
      if (tab === 'town') {
        const el = $('#board');
        if (el) el.outerHTML = viewBoard();
      }
    } catch (err) { /* thử lại lần sau */ }
  }

  function viewBoard() {
    const kinds = [['level', 'Cấp cao'], ['kills', 'Săn nhiều'], ['dragon', 'Diệt rồng']];
    const rows = board.data ? board.data[board.kind] : null;
    const value = (r) => (board.kind === 'level' ? `Cấp ${r.level}` : board.kind === 'kills' ? `${fmt(r.kills)} quái` : new Date(r.victory_at).toLocaleDateString('vi-VN'));
    return `<div class="card" id="board">
      <div class="row"><h3 class="grow">Bảng xếp hạng</h3>${board.data && board.data.me ? `<span class="tag gold num">Bạn hạng ${board.data.me}</span>` : ''}</div>
      <div class="seg">${kinds.map(([k, label]) => `<button class="btn ${board.kind === k ? 'primary' : ''}" data-board="${k}">${label}</button>`).join('')}</div>
      ${rows == null ? '<p class="small muted">Đang tải…</p>'
        : rows.length === 0 ? `<p class="small muted">${board.kind === 'dragon' ? 'Chưa ai hạ được Hắc Long. Bạn sẽ là người đầu tiên?' : 'Chưa có ai.'}</p>`
        : `<ol class="board">${rows.map((r) => `<li class="${r.user_id === Net.userId ? 'me' : ''}"><span class="num rank">${r.rank}</span><span class="grow">${esc(r.name)} <span class="small muted">${CLASSES[r.cls] ? CLASSES[r.cls].name : ''}</span></span><span class="num">${value(r)}</span></li>`).join('')}</ol>`}
    </div>`;
  }

  // Cập nhật nhẹ khi đang xem bản đồ (không dựng lại cả trang, tránh nháy).
  function refresh() {
    if (P && !P.battle && tab === 'map' && !npc && Map_.mountedMap() === P.pos.map && $('#map-canvas')) {
      $('#hud').innerHTML = viewHud();
      Map_.draw();
    } else {
      render();
    }
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
        <div class="row">${icon('campfire', 'lg')}<div class="grow"><h3>Hồi máu</h3><p class="small muted">${full ? 'Máu đang đầy.' : `Gặp Chủ Quán Trọ ở Làng để nghỉ${cost ? ` (${fmt(cost)} vàng)` : ' (miễn phí)'}, hoặc về Nhà uống nước giếng.`}</p></div></div>
      </div>

      <div class="card">
        <div class="row"><h3 class="grow">Hành trình diệt rồng</h3><span class="tag gold num">${P.bosses.length}/${ZONES.length} trùm</span></div>
        <div class="journey">
          ${ZONES.map((z, i) => `<div class="step ${P.bosses.includes(z.boss.id) ? 'done' : i === ni ? 'next' : ''}">${sprite(z.boss.id, '', z.boss.name)}<span>${z.boss.name}</span></div>`).join('')}
        </div>
        ${ni >= 0 ? `<p class="small muted">Mục tiêu kế tiếp: hạ <b style="color:var(--parch)">${ZONES[ni].boss.name}</b> (cấp ${ZONES[ni].boss.level}) ở ${ZONES[ni].name}.</p>` : '<p class="small" style="color:var(--gold)">Bạn đã hạ tất cả trùm. Vùng đất đã bình yên.</p>'}
        <button class="btn block" data-tab="map">${icon('walk')} Ra bản đồ</button>
      </div>

      ${pots === 0 ? `<div class="card"><div class="row">${icon('health-potion', 'lg')}<div class="grow"><h3>Hết bình máu</h3><p class="small muted">Mua ở Bà Lang trong Làng, hoặc hái Thảo Dược nhờ bà pha.</p></div></div></div>` : ''}

      ${wb.alive ? '' : wb.nextAt ? `<div class="card"><div class="row">${sprite('ancient_dragon', '', '')}<div class="grow"><h3>Trùm thế giới</h3><p class="small muted">${esc(wb.name)} sẽ xuất hiện ở Tế Đàn sau khoảng ${Math.max(1, Math.round((wb.nextAt - wb.skew - Date.now()) / 60000))} phút. Cả server cùng đánh, chia thưởng theo sát thương.</p></div></div></div>` : ''}
      ${viewBoard()}

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
        <div class="btn-row" style="margin-bottom:8px">
          <button class="btn" data-act="logout">Đăng xuất</button>
          <button class="btn" data-act="pw-toggle">Đổi mật khẩu</button>
        </div>
        ${pwForm ? `<form id="pw-form" class="pw-form">
          <label class="field" for="pw-cur">Mật khẩu hiện tại<input type="password" id="pw-cur" autocomplete="current-password" required></label>
          <label class="field" for="pw-new">Mật khẩu mới<input type="password" id="pw-new" autocomplete="new-password" minlength="6" maxlength="72" required></label>
          <p class="small muted">Đổi xong, các thiết bị khác sẽ bị đăng xuất.</p>
          <button class="btn primary" type="submit">Lưu mật khẩu mới</button>
        </form>` : ''}
        <button class="btn" data-act="logout-all" style="margin-bottom:8px">Đăng xuất mọi thiết bị</button>
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
    const gear = ids.filter((id) => !['potion', 'material'].includes(ITEMS[id].slot));
    const pots = ids.filter((id) => ITEMS[id].slot === 'potion');
    const mats = ids.filter((id) => ITEMS[id].slot === 'material');
    const d = P.view.derived;
    const rowFor = (id) => {
      const it = ITEMS[id], n = P.inv[id];
      const low = it.level && P.level < it.level;
      const main = it.slot === 'potion'
        ? `<button class="btn" data-act="use" data-id="${id}" ${P.hp >= d.maxHp ? 'disabled' : ''}>Dùng</button>`
        : it.slot === 'material' ? ''
        : `<button class="btn primary" data-act="equip" data-id="${id}" ${low ? 'disabled' : ''}>Trang bị</button>`;
      return `<div class="item">
        ${itemIcon(it)}
        <div class="grow">
          <div class="name">${it.name}${n > 1 ? ` <span class="muted num">×${n}</span>` : ''}</div>
          <div class="small muted">${it.slot === 'material' ? it.desc : itemStat(it)} ${['potion', 'material'].includes(it.slot) ? '' : compare(it)}${low ? ` · <span style="color:var(--bad)">Cần cấp ${it.level}</span>` : ''}</div>
        </div>
        ${main}
      </div>`;
    };
    return `
      <div class="card">
        <h3>Bình máu</h3>
        ${pots.length ? `<div class="list">${pots.map(rowFor).join('')}</div>` : `<p class="small muted">Chưa có bình máu. Mua ở Bà Lang trong Làng.</p>`}
      </div>
      <div class="card">
        <h3>Nguyên liệu</h3>
        ${mats.length ? `<div class="list">${mats.map(rowFor).join('')}</div>` : `<p class="small muted">Bước vào bụi cây để hái Thảo Dược, vào mỏ đá để đào quặng. Mang cho Bà Lang pha thuốc hoặc bán cho Thợ Rèn.</p>`}
      </div>
      <div class="card">
        <h3>Trang bị trong túi</h3>
        ${gear.length ? `<div class="list">${gear.map(rowFor).join('')}</div>` : `<p class="small muted">Đồ bạn mua hoặc nhặt được sẽ nằm ở đây. Đồ đang mặc xem ở tab Nhân vật.</p>`}
      </div>
      <p class="small muted">Muốn bán đồ thì gặp Thợ Rèn hoặc Bà Lang trong Làng.</p>`;
  }

  // ---------- NPC ----------
  const npcData = () => WORLD.maps[npc.map].npcs.find((n) => n.id === npc.id);

  function shopRow(id) {
    const it = ITEMS[id], slot = it.slot;
    const low = it.level && P.level < it.level;
    const worn = P.equip[slot] === id;
    const owned = P.inv[id] || 0;
    const poor = P.gold < it.price;
    return `<div class="item">
      ${itemIcon(it)}
      <div class="grow">
        <div class="name">${it.name}</div>
        <div class="small muted">${itemStat(it)} ${slot !== 'potion' ? compare(it) : ''}${low ? ` · <span style="color:var(--bad)">Cần cấp ${it.level}</span>` : ''}${worn ? ' · <span style="color:var(--good)">Đang dùng</span>' : ''}${owned ? ` · có ${owned}` : ''}</div>
      </div>
      ${slot === 'potion' ? `<button class="btn" data-act="buy5" data-id="${id}" ${P.gold < it.price * 5 ? 'disabled' : ''}>×5</button>` : ''}
      <button class="btn ${!low && !poor ? 'primary' : ''}" data-act="buy" data-id="${id}" ${low || poor ? 'disabled' : ''}>${icon('two-coins')}${fmt(it.price)}</button>
    </div>`;
  }

  function sellCard() {
    const ids = Object.keys(P.inv).filter((id) => P.inv[id] > 0);
    return `<div class="card"><h3>Bán đồ</h3>
      ${ids.length ? `<div class="list">${ids.map((id) => {
        const it = ITEMS[id], n = P.inv[id];
        return `<div class="item">${itemIcon(it)}<div class="grow"><div class="name">${it.name}${n > 1 ? ` <span class="muted num">×${n}</span>` : ''}</div></div>
          <button class="btn" data-act="sell" data-id="${id}" aria-label="Bán ${it.name}">Bán ${fmt(it.sell)}</button></div>`;
      }).join('')}</div>` : '<p class="small muted">Túi trống. Đồ đang mặc không bán được.</p>'}
    </div>`;
  }

  function craftCard() {
    return `<div class="card"><h3>Pha thuốc</h3><div class="list">${RECIPES.filter((r) => r.npc === 'herbalist').map((r) => {
      const out = ITEMS[r.out];
      const needs = Object.entries(r.needs);
      const ok = needs.every(([id, n]) => (P.inv[id] || 0) >= n);
      return `<div class="item">${itemIcon(out)}<div class="grow"><div class="name">${out.name}</div>
        <div class="small muted">${needs.map(([id, n]) => `${ITEMS[id].name} ${Math.min(P.inv[id] || 0, n)}/${n}`).join(' · ')}</div></div>
        <button class="btn ${ok ? 'primary' : ''}" data-act="craft" data-id="${r.id}" ${ok ? '' : 'disabled'}>Pha</button></div>`;
    }).join('')}</div></div>`;
  }

  // Tiến độ nhiệm vụ đang làm (server vẫn là nơi kiểm tra cuối cùng).
  function questProgress(q) {
    const have = q.type === 'kill' ? (P.quests.active[q.id] || 0)
      : q.type === 'collect' ? (P.inv[q.target] || 0)
      : P.bosses.includes(q.target) ? 1 : 0;
    return [Math.min(have, q.count), q.count];
  }

  function questRow(q, action) {
    const reward = [`${fmt(q.reward.gold)} vàng`, `${fmt(q.reward.xp)} kinh nghiệm`]
      .concat(Object.entries(q.reward.items).map(([id, n]) => `${ITEMS[id].name} ×${n}`)).join(' · ');
    let right = '', progress = '';
    if (action !== 'accept') {
      const [have, need] = questProgress(q);
      progress = `<div class="small ${have >= need ? '' : 'muted'}" style="${have >= need ? 'color:var(--good)' : ''}">${have >= need ? 'Đã xong, về báo Trưởng Làng' : `Tiến độ ${have}/${need}`}</div>`;
      if (action === 'turnin') right = `<button class="btn ${have >= need ? 'primary' : ''}" data-act="quest_turnin" data-id="${q.id}" ${have >= need ? '' : 'disabled'}>Trả</button>`;
    } else {
      right = `<button class="btn primary" data-act="quest_accept" data-id="${q.id}">Nhận</button>`;
    }
    return `<div class="item quest"><div class="grow">
      <div class="name">${q.name} <span class="small muted">· ${ZONES[q.zone].name}</span></div>
      <div class="small muted">${q.desc}</div>
      ${progress}
      <div class="small" style="color:var(--gold)">Thưởng: ${reward}</div>
    </div>${right}</div>`;
  }

  const activeQuests = () => QUESTS.filter((q) => q.id in P.quests.active);
  const availableQuests = () => QUESTS.filter((q) => !(q.id in P.quests.active) && !P.quests.done.includes(q.id)
    && P.view.unlocked[q.zone] && q.requires.every((r) => P.quests.done.includes(r)));

  // ---------- Việc hằng ngày ----------
  function dailyLeft() {
    const s = P.view.dailyLeft, h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
    return h ? `${h} giờ ${m} phút` : `${m} phút`;
  }

  function dailyList(claim) {
    const tasks = (P.daily && P.daily.tasks) || [];
    return `<div class="list">${tasks.map((t, i) => {
      const done = t.progress >= t.count;
      const right = t.claimed ? '<span class="tag good">Đã nhận</span>'
        : claim ? `<button class="btn ${done ? 'primary' : ''}" data-act="daily_claim" data-i="${i}" ${done ? '' : 'disabled'}>Nhận</button>` : '';
      return `<div class="item quest"><div class="grow">
        <div class="name">${esc(t.name)} <span class="small muted">· ${ZONES[t.zone].name}</span></div>
        <div class="small ${done ? '' : 'muted'}" style="${done && !t.claimed ? 'color:var(--good)' : ''}">${t.claimed ? 'Xong' : done ? 'Đã xong, đến Bảng Tin nhận thưởng' : `Tiến độ ${t.progress}/${t.count}`}</div>
        <div class="small" style="color:var(--gold)">Thưởng: ${fmt(t.reward.gold)} vàng · ${fmt(t.reward.xp)} kinh nghiệm</div>
      </div>${right}</div>`;
    }).join('')}</div>`;
  }

  function viewNpc() {
    const n = npcData(), d = P.view.derived;
    const sections = [];
    if (n.role === 'quests') {
      const act = activeQuests(), avail = availableQuests();
      sections.push(`<div class="card"><h3>Nhiệm vụ đang làm</h3>${act.length ? `<div class="list">${act.map((q) => questRow(q, 'turnin')).join('')}</div>` : '<p class="small muted">Chưa nhận nhiệm vụ nào.</p>'}</div>`);
      sections.push(`<div class="card"><h3>Việc cần người giúp</h3>${avail.length ? `<div class="list">${avail.map((q) => questRow(q, 'accept')).join('')}</div>` : '<p class="small muted">Hiện chưa có việc mới. Mở thêm vùng đất để nhận thêm nhiệm vụ.</p>'}</div>`);
    }
    if (n.role === 'shop' || n.role === 'herbalist') {
      if (n.role === 'herbalist') sections.push(craftCard());
      sections.push(`<div class="card"><h3>Mua</h3><div class="list">${n.stock.map(shopRow).join('')}</div></div>`);
      sections.push(sellCard());
    }
    if (n.role === 'inn') {
      const full = P.hp >= d.maxHp, cost = P.view.restCost;
      sections.push(`<div class="card"><button class="btn ${full ? '' : 'primary'} block" data-act="rest" ${full ? 'disabled' : ''}>${full ? 'Máu đang đầy' : cost ? `Nghỉ một đêm · ${fmt(cost)} vàng` : 'Nghỉ một đêm · miễn phí'}</button></div>`);
    }
    if (n.role === 'daily') {
      sections.push(`<div class="card"><div class="row"><h3 class="grow">Việc hôm nay</h3><span class="small muted">Việc mới sau ${dailyLeft()}</span></div>${dailyList(true)}</div>`);
    }
    if (n.role === 'talk') {
      sections.push(`<div class="card">${n.lines.map((l) => `<p>“${esc(l)}”</p>`).join('')}</div>`);
    }
    return `
      <div class="card npc-head">
        <div class="row"><img class="sprite" src="${asset('npcs/' + n.sprite + '.png')}" alt="${esc(n.name)}"><div class="grow"><h2 class="display">${esc(n.name)}</h2>
        ${n.role !== 'talk' ? `<p class="small muted">“${esc(npc.line)}”</p>` : ''}</div></div>
      </div>
      ${sections.join('')}
      <button class="btn block" data-act="npc-close">${icon('walk')} Rời đi</button>`;
  }

  // ---------- Nhiệm vụ ----------
  function viewQuests() {
    const act = activeQuests();
    return `<h2 class="display">Nhiệm vụ</h2>
      <div class="card"><div class="row"><h3 class="grow">Việc hằng ngày</h3><span class="small muted">Việc mới sau ${dailyLeft()}</span></div>
        ${dailyList(false)}
        <p class="small muted">Tự tính khi bạn làm; xong thì đến Bảng Tin trong Làng nhận thưởng.</p>
      </div>
      <h3>Nhiệm vụ của Trưởng Làng</h3>
      <div class="card">${act.length ? `<div class="list">${act.map((q) => questRow(q, 'log')).join('')}</div>` : '<p class="small muted">Chưa nhận nhiệm vụ nào. Gặp Trưởng Làng (ông già ở giữa Làng, phía trên) để nhận việc.</p>'}</div>
      <p class="small muted">Đã hoàn thành ${P.quests.done.length}/${QUESTS.length} nhiệm vụ.${availableQuests().length ? ` Trưởng Làng đang có ${availableQuests().length} việc mới.` : ''}</p>`;
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
            <button class="btn primary" data-act="leave">${r === 'lose' ? `${icon('village')} Về nhà` : `${icon('walk')} Tiếp tục`}</button>
          </div>
          ${r !== 'lose' && P.hp < d.maxHp * 0.35 ? '<p class="small" style="color:var(--bad)">Máu đang thấp. Nên uống máu hoặc về Nhà uống nước giếng.</p>' : ''}
        </div>`;
    }
    return `
      <div class="stage ${m.boss ? 'boss' : ''} ${m.world ? 'world' : ''}" style="background-image:url('${asset('floors/' + z.id + '.png')}')">
        <span class="eyebrow">${m.world ? 'Trùm thế giới · Tế Đàn' : z.name + (m.boss ? ' · Trùm' : '')}</span>
        ${sprite(m.id, fx && fx.mDmg ? 'hit' : '', m.name)}
        ${floatHtml}
        <h2>${m.name}</h2>
        <span class="small muted">Cấp ${m.level} · Tấn công ${m.atk} · Phòng thủ ${m.def}${m.special ? ` · ${m.special.name} mỗi ${m.special.every} lượt` : ''}</span>
        ${bar(m.boss || m.world ? 'boss' : 'hp', m.hp, m.maxHp)}
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
      case 'alloc': return { act, stat: d.stat, n: 1 };
      case 'alloc5': return { act: 'alloc', stat: d.stat, n: 5 };
      case 'buy': return { act, id: d.id, n: 1 };
      case 'buy5': return { act: 'buy', id: d.id, n: 5 };
      case 'equip': case 'use': case 'sell': return { act, id: d.id };
      case 'unequip': return { act, slot: d.slot };
      case 'reset-yes': return { act: 'reset' };
      case 'teleport': return { act, to: d.to };
      case 'craft': case 'quest_accept': case 'quest_turnin': return { act, id: d.id };
      case 'daily_claim': return { act, i: +d.i };
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
        if (cmd.act === 'leave' || cmd.act === 'create') tab = 'map';
        if (cmd.act === 'reset') tab = 'map';
        confirmReset = false;
        dialog = null;
      }
    } catch (e) {
      toast(e.msg, true);
    }
    busy = false;
    render();
    if (cmd.act === 'create' || cmd.act === 'reset') $('#view').scrollTop = 0;
    else if (!P || !P.battle) $('#view').scrollTop = scroll;
  }

  // ---------- Đi trên bản đồ ----------
  // Một bước: gửi lên server, server kiểm tra rồi trả vị trí mới (hoặc bắt đầu trận).
  async function step(dir, confirm) {
    if (busy || !P || P.battle) return false;
    busy = true;
    const mapBefore = P.pos.map, hadDialog = !!dialog;
    dialog = null;
    let ok = false;
    try {
      const r = await Net.send(confirm ? { act: 'move', dir, confirm: true } : { act: 'move', dir });
      P = r.player;
      if (r.msg) result(r);
      if (r.confirm === 'boss') dialog = { type: 'boss', dir, boss: r.boss };
      if (r.waystone) dialog = { type: 'waystone' };
      if (r.npc) {
        const n = WORLD.maps[P.pos.map].npcs.find((x) => x.id === r.npc);
        npc = { map: P.pos.map, id: r.npc, line: n.lines[Math.floor(Math.random() * n.lines.length)] || '' };
      }
      ok = r.ok && !P.battle && P.pos.map === mapBefore && !dialog && !npc;
    } catch (e) {
      toast(e.msg, true);
    }
    busy = false;
    if (!P || P.battle || P.pos.map !== mapBefore || dialog || hadDialog || npc) { walk = null; render(); if (npc) $('#view').scrollTop = 0; } else refresh();
    return ok;
  }

  // Đi dần tới ô đích (hoặc đuổi theo con quái đã chạm vào), tính lại đường sau mỗi bước.
  async function walkTo(x, y) {
    const target = Map_.monsterAt(x, y);
    const me = { x, y, monster: target ? target.id : null, id: Symbol('walk') };
    walk = me;
    for (let i = 0; i < 200 && walk === me && P && !P.battle; i++) {
      if (me.monster != null) {
        const q = Map_.monsterById(me.monster);
        if (!q) break;
        me.x = q.x; me.y = q.y;
      }
      const dir = Map_.nextStep(P, me.x, me.y);
      if (!dir) break;
      const started = Date.now();
      if (!(await step(dir))) break;
      const wait = 130 - (Date.now() - started);
      if (wait > 0) await new Promise((res) => setTimeout(res, wait));
    }
    if (walk === me) walk = null;
  }

  function onKey(e) {
    if (!P || P.battle || tab !== 'map' || e.target.closest('input, textarea')) return;
    if (npc) { if (e.key === 'Escape') { npc = null; render(); } return; }
    const dir = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right', w: 'up', s: 'down', a: 'left', d: 'right' }[e.key];
    if (!dir) return;
    e.preventDefault();
    walk = null;
    step(dir);
  }

  function onMapTap(e) {
    if (e.target.id !== 'map-canvas' || !P || P.battle) return;
    const [x, y] = Map_.tileFromEvent(e);
    walkTo(x, y);
  }

  function enter(r) {
    P = r ? r.player : null;
    if (r) { Map_.setUser(r.user_id); Net.userId = r.user_id; }
    tab = 'map';
    loading = false;
    render();
  }

  function logout() {
    Net.logout();
    P = null;
    npc = null; dialog = null; pwForm = false;
    confirmReset = false;
    render();
  }

  function onClick(e) {
    const t = e.target.closest('button');
    if (!t) return;
    if (t.dataset.cls) { pickCls = t.dataset.cls; document.querySelectorAll('.class-opt').forEach((b) => b.setAttribute('aria-pressed', b.dataset.cls === pickCls)); return; }
    if (t.dataset.tab) { tab = t.dataset.tab; confirmReset = false; render(); $('#view').scrollTop = 0; return; }
    if (t.dataset.auth) { authMode = t.dataset.auth; render(); return; }
    if (t.dataset.board) { board.kind = t.dataset.board; const el = $('#board'); if (el) el.outerHTML = viewBoard(); loadBoard(); return; }
    if (t.dataset.move) { walk = null; step(t.dataset.move); return; }
    const act = t.dataset.act;
    if (act === 'logout') return logout();
    if (act === 'pw-toggle') { pwForm = !pwForm; render(); return; }
    if (act === 'logout-all') {
      Net.logoutAll().then(() => { P = null; render(); toast('Đã đăng xuất mọi thiết bị.'); }).catch((err) => toast(err.msg, true));
      return;
    }
    if (!act || !P) return;
    if (act === 'reset-ask' || act === 'reset-cancel') { confirmReset = act === 'reset-ask'; render(); return; }
    if (act === 'dialog-close') { dialog = null; render(); return; }
    if (act === 'npc-close') { npc = null; render(); return; }
    if (act === 'boss-yes') { const d = dialog; if (d) step(d.dir, true); return; }
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

  async function onPassword() {
    if (busy) return;
    busy = true;
    try {
      const r = await Net.changePassword($('#pw-cur').value, $('#pw-new').value);
      P = r.player;
      pwForm = false;
      render();
      toast('Đã đổi mật khẩu. Các thiết bị khác đã bị đăng xuất.');
    } catch (err) {
      toast(err.msg, true);
    }
    busy = false;
  }

  function onSubmit(e) {
    if (e.target.id === 'auth') { e.preventDefault(); onAuth(); return; }
    if (e.target.id === 'pw-form') { e.preventDefault(); onPassword(); return; }
    if (e.target.id === 'chat-form') { e.preventDefault(); onChatSubmit(); return; }
    if (e.target.id !== 'create') return;
    e.preventDefault();
    const name = $('#hero-name').value.trim();
    if (!name) { toast('Hãy đặt tên cho nhân vật.', true); return; }
    sendCommand({ act: 'create', name, cls: pickCls });
  }

  function start() {
    document.addEventListener('click', onClick);
    document.addEventListener('submit', onSubmit);
    document.addEventListener('keydown', onKey);
    document.addEventListener('pointerdown', onMapTap);
    window.addEventListener('resize', () => Map_.resize());
    Net.onPlayer((p) => { if (!busy) { P = p; refresh(); } });
    Net.onMap((snap) => Map_.setWorld(snap));
    Net.onChat(onChatMessage);
    Net.onWorldBoss(onWorldBoss);
    Net.onNotice((msg) => toast(msg));
    setInterval(() => { const el = $('#wb-left'); if (el && wb.alive) el.textContent = clock(wb.endsAt - wb.skew - Date.now()); }, 1000);
    Net.onChatHistory((msgs) => { chats = msgs; const log = $('#chat-log'); if (log) { log.innerHTML = chats.map(chatLine).join(''); log.scrollTop = log.scrollHeight; } });
    document.addEventListener('input', (e) => { if (e.target.id === 'chat-input') chatDraft = e.target.value; });
    Net.onStatus((st) => {
      const bar = $('#netbar');
      bar.hidden = st === 'online';
      bar.textContent = 'Mất kết nối, đang kết nối lại…';
    });
    // vào lại sau khi mất mạng: lấy trạng thái mới nhất từ server
    Net.onRejoin((r) => { P = r.player; walk = null; render(); });
    Net.onExpired(() => {
      P = null; npc = null; dialog = null;
      $('#netbar').hidden = true;
      render();
      toast('Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.', true);
    });
    render();
    Net.resume().then(enter).catch((e) => { toast(e.msg, true); enter(null); });
  }

  start();
})();
