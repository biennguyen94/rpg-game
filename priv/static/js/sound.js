/* Âm thanh: tự tổng hợp bằng Web Audio (không cần file âm thanh).
 * Sound.play(tên) phát một hiệu ứng ngắn; tắt/bật và âm lượng lưu trong trình duyệt.
 * AudioContext chỉ được tạo sau thao tác đầu tiên của người chơi (trình duyệt yêu cầu). */
(function () {
  const KEY = 'hac-long-sound';
  let ctx = null, master = null;
  let settings = { on: true, volume: 0.6 };
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
  };

  window.Sound = Sound;
})();
