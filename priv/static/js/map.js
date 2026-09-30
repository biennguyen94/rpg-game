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
  const monsterAt = (x, y) => world.monsters.find((q) => q.x === x && q.y === y);
  const monsterById = (id) => world.monsters.find((q) => q.id === id);

  // Cổng vào vùng chưa mở (P.view.unlocked do server tính).
  function locked(P, portal) {
    const target = mapOf(portal.to);
    return target.zone != null && !P.view.unlocked[target.zone];
  }

  function html(P) {
    const m = mapOf(P.pos.map);
    const z = m.zone != null ? ZONES[m.zone] : null;
    return `
      <div class="map-top">
        <b>${m.name}</b>
        <span class="small muted">${z ? `Quái cấp ${z.levels}` : P.pos.map === 'home' ? 'Giếng nước hồi đầy máu' : 'Nghỉ trọ ở tab Hành trình'}</span>
      </div>
      <div class="map-wrap"><canvas id="map-canvas" aria-label="Bản đồ ${m.name}"></canvas></div>
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

  // Góc trên trái của khung nhìn (pixel), đi theo nhân vật, không lố ra ngoài bản đồ.
  function camera(m, P) {
    const vw = canvas.clientWidth, vh = canvas.clientHeight;
    const mw = m.tiles[0].length * TILE, mh = m.tiles.length * TILE;
    const axis = (view, size, at) => (size <= view ? (size - view) / 2 : Math.max(0, Math.min(size - view, at * TILE + TILE / 2 - view / 2)));
    return [axis(vw, mw, P.pos.x), axis(vh, mh, P.pos.y)];
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
    const m = mapOf(P.pos.map);
    const [cx, cy] = camera(m, P);
    ctx.fillStyle = '#0c0910';
    ctx.fillRect(0, 0, canvas.clientWidth, canvas.clientHeight);
    const x0 = Math.max(0, Math.floor(cx / TILE)), y0 = Math.max(0, Math.floor(cy / TILE));
    const x1 = Math.min(m.tiles[0].length - 1, Math.ceil((cx + canvas.clientWidth) / TILE));
    const y1 = Math.min(m.tiles.length - 1, Math.ceil((cy + canvas.clientHeight) / TILE));
    const floor = image(m.floor);
    const labels = [];

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
    for (const q of here ? world.monsters : []) {
      const px = Math.round(q.x * TILE - cx), py = Math.round(q.y * TILE - cy);
      if (px < -TILE || py < -TILE || px > canvas.clientWidth || py > canvas.clientHeight) continue;
      ctx.globalAlpha = q.busy ? 0.45 : 1;
      if (q.boss) {
        ctx.strokeStyle = '#f0cf7a'; ctx.lineWidth = 2;
        ctx.strokeRect(px + 1, py + 1, TILE - 2, TILE - 2);
      }
      const im = image('monsters/' + q.kind);
      if (im.complete) ctx.drawImage(im, px, py, TILE, TILE);
      ctx.globalAlpha = 1;
      const lv = LEVEL[q.kind] || 1;
      ctx.font = '700 9px system-ui, sans-serif';
      ctx.fillStyle = 'rgba(12,9,16,0.85)';
      ctx.fillRect(px + TILE - 14, py + TILE - 10, 14, 10);
      ctx.fillStyle = levelColor(P, lv);
      ctx.textAlign = 'center'; ctx.textBaseline = 'top';
      ctx.fillText(String(lv), px + TILE - 7, py + TILE - 9);
      if (q.busy) label('⚔', px + TILE / 2, py - 12, '#ef6a5a');
    }

    const hero = image('monsters/hero');
    for (const o of here ? world.players : []) {
      if (o.id === userId) continue;
      const px = Math.round(o.x * TILE - cx), py = Math.round(o.y * TILE - cy);
      ctx.globalAlpha = 0.8;
      if (hero.complete) ctx.drawImage(hero, px, py, TILE, TILE);
      ctx.globalAlpha = 1;
      labels.push([`${o.name} · ${o.level}`, px + TILE / 2, py - 14, '#b9d7ff']);
    }

    const px = Math.round(P.pos.x * TILE - cx), py = Math.round(P.pos.y * TILE - cy);
    ctx.fillStyle = 'rgba(240, 207, 122, 0.35)';
    ctx.beginPath(); ctx.ellipse(px + TILE / 2, py + TILE - 4, 12, 5, 0, 0, Math.PI * 2); ctx.fill();
    if (hero.complete) ctx.drawImage(hero, px, py, TILE, TILE);
    for (const l of labels) label(...l);
  }

  // Ô dưới ngón tay/chuột.
  function tileFromEvent(e) {
    const P = getPlayer();
    const m = mapOf(P.pos.map);
    const [cx, cy] = camera(m, P);
    const r = canvas.getBoundingClientRect();
    return [Math.floor((e.clientX - r.left + cx) / TILE), Math.floor((e.clientY - r.top + cy) / TILE)];
  }

  // Hướng của bước đầu tiên trên đường ngắn nhất tới (tx, ty), hoặc null.
  // Không đi xuyên quái hay cổng; riêng ô đích thì cho phép (đánh quái, qua cổng, uống nước giếng).
  function nextStep(P, tx, ty) {
    const m = mapOf(P.pos.map);
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
        if (!goal && (!WALK.has(c) || PORTAL.has(c) || monsterAt(nx, ny))) continue;
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
    html, mount, resize, draw, tileFromEvent, nextStep, monsterAt, monsterById,
    mountedMap: () => mounted,
    setUser(id) { userId = id; },
    setWorld(snap) {
      world = snap;
      draw();
    },
    world: () => world,
  };
})();
