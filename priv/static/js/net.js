/* Kết nối tới server Phoenix: đăng nhập/đăng ký qua HTTP, rồi mở WebSocket vào
 * kênh "game". Mọi thao tác gửi qua kênh này và server trả về trạng thái mới.
 *
 * Mất mạng thì thư viện Phoenix tự kết nối lại và vào lại kênh; khi đó Net báo trạng thái
 * (onStatus) và gửi trạng thái nhân vật mới nhất (onRejoin). Nếu token đã bị thu hồi
 * (đăng xuất mọi thiết bị, đổi mật khẩu ở nơi khác) thì báo onExpired để về màn đăng nhập. */
(function () {
  const TOKEN_KEY = 'hac-long-token';
  const cb = { player: null, map: null, status: null, rejoin: null, expired: null, chat: null, history: null, boss: null, notice: null, mail: null, guild: null, party: null, invite: null, shared: null, trade: null, tradeRequest: null, friends: null, dm: null };
  let socket = null, channel = null, checkTimer = null;

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

  function close() {
    clearTimeout(checkTimer);
    const s = socket;
    socket = channel = null; // trước khi ngắt, để onClose biết là mình chủ động đóng
    if (s) s.disconnect();
  }

  // Mất kết nối một lúc mà chưa vào lại được: hỏi server xem token còn hiệu lực không.
  function scheduleCheck(token) {
    clearTimeout(checkTimer);
    checkTimer = setTimeout(async () => {
      if (!socket || socket.isConnected()) return;
      try {
        await api('GET', '/api/me', null, token);
      } catch (e) {
        if (e.status === 401) { Net.logout(true); if (cb.expired) cb.expired(); return; }
      }
      scheduleCheck(token);
    }, 4000);
  }

  // Mở WebSocket và vào kênh "game". Trả về { username, user_id, player }.
  function join(token) {
    close();
    return new Promise((resolve, reject) => {
      let joined = false;
      const s = new window.Phoenix.Socket('/socket', { params: { token } });
      socket = s;
      s.onOpen(() => { if (socket === s && cb.status) cb.status('online'); });
      s.onClose(() => {
        if (socket !== s) return;
        if (cb.status) cb.status('offline');
        scheduleCheck(token);
      });
      s.connect();
      channel = s.channel('game', {});
      channel.on('player', (m) => cb.player && cb.player(m.player));
      channel.on('map', (m) => cb.map && cb.map(m));
      channel.on('chat', (m) => cb.chat && cb.chat(m));
      channel.on('chat_history', (m) => cb.history && cb.history(m.messages));
      channel.on('world_boss', (m) => cb.boss && cb.boss(m));
      channel.on('notice', (m) => cb.notice && cb.notice(m.msg));
      channel.on('mail', (m) => cb.mail && cb.mail(m.unread));
      channel.on('guild', (m) => cb.guild && cb.guild(m.guild));
      channel.on('party', (m) => cb.party && cb.party(m.party));
      channel.on('party_invite', (m) => cb.invite && cb.invite(m));
      channel.on('trade', (m) => cb.trade && cb.trade(m.trade));
      channel.on('friends', (m) => cb.friends && cb.friends(m.msg));
      channel.on('dm', (m) => cb.dm && cb.dm(m));
      channel.on('trade_request', (m) => cb.tradeRequest && cb.tradeRequest(m));
      channel.on('shared', (m) => cb.shared && cb.shared(m));
      channel.join()
        .receive('ok', (r) => {
          if (!joined) { joined = true; resolve(r); } else if (cb.rejoin) cb.rejoin(r);
        })
        .receive('error', () => { if (!joined) { close(); reject({ msg: 'Không vào được game.' }); } })
        .receive('timeout', () => { if (!joined) { close(); reject({ msg: 'Máy chủ không phản hồi.' }); } });
    });
  }

  function push(event, payload) {
    return new Promise((resolve, reject) => {
      if (!channel) return reject({ msg: 'Chưa kết nối.' });
      channel.push(event, payload, 10000)
        .receive('ok', resolve)
        .receive('error', (e) => reject({ msg: (e && e.msg) || 'Lỗi máy chủ.' }))
        .receive('timeout', () => reject({ msg: 'Mất kết nối, thử lại.' }));
    });
  }

  const Net = {
    username: null,

    // Tự đăng nhập bằng token đã lưu. Trả về { username, user_id, player } hoặc null.
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

    // Đăng xuất thiết bị này. `local`: token đã hết hiệu lực, không cần báo server.
    logout(local) {
      const token = store.get();
      if (token && !local) api('POST', '/api/logout', null, token).catch(() => {});
      store.set(null);
      Net.username = null;
      close();
    },

    async logoutAll() {
      await api('POST', '/api/logout_all', null, store.get());
      Net.logout(true);
    },

    // Đổi mật khẩu: server thu hồi mọi token cũ, trả token mới cho thiết bị này.
    async changePassword(current, password) {
      const r = await api('POST', '/api/password', { current, password }, store.get());
      store.set(r.token);
      return join(r.token);
    },

    // Gửi một lệnh, nhận { ok, msg, result, player }.
    send(cmd) { return push('cmd', cmd); },

    // Gửi tin nhắn chat thế giới.
    // `to`: 'guild' để chat trong bang, bỏ trống là chat thế giới.
    chat(text, to) { return push('chat', to ? { text, to } : { text }); },

    // Tổ đội: party('invite', { uid }), party('accept'), party('leave')...
    party(op, payload) { return push('party', Object.assign({ op }, payload || {})); },
    // Giao dịch: trade('request', { uid }), trade('accept'), trade('offer', { offer }), trade('ready')...
    trade(op, payload) { return push('trade', Object.assign({ op }, payload || {})); },
    // Bạn bè: friends('list'), friends('request', { uid } | { name }), accept/decline/remove { uid }.
    friends(op, payload) { return push('friends', Object.assign({ op }, payload || {})); },
    // Tin riêng: dm('history', { uid }), dm('send', { uid, text }).
    dm(op, payload) { return push('dm', Object.assign({ op }, payload || {})); },
    // Đấu trường: điểm của mình, đối thủ gợi ý, bảng xếp hạng. Xem thông tin người chơi khác.
    arena() { return push('arena', {}); },
    // Chợ: { listings, fee, max }. Rao bán/mua/rút về là lệnh market_sell/market_buy/market_cancel.
    market(q) { return push('market', { q: q || '' }); },
    inspect(uid) { return push('inspect', { uid }); },
    // Thăm nhà: { id, name, look, decor, comfort, likes, liked }; khen nhà: { likes }.
    visit(uid) { return push('visit', { uid }); },
    homeLike(uid) { return push('home_like', { uid }); },

    // Bang hội: guild('list', { q }), guild('info'), guild('join', { id })... (xem GameChannel).
    guild(op, payload) { return push('guild', Object.assign({ op }, payload || {})); },

    // Bảng xếp hạng: { level, kills, dragon, me }.
    leaderboard() { return push('leaderboard', {}); },

    // Chặn / bỏ chặn chat của một người (trả { blocked }); báo cáo một tin nhắn.
    block(uid) { return push('block', { uid }); },
    unblock(uid) { return push('unblock', { uid }); },
    report(id) { return push('report', { id }); },

    // Hộp thư: { mails, unread }. Mở thư/nhận quà là lệnh { act: 'mail_claim', id }.
    mail() { return push('mail', {}); },

    // Lệnh quản trị (chỉ tài khoản quản trị).
    admin(op, payload) { return push('admin', Object.assign({ op }, payload || {})); },
    // Nhân vật thay đổi từ tab/thiết bị khác.
    onPlayer(f) { cb.player = f; },
    // Quái và người chơi trên bản đồ đang đứng thay đổi.
    onMap(f) { cb.map = f; },
    // 'online' | 'offline'
    onStatus(f) { cb.status = f; },
    // Vào lại kênh sau khi mất kết nối: nhận { username, user_id, player } mới nhất.
    onRejoin(f) { cb.rejoin = f; },
    // Token hết hiệu lực (bị đăng xuất từ nơi khác).
    onExpired(f) { cb.expired = f; },
    // Tin chat mới / các tin gần nhất lúc vào game.
    onChat(f) { cb.chat = f; },
    onChatHistory(f) { cb.history = f; },
    // Trạng thái trùm thế giới; thông báo riêng (vd. nhận thưởng).
    onWorldBoss(f) { cb.boss = f; },
    onNotice(f) { cb.notice = f; },
    // Số thư chưa mở thay đổi (có thư mới, vừa mở thư).
    onMail(f) { cb.mail = f; },
    // Bang của mình vừa đổi (vào, rời, bị đuổi, lên cấp): { id, name, tag, level, role } hoặc null.
    onGuild(f) { cb.guild = f; },
    // Tổ đội đổi / có lời mời vào tổ đội / máu chung của trận đánh cùng đổi.
    onParty(f) { cb.party = f; },
    onPartyInvite(f) { cb.invite = f; },
    onShared(f) { cb.shared = f; },
    // Bảng giao dịch đổi (hoặc null khi xong/hủy) / có người mời giao dịch.
    onTrade(f) { cb.trade = f; },
    onTradeRequest(f) { cb.tradeRequest = f; },
    // Danh sách bạn đổi (msg: thông báo hoặc null) / có tin riêng mới (của mình hoặc gửi cho mình).
    onFriends(f) { cb.friends = f; },
    onDm(f) { cb.dm = f; },
  };

  window.Net = Net;
})();
