/* Vẽ bản đồ ô vuông lên canvas và tìm đường khi chạm vào một ô.
 * Chỉ hiển thị: vị trí thật do server quyết định (mỗi bước gửi lên, server kiểm tra rồi trả về).
 * Dữ liệu bản đồ tĩnh ở GAME_DATA.WORLD; quái và người chơi khác đến từ sự kiện "map" của server. */
(function () {
  const { WORLD, ZONES } = window.GAME_DATA;
  const TILE = 32;
  const WALK = new Set(WORLD.walkable);
  const PORTAL = new Set(['D', 'A', 'O']);
  // loại ô → hình (assets/tiles/*.png); nền "." dùng hình `floor` của từng bản đồ
  const GROUND = { grass: 1, dirt: 1, flowers: 1 };
  const DIRS = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] };

  // cấp của từng loại quái, để tô màu độ khó
  const LEVEL = {};
  ZONES.forEach((z) => { z.monsters.concat([z.boss]).forEach((m) => { LEVEL[m.id] = m.level; }); });

  const images = {};
  let canvas = null, ctx = null, mounted = null, getPlayer = () => null;
  let world = { map: null, monsters: [], players: [] };
  let userId = null;
  let boss = { alive: false }; // trùm thế giới (HacLong.WorldBoss)

  // ---------- Di chuyển mượt ----------
  // Server gửi vị trí theo ô; khi vẽ thì trượt từ ô cũ sang ô mới trong `dur` ms.
  // Nhảy xa hơn một ô (dịch chuyển, qua cổng) thì hiện ngay ở chỗ mới.
  const anim = new Map();
  let frame = null, lastCam = [0, 0];
  const DUR = { me: 130, player: 160, monster: 380 };

  // Bong bóng lời nói trên đầu nhân vật (chat), hiện vài giây.
  const bubbles = new Map();
  const BUBBLE_MS = 6000;
  let bubbleTimer = null;

  function bubble(text, cx, py) {
    ctx.font = '500 11px "Be Vietnam Pro", system-ui, sans-serif';
    let t = text;
    while (ctx.measureText(t).width > 170 && t.length > 4) t = t.slice(0, -2);
    if (t !== text) t = t.slice(0, -1) + '…';
    const w = ctx.measureText(t).width + 12, x = Math.round(cx - w / 2), y = py - 34;
    ctx.fillStyle = 'rgba(246, 240, 226, 0.95)';
    ctx.beginPath(); ctx.roundRect(x, y, w, 18, 6); ctx.fill();
    ctx.beginPath(); ctx.moveTo(cx - 4, y + 18); ctx.lineTo(cx + 4, y + 18); ctx.lineTo(cx, y + 23); ctx.fill();
    ctx.fillStyle = '#1b1422';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(t, cx, y + 9.5);
  }

  function bubbleOf(uid, now) {
    const b = bubbles.get(uid);
    if (!b) return null;
    if (b.until < now) { bubbles.delete(uid); return null; }
    return b.text;
  }

  function smooth(key, x, y, dur, now) {
    let a = anim.get(key);
    if (!a || Math.abs(a.tx - x) + Math.abs(a.ty - y) > 1) {
      a = { fx: x, fy: y, tx: x, ty: y, t0: now, dur };
      anim.set(key, a);
    } else if (a.tx !== x || a.ty !== y) {
      const [cx, cy] = at(a, now);
      Object.assign(a, { fx: cx, fy: cy, tx: x, ty: y, t0: now, dur });
    }
    a.seen = now;
    return at(a, now);
  }

  function at(a, now) {
    const k = Math.min(1, (now - a.t0) / a.dur);
    if (k < 1 && !frame) frame = requestAnimationFrame(() => { frame = null; draw(); });
    return [a.fx + (a.tx - a.fx) * k, a.fy + (a.ty - a.fy) * k];
  }

  function image(path) {
    if (!images[path]) {
      const im = new Image();
      im.onload = () => draw();
      im.src = 'assets/' + path + '.png';
      images[path] = im;
    }
    return images[path];
  }

  const mapOf = (id) => WORLD.maps[id];
  const tileAt = (m, x, y) => (y >= 0 && y < m.tiles.length && x >= 0 && x < m.tiles[0].length ? m.tiles[y][x] : null);
  const portalAt = (m, x, y) => m.portals.find((p) => p.at[0] === x && p.at[1] === y);
  // Tầng Tháp Vô Tận không có trong WORLD: dựng từ trạng thái nhân vật (P.tower).
  function cur(P) {
    if (P.pos.map !== 'tower' || !P.tower) return mapOf(P.pos.map);
    const t = P.tower, zi = Math.min(ZONES.length - 1, Math.floor((t.floor - 1) / 10));
    return { name: `Tháp Vô Tận · Tầng ${t.floor}`, zone: null, floor: 'floors/' + ZONES[zi].id, tiles: t.tiles, portals: [], npcs: [], tower: t };
  }

  // Quái trên bản đồ đang đứng: quái dùng chung (sự kiện "map") hoặc quái của tầng tháp.
  function mobs(P) {
    if (P.pos.map === 'tower' && P.tower) return P.tower.monsters.map((q) => Object.assign({}, q, { id: 't' + q.id, boss: q.elite }));
    return world.map === P.pos.map ? world.monsters : [];
  }

  const monsterAt = (x, y) => mobs(getPlayer()).find((q) => q.x === x && q.y === y);
  const monsterById = (id) => mobs(getPlayer()).find((q) => q.id === id);
  const nodeAt = (x, y) => (world.nodes || []).find((n) => n.x === x && n.y === y);
  const npcAt = (m, x, y) => (m.npcs || []).find((n) => n.at[0] === x && n.at[1] === y);

  // Cổng vào vùng chưa mở (P.view.unlocked do server tính).
  function locked(P, portal) {
    const target = mapOf(portal.to);
    return target.zone != null && !P.view.unlocked[target.zone];
  }

  function top(P) {
    const m = cur(P);
    const z = m.zone != null ? ZONES[m.zone] : null;
    return `<div class="map-top">
        <b>${m.name}</b>
        <span class="small muted">${m.tower ? (m.tower.monsters.length ? `Còn ${m.tower.monsters.length} quái · kỷ lục tầng ${P.tower_best || 0}` : 'Cầu thang đã mở!') : z ? (P.pos.map.endsWith('_boss') ? `Phòng trùm · cấp ${z.boss.level}` : `Quái cấp ${z.levels}`) : P.pos.map === 'home' ? 'Giếng nước hồi đầy máu' : P.pos.map === 'altar' ? 'Nơi trùm thế giới xuất hiện' : 'Bước vào người dân để nói chuyện'}</span>
      </div>`;
  }

  function html(P, overlay) {
    const m = cur(P);
    return `
      ${top(P)}
      <div class="map-wrap"><canvas id="map-canvas" aria-label="Bản đồ ${m.name}"></canvas>${overlay || ''}</div>
      <div class="dpad" aria-label="Di chuyển">
        <button class="btn" data-move="up" aria-label="Lên">▲</button>
        <button class="btn" data-move="left" aria-label="Trái">◀</button>
        <button class="btn" data-move="down" aria-label="Xuống">▼</button>
        <button class="btn" data-move="right" aria-label="Phải">▶</button>
      </div>
      <p class="small muted map-hint">Chạm vào ô để đi tới, bước vào quái để đánh. Máy tính: phím mũi tên hoặc WASD.</p>`;
  }

  function mount(player) {
    getPlayer = player;
    canvas = document.getElementById('map-canvas');
    if (!canvas) { mounted = null; return; }
    ctx = canvas.getContext('2d');
    if (mounted !== getPlayer().pos.map) anim.clear();
    mounted = getPlayer().pos.map;
    resize();
  }

  function resize() {
    if (!canvas) return;
    const w = canvas.parentElement.clientWidth;
    const h = Math.min(Math.round(window.innerHeight * 0.52), 13 * TILE);
    const dpr = window.devicePixelRatio || 1;
    canvas.style.height = h + 'px';
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.imageSmoothingEnabled = false;
    draw();
  }

  // Góc trên trái của khung nhìn (pixel), đi theo nhân vật (x, y tính theo ô, có thể lẻ),
  // không lố ra ngoài bản đồ.
  function camera(m, x, y) {
    const vw = canvas.clientWidth, vh = canvas.clientHeight;
    const mw = m.tiles[0].length * TILE, mh = m.tiles.length * TILE;
    const axis = (view, size, t) => (size <= view ? (size - view) / 2 : Math.max(0, Math.min(size - view, t * TILE + TILE / 2 - view / 2)));
    return [Math.round(axis(vw, mw, x)), Math.round(axis(vh, mh, y))];
  }

  function label(text, cx, y, color) {
    ctx.font = '600 10px "Be Vietnam Pro", system-ui, sans-serif';
    const w = ctx.measureText(text).width + 6;
    ctx.fillStyle = 'rgba(12, 9, 16, 0.78)';
    ctx.fillRect(Math.round(cx - w / 2), y, w, 13);
    ctx.fillStyle = color || '#f1e6cf';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    ctx.fillText(text, cx, y + 1);
  }

  function levelColor(P, lv) {
    if (lv <= P.level - 3) return '#9a93a3';
    if (lv <= P.level) return '#7fd08a';
    if (lv <= P.level + 2) return '#e8c15a';
    return '#ef6a5a';
  }

  function draw() {
    const P = getPlayer();
    if (!canvas || !ctx || !P || !P.pos || mounted !== P.pos.map) return;
    const m = cur(P);
    const now = performance.now();
    const [mx, my] = smooth('me', P.pos.x, P.pos.y, DUR.me, now);
    const [cx, cy] = camera(m, mx, my);
    lastCam = [cx, cy];
    ctx.fillStyle = '#0c0910';
    ctx.fillRect(0, 0, canvas.clientWidth, canvas.clientHeight);
    const x0 = Math.max(0, Math.floor(cx / TILE)), y0 = Math.max(0, Math.floor(cy / TILE));
    const x1 = Math.min(m.tiles[0].length - 1, Math.ceil((cx + canvas.clientWidth) / TILE));
    const y1 = Math.min(m.tiles.length - 1, Math.ceil((cy + canvas.clientHeight) / TILE));
    const floor = image(m.floor);
    const labels = [], talk = [];

    for (let y = y0; y <= y1; y++) {
      for (let x = x0; x <= x1; x++) {
        const px = Math.round(x * TILE - cx), py = Math.round(y * TILE - cy);
        const kind = WORLD.legend[m.tiles[y][x]];
        if (floor.complete) ctx.drawImage(floor, px, py, TILE, TILE);
        if (kind !== 'floor') {
          const im = image('tiles/' + kind);
          if (im.complete) ctx.drawImage(im, px, py, TILE, TILE);
        }
        if (GROUND[kind]) continue;
        if (kind === 'waystone') labels.push(['Đá dịch chuyển', px + TILE / 2, py - 13, '#b9d7ff']);
        if (kind === 'stairs_up') labels.push([m.tower && m.tower.monsters.length ? '🔒 Lên tầng' : 'Lên tầng', px + TILE / 2, py + TILE - 13, '#f0cf7a']);
        if (kind === 'stairs_down') labels.push(['Về Làng', px + TILE / 2, py + TILE - 13, '#b9d7ff']);
        const portal = PORTAL.has(m.tiles[y][x]) && portalAt(m, x, y);
        if (portal) {
          const shut = locked(P, portal);
          if (shut) { ctx.fillStyle = 'rgba(0,0,0,0.55)'; ctx.fillRect(px, py, TILE, TILE); }
          // nhãn nằm trong ô cổng để không đè lên người đứng cạnh
          labels.push([(shut ? '🔒 ' : '') + mapOf(portal.to).name, px + TILE / 2, py + TILE - 13, shut ? '#9a93a3' : '#f0cf7a']);
        }
      }
    }

    // sự kiện "map" có thể đến trước/sau lúc đổi bản đồ một chút
    const here = world.map === P.pos.map;
    for (const q of mobs(P)) {
      const [qx, qy] = smooth('m' + q.id, q.x, q.y, DUR.monster, now);
      const px = Math.round(qx * TILE - cx), py = Math.round(qy * TILE - cy);
      if (px < -TILE || py < -TILE || px > canvas.clientWidth || py > canvas.clientHeight) continue;
      ctx.globalAlpha = q.busy ? 0.45 : 1;
      if (q.boss) {
        ctx.strokeStyle = '#f0cf7a'; ctx.lineWidth = 2;
        ctx.strokeRect(px + 1, py + 1, TILE - 2, TILE - 2);
      }
      const im = image('monsters/' + q.kind);
      if (im.complete) ctx.drawImage(im, px, py, TILE, TILE);
      ctx.globalAlpha = 1;
      const lv = q.level || LEVEL[q.kind] || 1;
      ctx.font = '700 9px system-ui, sans-serif';
      ctx.fillStyle = 'rgba(12,9,16,0.85)';
      ctx.fillRect(px + TILE - 14, py + TILE - 10, 14, 10);
      ctx.fillStyle = levelColor(P, lv);
      ctx.textAlign = 'center'; ctx.textBaseline = 'top';
      ctx.fillText(String(lv), px + TILE - 7, py + TILE - 9);
      if (q.busy) label('⚔', px + TILE / 2, py - 12, '#ef6a5a');
    }

    for (const n of here ? world.nodes || [] : []) {
      const px = Math.round(n.x * TILE - cx), py = Math.round(n.y * TILE - cy);
      const im = image('nodes/' + n.item);
      if (im.complete) ctx.drawImage(im, px, py, TILE, TILE);
    }

    for (const n of m.npcs || []) {
      const px = Math.round(n.at[0] * TILE - cx), py = Math.round(n.at[1] * TILE - cy);
      const im = image('npcs/' + n.sprite);
      if (im.complete) ctx.drawImage(im, px, py, TILE, TILE);
      labels.push([n.name, px + TILE / 2, py - 14, n.role === 'quests' ? '#f0cf7a' : '#c8f0b0']);
      if ((n.role === 'quests' && P.view.questReady) || (n.role === 'daily' && P.view.dailyReady)) label('!', px + TILE - 4, py - 2, '#f0cf7a');
    }

    // trùm thế giới: vẽ to gấp đôi, có thanh máu chung
    if (m.worldBoss && boss.alive) {
      const [bx, by] = m.worldBoss;
      const px = Math.round(bx * TILE - cx), py = Math.round(by * TILE - cy);
      const im = image('monsters/ancient_dragon');
      if (im.complete) ctx.drawImage(im, px - TILE / 2, py - TILE, TILE * 2, TILE * 2);
      const w = TILE * 2, k = boss.hp / boss.maxHp;
      ctx.fillStyle = 'rgba(12,9,16,0.85)'; ctx.fillRect(px - TILE / 2, py - TILE - 8, w, 6);
      ctx.fillStyle = '#d9483b'; ctx.fillRect(px - TILE / 2 + 1, py - TILE - 7, Math.max(0, (w - 2) * k), 4);
      labels.push([boss.name, px + TILE / 2, py - TILE - 22, '#ef6a5a']);
    }

    const hero = image('monsters/hero');
    for (const o of here ? world.players : []) {
      if (o.id === userId) continue;
      const [ox, oy] = smooth('p' + o.id, o.x, o.y, DUR.player, now);
      const px = Math.round(ox * TILE - cx), py = Math.round(oy * TILE - cy);
      ctx.globalAlpha = 0.8;
      if (hero.complete) ctx.drawImage(hero, px, py, TILE, TILE);
      ctx.globalAlpha = 1;
      labels.push([`${o.name} · ${o.level}`, px + TILE / 2, py - 14, '#b9d7ff']);
      const said = bubbleOf(o.id, now);
      if (said) talk.push([said, px + TILE / 2, py]);
    }

    const px = Math.round(mx * TILE - cx), py = Math.round(my * TILE - cy);
    ctx.fillStyle = 'rgba(240, 207, 122, 0.35)';
    ctx.beginPath(); ctx.ellipse(px + TILE / 2, py + TILE - 4, 12, 5, 0, 0, Math.PI * 2); ctx.fill();
    if (hero.complete) ctx.drawImage(hero, px, py, TILE, TILE);
    const mine = bubbleOf(userId, now);
    if (mine) talk.push([mine, px + TILE / 2, py]);
    for (const l of labels) label(...l);
    for (const t of talk) bubble(...t);
    // vẽ lại khi bong bóng hết hạn
    if (bubbles.size && !bubbleTimer) bubbleTimer = setTimeout(() => { bubbleTimer = null; draw(); }, 1000);
    // bỏ những con quái/người đã biến mất khỏi bản đồ
    for (const [k, a] of anim) if (a.seen !== now) anim.delete(k);
  }

  // Ô dưới ngón tay/chuột.
  function tileFromEvent(e) {
    const [cx, cy] = lastCam;
    const r = canvas.getBoundingClientRect();
    return [Math.floor((e.clientX - r.left + cx) / TILE), Math.floor((e.clientY - r.top + cy) / TILE)];
  }

  // Hướng của bước đầu tiên trên đường ngắn nhất tới (tx, ty), hoặc null.
  // Không đi xuyên quái hay cổng; riêng ô đích thì cho phép (đánh quái, qua cổng, uống nước giếng).
  function nextStep(P, tx, ty) {
    const m = cur(P);
    const sx = P.pos.x, sy = P.pos.y;
    if (sx === tx && sy === ty) return null;
    const key = (x, y) => y * 1000 + x;
    const prev = new Map([[key(sx, sy), null]]);
    const queue = [[sx, sy]];
    while (queue.length) {
      const [x, y] = queue.shift();
      for (const [dir, [dx, dy]] of Object.entries(DIRS)) {
        const nx = x + dx, ny = y + dy, k = key(nx, ny);
        if (prev.has(k)) continue;
        const goal = nx === tx && ny === ty;
        const c = tileAt(m, nx, ny);
        if (c == null) continue;
        const bossHere = boss.alive && m.worldBoss && m.worldBoss[0] === nx && m.worldBoss[1] === ny;
        // không đi ngang qua cầu thang (lên/xuống tầng ngoài ý muốn); ô đích thì được
        if (!goal && (!WALK.has(c) || PORTAL.has(c) || c === '<' || c === '>' || monsterAt(nx, ny) || nodeAt(nx, ny) || npcAt(m, nx, ny) || bossHere)) continue;
        prev.set(k, [x, y, dir]);
        if (goal) {
          // lần ngược về ô xuất phát để lấy bước đầu
          let cur = [nx, ny], step = dir;
          for (let p = prev.get(key(...cur)); p; p = prev.get(key(p[0], p[1]))) { step = p[2]; cur = p; }
          return step;
        }
        queue.push([nx, ny]);
      }
    }
    return null;
  }

  window.MapView = {
    html, top, mount, resize, draw, tileFromEvent, nextStep, monsterAt, monsterById,
    mountedMap: () => mounted,
    setUser(id) { userId = id; },
    setBoss(st) { boss = st; draw(); },
    say(uid, text) { bubbles.set(uid, { text, until: performance.now() + BUBBLE_MS }); draw(); },
    setWorld(snap) {
      world = snap;
      draw();
    },
    world: () => world,
  };
})();
