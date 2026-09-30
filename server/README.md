# Server Hắc Long (Elixir / Phoenix)

Server cho bản online: tài khoản, lưu nhân vật trong PostgreSQL, logic chiến đấu chạy
trên server qua Phoenix Channels. Giao diện vẫn là client JS ở thư mục gốc repo.

## Chạy

Cần Elixir ≥ 1.14 (OTP ≥ 25) và PostgreSQL (mặc định `postgres`/`postgres` trên
`localhost`, sửa trong `config/dev.exs`).

```bash
cd server
mix setup          # tải thư viện, tạo database, chạy migration
mix phx.server     # mở http://localhost:4000
mix test           # chạy test (cần PostgreSQL; test so khớp engine cần node)
```

## Cách hoạt động

```
Trình duyệt (index.html + js/ui.js + js/net.js)
   │  POST /api/register, /api/login  → token
   │  WebSocket /socket?token=…  → kênh "game"
   ▼
HacLongWeb.GameChannel ── lệnh {"act": "attack"} ──▶ HacLong.Game.Session (1 tiến trình / tài khoản)
                                                        │  HacLong.Game.Commands  (kiểm tra đầu vào)
                                                        │  HacLong.Game.Engine    (luật chơi)
                                                        ▼
                                                   PostgreSQL (bảng users, characters)
```

- **Client chỉ gửi ý định** (tấn công, mua món X, cộng điểm vào Sức mạnh...). Server tính
  sát thương, rơi đồ, vàng, kinh nghiệm rồi trả về toàn bộ trạng thái nhân vật; client chỉ vẽ.
- **Mỗi tài khoản một tiến trình `Session`**: mọi lệnh được xử lý tuần tự nên mở nhiều tab
  không gây ghi đè hay nhân đôi đồ. Sau mỗi thay đổi trạng thái được ghi ngay vào database
  và đẩy sang các tab khác. Rảnh 10 phút thì tiến trình tự tắt, lần sau nạp lại từ database.
- **Trận đấu đang dở cũng được lưu** (cột `battle`), nên tải lại trang hay mất mạng không
  thoát được trận.
- **Engine Elixir là bản dịch của `js/engine.js`**. Test `engine_parity_test.exs` chơi tự
  động 1500 lượt cho mỗi lớp nhân vật rồi phát lại trên engine JS với cùng dãy số ngẫu
  nhiên; trạng thái sau từng lượt phải trùng khớp. Sửa luật chơi thì sửa cả hai file.
- **Dữ liệu game dùng chung**: `priv/game_data.json` sinh từ `js/data.js`. Sau khi sửa
  `js/data.js` chạy `node tools/export-data.js` ở thư mục gốc rồi biên dịch lại server.
- Mật khẩu băm bằng PBKDF2. Token đăng nhập ký bằng `Phoenix.Token`, hạn 30 ngày.

## Cấu trúc

```
lib/hac_long/accounts.ex            Đăng ký, đăng nhập, token
lib/hac_long/game/data.ex           Dữ liệu game (đọc priv/game_data.json)
lib/hac_long/game/engine.ex         Luật chơi, bản Elixir của js/engine.js
lib/hac_long/game/commands.ex       Lệnh từ client → hàm engine
lib/hac_long/game/session.ex        Tiến trình giữ nhân vật đang online
lib/hac_long/game/characters.ex     Đọc/ghi bảng characters
lib/hac_long_web/channels/          UserSocket, GameChannel
lib/hac_long_web/controllers/       API đăng nhập, trang chủ
lib/hac_long_web/client_static.ex   Phục vụ js/, css/, assets/ từ thư mục gốc repo
```

## Giao thức

| Kênh | Nội dung |
| --- | --- |
| `POST /api/register`, `POST /api/login` | `{username, password}` → `{token, username}` |
| `GET /api/me` | Header `Authorization: Bearer <token>` → `{username}` hoặc 401 |
| join `"game"` | → `{username, player}` (`player` là `null` nếu chưa tạo nhân vật) |
| push `"cmd"` | `{act, ...}` → `{ok, msg?, result?, player}` |
| server push `"player"` | `{player}` khi nhân vật đổi từ tab khác |

Các `act`: `create {name, cls}`, `reset`, `rest`, `hunt {zone}`, `boss {zone}`, `attack`,
`skill`, `potion`, `flee`, `again`, `leave`, `alloc {stat, n}`, `equip {id}`,
`unequip {slot}`, `use {id}`, `sell {id}`, `buy {id, n}`.

## Production

```bash
export DATABASE_URL=ecto://USER:PASS@HOST/hac_long
export SECRET_KEY_BASE=$(mix phx.gen.secret)
export PHX_HOST=game.example.com
export CLIENT_DIR=/duong/dan/toi/repo     # thư mục chứa index.html, js/, css/, assets/
MIX_ENV=prod mix do compile, ecto.migrate
MIX_ENV=prod PHX_SERVER=true mix phx.server
```
