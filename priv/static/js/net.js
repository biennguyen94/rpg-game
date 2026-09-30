/* Kết nối tới server Phoenix: đăng nhập/đăng ký qua HTTP, rồi mở WebSocket vào
 * kênh "game". Mọi thao tác gửi qua kênh này và server trả về trạng thái mới. */
(function () {
  const TOKEN_KEY = 'hac-long-token';
  let socket = null, channel = null, onPlayer = null, onMap = null;

  const store = {
    get() { try { return localStorage.getItem(TOKEN_KEY); } catch (e) { return null; } },
    set(t) { try { if (t) localStorage.setItem(TOKEN_KEY, t); else localStorage.removeItem(TOKEN_KEY); } catch (e) { /* bỏ qua */ } },
  };

  async function api(method, path, body, token) {
    const headers = { 'content-type': 'application/json', accept: 'application/json' };
    if (token) headers.authorization = 'Bearer ' + token;
    let res;
    try {
      res = await fetch(path, { method, headers, body: body ? JSON.stringify(body) : undefined });
    } catch (e) {
      throw { msg: 'Không kết nối được máy chủ.' };
    }
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw { status: res.status, msg: data.error || 'Lỗi máy chủ.' };
    return data;
  }

  // Mở WebSocket và vào kênh "game". Trả về { username, player }.
  function join(token) {
    return new Promise((resolve, reject) => {
      socket = new window.Phoenix.Socket('/socket', { params: { token } });
      socket.connect();
      channel = socket.channel('game', {});
      channel.on('player', (m) => onPlayer && onPlayer(m.player));
      channel.on('map', (m) => onMap && onMap(m));
      channel.join()
        .receive('ok', resolve)
        .receive('error', () => reject({ msg: 'Không vào được game.' }))
        .receive('timeout', () => reject({ msg: 'Máy chủ không phản hồi.' }));
    });
  }

  const Net = {
    username: null,

    // Tự đăng nhập bằng token đã lưu. Trả về { username, player } hoặc null.
    async resume() {
      const token = store.get();
      if (!token) return null;
      try {
        await api('GET', '/api/me', null, token);
      } catch (e) {
        if (e.status === 401) { store.set(null); return null; }
        throw e;
      }
      const r = await join(token);
      Net.username = r.username;
      return r;
    },

    async login(username, password, register) {
      const r = await api('POST', register ? '/api/register' : '/api/login', { username, password });
      store.set(r.token);
      const j = await join(r.token);
      Net.username = j.username;
      return j;
    },

    logout() {
      store.set(null);
      Net.username = null;
      if (socket) socket.disconnect();
      socket = channel = null;
    },

    // Gửi một lệnh, nhận { ok, msg, result, player }.
    send(cmd) {
      return new Promise((resolve, reject) => {
        if (!channel) return reject({ msg: 'Chưa kết nối.' });
        channel.push('cmd', cmd, 10000)
          .receive('ok', resolve)
          .receive('error', (e) => reject({ msg: (e && e.msg) || 'Lỗi máy chủ.' }))
          .receive('timeout', () => reject({ msg: 'Mất kết nối, thử lại.' }));
      });
    },

    // Nhân vật thay đổi từ tab/thiết bị khác.
    onPlayer(cb) { onPlayer = cb; },

    // Quái và người chơi trên bản đồ đang đứng thay đổi.
    onMap(cb) { onMap = cb; },
  };

  window.Net = Net;
})();
