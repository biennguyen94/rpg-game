/* Âm thanh: tự tổng hợp bằng Web Audio (không cần file âm thanh).
 * Sound.play(tên) phát một hiệu ứng ngắn; Sound.music(không khí) chọn nhạc nền (nhạc sinh ra
 * theo luật: hợp âm nền, bè trầm, giai điệu ngũ cung đi dạo ngẫu nhiên), đổi ở đầu ô nhịp sau.
 * Tắt/bật và âm lượng (hiệu ứng, nhạc riêng) lưu trong trình duyệt.
 * AudioContext chỉ được tạo sau thao tác đầu tiên của người chơi (trình duyệt yêu cầu). */
(function () {
  const KEY = 'hac-long-sound';
  let ctx = null, master = null;
  let settings = { on: true, volume: 0.6, music: true, musicVolume: 0.35 };
  try { Object.assign(settings, JSON.parse(localStorage.getItem(KEY) || '{}')); } catch (e) { /* mặc định */ }

  function save() { try { localStorage.setItem(KEY, JSON.stringify(settings)); } catch (e) { /* bỏ qua */ } }

  function audio() {
    if (!ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return null;
      ctx = new AC();
      master = ctx.createGain();
      master.gain.value = settings.volume * 0.5;
      master.connect(ctx.destination);
    }
    if (ctx.state === 'suspended') ctx.resume();
    return ctx;
  }

  // Một nốt: dạng sóng, tần số (có thể trượt tới `to`), bắt đầu sau `at` giây, dài `dur` giây.
  function tone(freq, dur, { type = 'square', at = 0, to = null, vol = 0.3, attack = 0.005 } = {}) {
    const t = ctx.currentTime + at;
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (to) o.frequency.exponentialRampToValueAtTime(to, t + dur);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(master);
    o.start(t); o.stop(t + dur + 0.02);
  }

  // Tiếng ồn (đòn đánh, nước bắn), lọc để đổi màu tiếng.
  function noise(dur, { at = 0, vol = 0.3, freq = 1200, q = 0.8, type = 'bandpass', to = null } = {}) {
    const t = ctx.currentTime + at;
    const len = Math.max(1, Math.floor(ctx.sampleRate * dur));
    const buf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    const src = ctx.createBufferSource(), f = ctx.createBiquadFilter(), g = ctx.createGain();
    src.buffer = buf;
    f.type = type; f.frequency.setValueAtTime(freq, t); f.Q.value = q;
    if (to) f.frequency.exponentialRampToValueAtTime(to, t + dur);
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    src.connect(f).connect(g).connect(master);
    src.start(t); src.stop(t + dur + 0.02);
  }

  const notes = (list, gap, opts) => list.forEach((f, i) => tone(f, opts.dur || gap * 1.6, Object.assign({}, opts, { at: (opts.at || 0) + i * gap })));

  const SFX = {
    hit() { noise(0.09, { freq: 900, vol: 0.5 }); tone(140, 0.1, { type: 'triangle', to: 60, vol: 0.4 }); },
    crit() { noise(0.14, { freq: 2200, vol: 0.55 }); tone(220, 0.16, { type: 'sawtooth', to: 70, vol: 0.35 }); tone(880, 0.12, { type: 'square', at: 0.03, vol: 0.12 }); },
    miss() { noise(0.18, { freq: 500, to: 3000, vol: 0.18, q: 2 }); },
    hurt() { tone(110, 0.18, { type: 'sawtooth', to: 55, vol: 0.3 }); noise(0.08, { freq: 400, vol: 0.3, type: 'lowpass' }); },
    skill() { tone(330, 0.25, { type: 'sawtooth', to: 990, vol: 0.18 }); noise(0.2, { freq: 3000, vol: 0.2, at: 0.05 }); },
    potion() { notes([520, 660, 780], 0.06, { type: 'sine', vol: 0.2, dur: 0.12 }); },
    win() { notes([523, 659, 784, 1047], 0.09, { type: 'square', vol: 0.14, dur: 0.16 }); },
    lose() { notes([392, 330, 262, 196], 0.16, { type: 'triangle', vol: 0.25, dur: 0.3 }); },
    flee() { noise(0.25, { freq: 800, to: 200, vol: 0.2 }); },
    levelup() { notes([523, 659, 784, 1047, 1319], 0.08, { type: 'square', vol: 0.13, dur: 0.14 }); tone(1047, 0.5, { type: 'triangle', at: 0.42, vol: 0.2 }); },
    coin() { tone(988, 0.07, { vol: 0.15 }); tone(1319, 0.18, { vol: 0.15, at: 0.07 }); },
    gather() { tone(660, 0.08, { type: 'triangle', vol: 0.25 }); tone(990, 0.1, { type: 'triangle', vol: 0.2, at: 0.06 }); },
    portal() { tone(220, 0.35, { type: 'sine', to: 880, vol: 0.2 }); tone(330, 0.35, { type: 'sine', to: 1320, vol: 0.1, at: 0.05 }); },
    forge() { noise(0.05, { freq: 3500, vol: 0.4, q: 4 }); tone(1760, 0.3, { type: 'triangle', vol: 0.12 }); tone(2637, 0.25, { type: 'sine', vol: 0.06 }); },
    brew() { [0, 0.08, 0.17, 0.27].forEach((at) => tone(300 + Math.random() * 300, 0.07, { type: 'sine', at, to: 900, vol: 0.15 })); },
    quest() { notes([784, 988, 1175], 0.1, { type: 'triangle', vol: 0.22, dur: 0.25 }); },
    mail() { tone(1175, 0.12, { type: 'sine', vol: 0.25 }); tone(1568, 0.25, { type: 'sine', vol: 0.2, at: 0.12 }); },
    achieve() { notes([784, 988, 1175, 1568], 0.07, { type: 'square', vol: 0.12, dur: 0.12 }); tone(1568, 0.6, { type: 'triangle', at: 0.3, vol: 0.2 }); },
    cast() { noise(0.12, { freq: 600, vol: 0.2, at: 0.15 }); tone(420, 0.1, { type: 'sine', to: 200, vol: 0.2, at: 0.15 }); },
    bite() { tone(600, 0.06, { type: 'sine', to: 300, vol: 0.35 }); tone(600, 0.06, { type: 'sine', to: 300, vol: 0.35, at: 0.1 }); },
    catch() { noise(0.25, { freq: 1500, vol: 0.3 }); SFX.gather(); },
    rare() { noise(0.25, { freq: 1500, vol: 0.3 }); notes([1047, 1319, 1568, 2093], 0.07, { type: 'triangle', vol: 0.16, dur: 0.2, at: 0.1 }); },
    encounter() { tone(98, 0.12, { type: 'triangle', vol: 0.4 }); tone(98, 0.14, { type: 'triangle', vol: 0.4, at: 0.14 }); noise(0.1, { freq: 300, vol: 0.2, type: 'lowpass', at: 0.14 }); },
    notice() { tone(880, 0.12, { type: 'sine', vol: 0.18 }); },
    error() { tone(160, 0.12, { type: 'square', vol: 0.12 }); },
  };

  // ---------- Nhạc nền ----------
  // Mỗi không khí: nốt gốc (MIDI), độ dài một phách con (giây, 8 phách một ô nhịp), vòng hợp
  // âm [bậc so với gốc, quãng ba], thang ngũ cung của giai điệu, độ dày giai điệu, các phách
  // có bè trầm, dạng sóng hợp âm nền, có trống hay không.
  const MAJ = [0, 2, 4, 7, 9], MIN = [0, 3, 5, 7, 10];
  const MOODS = {
    village: { root: 60, step: 0.33, prog: [[0, 4], [9, 3], [5, 4], [7, 4]], scale: MAJ, density: 0.45, bass: [0, 4], pad: 'triangle' },
    home: { root: 65, step: 0.42, prog: [[0, 4], [5, 4], [9, 3], [7, 4]], scale: MAJ, density: 0.3, bass: [0], pad: 'sine' },
    wild: { root: 57, step: 0.28, prog: [[0, 3], [8, 4], [3, 4], [10, 4]], scale: MIN, density: 0.4, bass: [0, 3, 4, 6], pad: 'triangle' },
    night: { root: 55, step: 0.44, prog: [[0, 3], [5, 3], [0, 3], [7, 3]], scale: MIN, density: 0.22, bass: [0], pad: 'sine' },
    tower: { root: 58, step: 0.3, prog: [[0, 3], [1, 4], [0, 3], [10, 4]], scale: [0, 1, 5, 7, 8], density: 0.35, bass: [0, 4], pad: 'sine' },
    battle: { root: 52, step: 0.2, prog: [[0, 3], [8, 4], [5, 3], [7, 4]], scale: MIN, density: 0.5, bass: [0, 2, 4, 6], pad: 'triangle', drum: true },
    boss: { root: 50, step: 0.18, prog: [[0, 3], [1, 4], [8, 4], [7, 4]], scale: [0, 1, 3, 7, 8], density: 0.55, bass: [0, 1, 2, 3, 4, 5, 6, 7], pad: 'sawtooth', drum: true },
  };
  let musicIn = null, musicOut = null, mood = null, want = null, timer = null;
  let nextTime = 0, step = 0, bar = 0, mel = 2;
  const midi = (n) => 440 * Math.pow(2, (n - 69) / 12);

  // đường nhạc: lọc bớt tiếng chói, thêm tiếng vang nhẹ
  function musicBus() {
    if (musicIn) return;
    musicIn = ctx.createGain();
    musicOut = ctx.createGain();
    musicOut.gain.value = settings.music ? settings.musicVolume * 0.6 : 0;
    const lp = ctx.createBiquadFilter();
    lp.type = 'lowpass'; lp.frequency.value = 2400;
    const delay = ctx.createDelay(), fb = ctx.createGain();
    delay.delayTime.value = 0.36; fb.gain.value = 0.28;
    musicIn.connect(lp); lp.connect(musicOut); lp.connect(delay);
    delay.connect(fb).connect(delay); delay.connect(musicOut);
    musicOut.connect(ctx.destination);
  }

  function voice(freq, t, dur, { type = 'triangle', vol = 0.05, attack = 0.02, to = null } = {}) {
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (to) o.frequency.exponentialRampToValueAtTime(to, t + dur);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + attack);
    g.gain.setValueAtTime(vol, t + Math.max(attack, dur * 0.6));
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(musicIn);
    o.start(t); o.stop(t + dur + 0.05);
  }

  function playStep(t) {
    const m = MOODS[mood], s = step % 8;
    const [deg, third] = m.prog[bar % m.prog.length];
    const root = m.root + deg;
    if (s === 0) {
      for (const n of [root - 12, root + third - 12, root + 7 - 12]) voice(midi(n), t, m.step * 8.4, { type: m.pad, vol: m.pad === 'sawtooth' ? 0.012 : 0.03, attack: m.step * 2 });
    }
    if (m.bass.includes(s)) voice(midi(root - 24), t, m.step * 1.6, { type: 'triangle', vol: 0.09, attack: 0.01 });
    if (m.drum && s % 4 === 0) voice(140, t, 0.16, { type: 'sine', vol: 0.18, attack: 0.003, to: 45 });
    if (m.drum && s % 4 === 2) voice(900, t, 0.04, { type: 'square', vol: 0.012, attack: 0.002 });
    // giai điệu: đi dạo trên thang ngũ cung quanh hợp âm
    if (Math.random() < m.density) {
      mel = Math.max(0, Math.min(9, mel + [-2, -1, -1, 0, 1, 1, 2][Math.floor(Math.random() * 7)]));
      const n = m.root + 12 + m.scale[mel % 5] + 12 * Math.floor(mel / 5);
      voice(midi(n), t, m.step * (Math.random() < 0.3 ? 2.2 : 1.1), { type: s === 0 ? 'triangle' : 'sine', vol: 0.05, attack: 0.015 });
    }
  }

  function tick() {
    if (!ctx || ctx.state !== 'running') return;
    if (nextTime < ctx.currentTime) nextTime = ctx.currentTime + 0.05;
    while (nextTime < ctx.currentTime + 0.5) {
      // đổi không khí ở đầu ô nhịp
      if (step % 8 === 0 && want !== mood) { mood = want; bar = 0; step = 0; }
      if (!mood) { stopMusic(); return; }
      playStep(nextTime);
      nextTime += MOODS[mood].step;
      step++;
      if (step % 8 === 0) bar++;
    }
  }

  function stopMusic() {
    if (timer) clearInterval(timer);
    timer = null; mood = null; step = 0;
  }

  function startMusic() {
    if (!want || !settings.music || timer) return;
    try {
      if (!audio()) return;
      musicBus();
      nextTime = ctx.currentTime + 0.1; step = 0; bar = 0;
      timer = setInterval(tick, 150);
      tick();
    } catch (e) { /* không phát được thì thôi */ }
  }

  // trình duyệt chặn âm thanh tới khi người chơi chạm vào trang; ẩn tab thì tạm dừng
  document.addEventListener('pointerdown', () => { if (ctx && ctx.state === 'suspended' && !document.hidden) ctx.resume(); startMusic(); });
  document.addEventListener('visibilitychange', () => {
    if (!ctx) return;
    if (document.hidden) ctx.suspend(); else ctx.resume();
  });

  const Sound = {
    play(name) {
      if (!settings.on || !SFX[name]) return;
      try { if (audio()) SFX[name](); } catch (e) { /* không phát được thì thôi */ }
    },
    get on() { return settings.on; },
    get volume() { return settings.volume; },
    toggle() { settings.on = !settings.on; save(); if (settings.on) Sound.play('coin'); return settings.on; },
    setVolume(v) {
      settings.volume = Math.max(0, Math.min(1, v));
      if (master) master.gain.value = settings.volume * 0.5;
      save();
    },
    // Nhạc nền theo không khí: village, home, wild, night, tower, battle, boss; null để tắt.
    music(name) {
      want = MOODS[name] ? name : null;
      if (want && !timer) startMusic();
    },
    get mood() { return mood; },
    get musicOn() { return settings.music; },
    get musicVolume() { return settings.musicVolume; },
    toggleMusic() {
      settings.music = !settings.music;
      save();
      if (musicOut) musicOut.gain.value = settings.music ? settings.musicVolume * 0.6 : 0;
      if (settings.music) startMusic(); else stopMusic();
      return settings.music;
    },
    setMusicVolume(v) {
      settings.musicVolume = Math.max(0, Math.min(1, v));
      if (musicOut && settings.music) musicOut.gain.value = settings.musicVolume * 0.6;
      save();
    },
  };

  window.Sound = Sound;
})();
