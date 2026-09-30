# Hắc Long RPG

Game nhập vai chơi trên trình duyệt, tối ưu cho điện thoại. Lấy cảm hứng từ các game RPG web kiểu
menu: đánh quái, lên cấp, mua đồ, hạ trùm từng vùng và cuối cùng tiêu diệt **Hắc Long**.

Server viết bằng **Elixir + Phoenix + PostgreSQL**: đăng ký/đăng nhập, nhân vật lưu trong
database, toàn bộ luật chơi (chiến đấu, rơi đồ, mua bán) chạy trên server. Trình duyệt chỉ
vẽ giao diện và gửi thao tác qua Phoenix Channels, nên không sửa được chỉ số từ phía người chơi.

## Chạy

Cần Elixir ≥ 1.14 (OTP ≥ 25) và PostgreSQL (mặc định `postgres`/`postgres` trên `localhost`,
sửa trong `config/dev.exs`).

```bash
mix setup          # tải thư viện, tạo database, chạy migration
mix phx.server     # mở http://localhost:4000
mix test           # chạy test (cần PostgreSQL)
```

## Nội dung

- 3 lớp nhân vật: **Chiến Binh**, **Thích Khách**, **Hiệp Sĩ**, mỗi lớp một kỹ năng riêng
- 6 vùng đất, 24 loại quái thường, 6 trùm (hạ trùm để mở vùng tiếp theo)
- Chiến đấu theo lượt: tấn công, kỹ năng (có hồi chiêu), uống máu, bỏ chạy
- Lên cấp nhận 3 điểm tiềm năng để cộng vào Sức mạnh, Thể lực, Nhanh nhẹn, Phòng thủ
- Cửa hàng vũ khí, giáp, khiên, bình máu; 2 món đồ hiếm chỉ rơi từ trùm
- Gục ngã mất 10% vàng và về làng
- Mỗi tài khoản một nhân vật, lưu sau mỗi thao tác, chơi tiếp được trên thiết bị khác

Một lượt chơi từ đầu đến khi hạ Hắc Long mất khoảng 430 trận (theo mô phỏng).

## Cách hoạt động

```
Trình duyệt (priv/static: index.html, js/ui.js, js/net.js)
   │  POST /api/register, /api/login  → token
   │  WebSocket /socket?token=…  → kênh "game"
   ▼
HacLongWeb.GameChannel ── lệnh {"act": "attack"} ──▶ HacLong.Game.Session (1 tiến trình / tài khoản)
                                                        │  HacLong.Game.Commands  (kiểm tra đầu vào)
                                                        │  HacLong.Game.Engine    (luật chơi)
                                                        ▼
                                                   PostgreSQL (bảng users, characters)
```

- **Client chỉ gửi ý định** (tấn công, mua món X, cộng điểm vào Sức mạnh...). Server tính sát
  thương, vàng, kinh nghiệm, đồ rơi rồi trả về trạng thái nhân vật kèm các chỉ số tính sẵn
  (`view`: máu tối đa, tấn công, giá nghỉ trọ, vùng đã mở). Client không có công thức nào.
- **Mỗi tài khoản một tiến trình `Session`**: mọi lệnh được xử lý tuần tự nên mở nhiều tab không
  gây ghi đè hay nhân đôi đồ. Sau mỗi thay đổi, trạng thái được ghi ngay vào database và đẩy sang
  các tab khác. Rảnh 10 phút thì tiến trình tự tắt, lần sau nạp lại từ database.
- **Trận đấu đang dở cũng được lưu** (cột `battle`), tải lại trang không thoát được trận.
- Mật khẩu băm bằng PBKDF2. Token đăng nhập ký bằng `Phoenix.Token`, hạn 30 ngày.

## Cấu trúc

```
priv/game_data.json                 Dữ liệu game: lớp nhân vật, vùng đất, quái, vật phẩm, cửa hàng
priv/static/                        Giao diện: index.html, css/, js/ui.js, js/net.js, assets/
lib/hac_long/game/data.ex           Đọc game_data.json (giải thích các trường)
lib/hac_long/game/engine.ex         Luật chơi (hàm thuần)
lib/hac_long/game/commands.ex       Lệnh từ client → hàm engine
lib/hac_long/game/session.ex        Tiến trình giữ nhân vật đang online
lib/hac_long/game/characters.ex     Đọc/ghi bảng characters
lib/hac_long/game/simulator.ex      Bot chơi thử để kiểm tra cân bằng
lib/hac_long/accounts.ex            Đăng ký, đăng nhập, token
lib/hac_long_web/channels/          UserSocket, GameChannel
lib/hac_long_web/controllers/       API đăng nhập; trang chủ (chèn dữ liệu game cho client)
```

## Chỉnh sửa game

- **Thêm quái / vùng / đồ**: sửa `priv/game_data.json`, khởi động lại server. Chỉ số quái được
  tính tự động từ cấp độ (`make_monster` trong `engine.ex`), dùng `mult` để làm một con mạnh
  hoặc yếu hơn. Client nhận dữ liệu này từ server nên không phải sửa gì thêm.
- **Đổi công thức chiến đấu**: `derived`, `make_monster`, `damage` trong `lib/hac_long/game/engine.ex`.
- Sau khi đổi số, chạy mô phỏng để xem game có quá dễ hay quá khó:

```bash
mix hac_long.simulate 10
```

Kết quả in ra số trận trung bình để thắng, số lần chết và cấp độ lúc hạ từng trùm.

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
MIX_ENV=prod mix do compile, ecto.migrate
MIX_ENV=prod PHX_SERVER=true mix phx.server
```

## Hướng phát triển tiếp

Xem [docs/ROADMAP.md](docs/ROADMAP.md): giới hạn tần suất, bảng xếp hạng, nhiệm vụ hằng ngày,
chat, trùm thế giới, bản đồ ô vuông để đi lại và đánh quái...

## Bản quyền hình ảnh

Hình quái vật từ Dungeon Crawl Stone Soup (CC0) và icon từ game-icons.net (CC BY 3.0).
Chi tiết và ghi tên tác giả xem [CREDITS.md](CREDITS.md).
