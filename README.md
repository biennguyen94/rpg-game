# Hắc Long RPG

Game nhập vai chơi trên trình duyệt, tối ưu cho điện thoại: đi trên bản đồ ô vuông, bước vào quái
để đánh, lên cấp, mua đồ, hạ trùm từng vùng và cuối cùng tiêu diệt **Hắc Long**.

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

- 3 lớp nhân vật: **Chiến Binh**, **Thích Khách**, **Hiệp Sĩ**, mỗi lớp 3 kỹ năng (mở ở cấp 1,
  10, 25)
- Bản đồ ô vuông: Nhà riêng, Làng và 6 vùng đất; mỗi vùng có 2 bản đồ quái và một phòng trùm,
  nối với nhau bằng cổng. Quái dùng chung giữa mọi người, đi lang thang và hồi lại sau khi bị hạ;
  thấy người chơi khác trên cùng bản đồ. Nhân vật và quái di chuyển mượt
- Đá dịch chuyển ở Làng và sâu trong mỗi vùng: chạm để ghi nhớ, rồi dịch chuyển qua lại
- 24 loại quái thường, 6 trùm trong phòng riêng (hỏi xác nhận trước khi đấu; hạ trùm để mở
  cổng sang vùng tiếp theo)
- Chiến đấu theo lượt: tấn công, kỹ năng (có hồi chiêu), uống máu, bỏ chạy; hiệu ứng trạng thái
  (độc, bỏng, choáng, suy yếu, cuồng nộ...)
- Đồ có chỉ số ngẫu nhiên rơi từ quái (Tốt, Hiếm, Sử Thi)
- Sổ tay quái vật: hạ đủ mốc mỗi loài thì đánh loài đó mạnh hơn
- Chuyển sinh ở cấp 50: về cấp 1 với điểm tiềm năng cộng thêm
- Ngày và đêm theo giờ Việt Nam; ban đêm có quái Bóng Đêm
- Rương Báu ở Thợ Rèn (ra đồ ngẫu nhiên), Rương Gia Truyền ở Nhà mở mỗi ngày
- Bang hội: lập/vào bang, chat bang, quỹ bang lên cấp, bảng xếp hạng bang
- Nhân vật mặc đúng đồ đang trang bị (người khác cũng thấy); thú cưng đi theo sau, thỉnh thoảng
  cắn thêm một đòn trong trận; hạ đủ 100 con một loài quái thường thì thuần phục được loài đó
- Trang trí nhà bằng đồ mua ở Thợ Mộc; nhà tiện nghi thì thêm kinh nghiệm; thăm và khen nhà
  người khác
- Tổ đội tối đa 3 người: đánh chung một con quái, chia thưởng, chat tổ đội
- Chạm vào người chơi khác để xem đồ, mời tổ đội, thách đấu ở đấu trường (PvP với bản sao chỉ số,
  điểm Elo)
- Chợ giữa người chơi: rao bán, mua; tiền bán được gửi qua hộp thư
- Giao dịch trực tiếp: hai bên bỏ đồ/vàng vào, cả hai xác nhận thì mới đổi
- Lên cấp nhận 3 điểm tiềm năng để cộng vào Sức mạnh, Thể lực, Nhanh nhẹn, Phòng thủ
- NPC trong Làng: Trưởng Làng giao nhiệm vụ, Thợ Rèn bán vũ khí/giáp/khiên, Bà Lang bán và pha
  thuốc, Chủ Quán Trọ cho nghỉ; mua bán phải đến gặp họ. 2 món đồ hiếm chỉ rơi từ trùm
- Hái Thảo Dược/Linh Chi, đào Quặng Sắt/Mithril trên bản đồ (dùng chung, mọc lại); mang đi pha
  thuốc, bán, nộp nhiệm vụ hoặc nhờ Thợ Rèn nâng cấp đồ đang mặc (tới +5)
- Câu cá ở hồ nước: phao chìm thì giật đúng lúc; Cá Chép Vàng rất hiếm; Bà Lang nấu cá thành
  bình máu; việc hằng ngày có câu cá
- 18 nhiệm vụ: mỗi vùng một việc diệt quái, một việc thu thập, một việc hạ trùm
- Việc hằng ngày ở Bảng Tin: 3 việc mới mỗi ngày cho mỗi người, theo các vùng đã mở
- Tên nhân vật không trùng nhau (không phân biệt hoa thường)
- Hướng dẫn người mới 5 bước (có vòng sáng chỉ đường trên bản đồ), xong được quà tân thủ
- 21 thành tựu, 15 danh hiệu hiện cạnh tên trong chat và bảng xếp hạng
- Hộp thư: thưởng nhận lúc vắng mặt, quà của quản trị viên
- Âm thanh tự tổng hợp (Web Audio), bật/tắt được
- Chat thế giới (bong bóng lời nói trên đầu người cùng bản đồ) và bảng xếp hạng: cấp cao nhất,
  săn nhiều nhất, ai hạ Hắc Long trước. Bấm tên người khác trong khung chat để báo cáo tin
  nhắn hoặc chặn người đó
- Trùm thế giới: Cổ Long Ba Đầu xuất hiện định kỳ ở Tế Đàn, cả server đánh chung một thanh máu,
  chia thưởng theo sát thương
- Tháp Vô Tận: leo từng tầng sinh ngẫu nhiên, quái mạnh dần không có trần, bảng kỷ lục
- Gục ngã mất 10% vàng và tỉnh dậy ở Nhà; giếng nước ở Nhà hồi máu miễn phí
- Mỗi tài khoản một nhân vật, lưu sau mỗi thao tác, chơi tiếp được trên thiết bị khác

- Quản trị viên: xử lý báo cáo, cấm chat, khóa tài khoản, thông báo cả server, tặng quà qua
  hộp thư, gọi trùm thế giới

Một lượt chơi từ đầu đến khi hạ Hắc Long mất khoảng 430 trận nếu chỉ đánh quái, khoảng 340
trận nếu làm cả nhiệm vụ và việc hằng ngày (theo mô phỏng).

## Cách hoạt động

```
Trình duyệt (priv/static: index.html, js/ui.js, js/net.js)
   │  POST /api/register, /api/login  → token
   │  WebSocket /socket?token=…  → kênh "game"
   ▼
HacLongWeb.GameChannel ── lệnh {"act": "attack"} ──▶ HacLong.Game.Session (1 tiến trình / tài khoản)
        ▲                                               │  HacLong.Game.Commands  (kiểm tra đầu vào)
        │ "map": quái, người chơi                       │  HacLong.Game.Engine    (luật chơi)
        │                                               │  HacLong.World          (đi lại, cổng, chạm quái)
        │                                               ▼
        └──── PubSub "map:<id>" ◀── HacLong.World.MapServer (1 tiến trình / bản đồ dùng chung)
                                                        │
                                                   PostgreSQL (bảng users, characters)
```

- **Client chỉ gửi ý định** (tấn công, mua món X, cộng điểm vào Sức mạnh...). Server tính sát
  thương, vàng, kinh nghiệm, đồ rơi rồi trả về trạng thái nhân vật kèm các chỉ số tính sẵn
  (`view`: máu tối đa, tấn công, giá nghỉ trọ, vùng đã mở). Client không có công thức nào.
- **Mỗi tài khoản một tiến trình `Session`**: mọi lệnh được xử lý tuần tự nên mở nhiều tab không
  gây ghi đè hay nhân đôi đồ. Sau mỗi thay đổi, trạng thái được ghi ngay vào database và đẩy sang
  các tab khác. Rảnh 10 phút thì tiến trình tự tắt, lần sau nạp lại từ database.
- **Trận đấu đang dở cũng được lưu** (cột `battle`), tải lại trang không thoát được trận.
- **Bản đồ**: mỗi bản đồ dùng chung (Làng, 6 vùng) có một tiến trình `MapServer` giữ vị trí quái
  và người chơi, xử lý lần lượt nên hai người cùng lao vào một con quái thì chỉ người đến trước
  được đánh. Server kiểm tra từng bước đi (ô kề bên, không xuyên vật cản, tối đa khoảng 11
  bước/giây). Vị trí được ghi vào database theo lô, khi đổi bản đồ, vào trận hoặc đóng game.
- **Tài khoản**: mật khẩu băm bằng PBKDF2. Mỗi lần đăng nhập tạo một token ngẫu nhiên (hạn
  30 ngày), database chỉ giữ mã băm nên thu hồi được: đăng xuất, đăng xuất mọi thiết bị, đổi
  mật khẩu. Giới hạn số lần đăng nhập/đăng ký (`HacLong.RateLimit`) và tốc độ thao tác.
- **Mất mạng**: client tự kết nối lại, hiện thanh báo và lấy trạng thái mới nhất khi vào lại.

## Cấu trúc

```
priv/game_data.json                 Dữ liệu game: lớp nhân vật, vùng đất, quái, vật phẩm, công thức, nhiệm vụ
priv/maps/*.json                    Bản đồ (vẽ bằng ký tự), cổng, NPC, chỗ sinh quái và điểm thu thập
priv/static/                        Giao diện: index.html, css/, js/ (ui, map, net, sound, doll), assets/
lib/hac_long/game/data.ex           Đọc game_data.json (giải thích các trường)
lib/hac_long/game/engine.ex         Luật chơi (hàm thuần)
lib/hac_long/game/commands.ex       Lệnh từ client → hàm engine
lib/hac_long/game/session.ex        Tiến trình giữ nhân vật đang online
lib/hac_long/game/characters.ex     Đọc/ghi bảng characters
lib/hac_long/game/quests.ex         Nhiệm vụ: nhận, tiến độ, trả và nhận thưởng
lib/hac_long/game/daily.ex          Việc hằng ngày
lib/hac_long/game/tower.ex          Tháp Vô Tận: sinh tầng, quái, lên tầng, thưởng
lib/hac_long/game/tutorial.ex       Hướng dẫn người mới
lib/hac_long/game/fishing.ex        Câu cá
lib/hac_long/game/achievements.ex   Thành tựu và danh hiệu
lib/hac_long/game/gear.ex           Đồ có chỉ số ngẫu nhiên
lib/hac_long/game/bestiary.ex       Sổ tay quái vật
lib/hac_long/game/chests.ex         Rương Báu, Rương Gia Truyền
lib/hac_long/game/pets.ex           Thú cưng
lib/hac_long/game/home.ex           Trang trí nhà
lib/hac_long/world/clock.ex         Ngày và đêm
lib/hac_long/guilds.ex              Bang hội
lib/hac_long/party.ex               Tổ đội, trận đánh chung
lib/hac_long/arena.ex               Đấu trường (PvP bất đồng bộ, điểm Elo)
lib/hac_long/market.ex              Chợ giữa người chơi
lib/hac_long/trade.ex               Giao dịch trực tiếp (bảng giao dịch trong bộ nhớ)
lib/hac_long/game/trade_offer.ex    Giao dịch trực tiếp: kiểm tra, lấy và trao đồ (hàm thuần)
lib/hac_long/homes.ex               Thăm nhà, khen nhà
lib/hac_long/game/names.ex          Kiểm tra và chuẩn hóa tên nhân vật
lib/hac_long/game/simulator.ex      Bot chơi thử để kiểm tra cân bằng
lib/hac_long/world.ex               Đi lại trên bản đồ, qua cổng, chạm quái, kết thúc trận
lib/hac_long/world/maps.ex          Đọc priv/maps (giải thích định dạng và các ký tự)
lib/hac_long/world/map_server.ex    Tiến trình giữ quái và người chơi của một bản đồ
lib/hac_long/accounts.ex            Đăng ký, đăng nhập, token
lib/hac_long/chat.ex                Chat thế giới (giữ 50 tin gần nhất)
lib/hac_long/leaderboard.ex         Bảng xếp hạng
lib/hac_long/moderation.ex          Chặn, báo cáo, cấm chat, khóa tài khoản, quyền quản trị
lib/hac_long/mailbox.ex             Hộp thư: gửi thư kèm quà, mở thư nhận quà
lib/hac_long/rate_limit.ex          Giới hạn tần suất (đăng nhập, chat...)
lib/hac_long/world_boss.ex          Trùm thế giới: lịch xuất hiện, máu chung, chia thưởng
lib/hac_long_web/channels/          UserSocket, GameChannel
lib/hac_long_web/controllers/       API đăng nhập; trang chủ (chèn dữ liệu game cho client)
lib/hac_long_web/remote_ip.ex       Lấy IP thật từ X-Forwarded-For khi chạy sau proxy tin cậy
lib/mix/tasks/                      mix hac_long.simulate, mix hac_long.admin
.github/workflows/ci.yml            CI: format, biên dịch không cảnh báo, mix test
```

## Chỉnh sửa game

- **Thêm quái / vùng / đồ**: sửa `priv/game_data.json`, khởi động lại server. Chỉ số quái được
  tính tự động từ cấp độ (`make_monster` trong `engine.ex`), dùng `mult` để làm một con mạnh
  hoặc yếu hơn. Client nhận dữ liệu này từ server nên không phải sửa gì thêm.
- **Thêm nhiệm vụ / công thức**: thêm vào `QUESTS` / `RECIPES` trong `priv/game_data.json`
  (giải thích các trường ở `lib/hac_long/game/data.ex`). Hàng NPC bán nằm ở `stock` của NPC
  trong `priv/maps/village.json`.
- **Sửa bản đồ**: sửa `priv/maps/<id>.json` (ý nghĩa các ký tự xem `lib/hac_long/world/maps.ex`),
  rồi chạy `mix test`: test kiểm tra cổng nối hai chiều và chỗ đứng hợp lệ.
- **Đổi công thức chiến đấu**: `derived`, `make_monster`, `damage` trong `lib/hac_long/game/engine.ex`.
- Sau khi đổi số, chạy mô phỏng để xem game có quá dễ hay quá khó:

```bash
mix hac_long.simulate 10
```

Kết quả in ra, cho mỗi lớp và bốn cách chơi (chỉ đánh, +nhiệm vụ, +việc hằng ngày, +nâng cấp
đồ ở Thợ Rèn), số trận
trung bình để thắng, số lần chết, vàng/kinh nghiệm từ nhiệm vụ và việc hằng ngày, và cấp độ
lúc hạ từng trùm.

## Giao thức

| Kênh | Nội dung |
| --- | --- |
| `POST /api/register`, `POST /api/login` | `{username, password}` → `{token, username}` |
| `GET /api/me` | Header `Authorization: Bearer <token>` → `{username}` hoặc 401 |
| | Tài khoản bị khóa: đăng nhập trả 403 kèm lý do và thời hạn; token cũ hết hiệu lực |
| `POST /api/logout`, `POST /api/logout_all` | (có token) đăng xuất thiết bị này / mọi thiết bị |
| `POST /api/password` | (có token) `{current, password}` → `{token, username}`; thiết bị khác bị đăng xuất |
| | Quá giới hạn thì trả 429 kèm `retry-after` |
| join `"game"` | → `{username, user_id, admin, blocked, mail, player}` (`player` là `null` nếu chưa tạo nhân vật; `blocked` là `[{id, name}]` người đã chặn; `mail` là số thư chưa mở) |
| push `"cmd"` | `{act, ...}` → `{ok, msg?, result?, player}` |
| server push `"player"` | `{player}` khi nhân vật đổi từ tab khác |
| server push `"map"` | `{map, phase, monsters, nodes, players}` (người chơi kèm `look`, `tag`) (`phase`: dawn/day/dusk/night; quái Bóng Đêm có `rare: true`) của bản đồ đang đứng, mỗi khi có thay đổi |
| push `"chat"` | `{text}` → ok hoặc `{msg}` lỗi (cả khi bị cấm chat); server đẩy `"chat"` `{id, uid, name, title, tag, map, text, at, guild?}` cho mọi người (trừ người đã chặn `uid`), `"chat_history"` lúc mới vào |
| push `"block"`, `"unblock"` | `{uid}` → `{blocked}`: chặn/bỏ chặn chat của một người |
| push `"report"` | `{id}` (id tin chat) → ok hoặc `{msg}` lỗi; tối đa 10 lần/10 phút |
| push `"guild"` | `{op, ...}`: `list {q}`, `info`, `join {id}`, `cancel {id}`, `accept`/`reject`/`kick`/`promote`/`demote`/`transfer {uid}`, `leave`, `disband`, `settings {open?, notice?}` → `{guild, msg}` (hoặc `{guilds, requested}` với `list`); server đẩy `"guild"` `{guild}` khi bang của mình đổi. Chat bang: push `"chat"` `{text, to: "guild"}` |
| push `"party"` | `{op, ...}`: `invite {uid}`, `accept`, `decline`, `leave`, `kick {uid}`, `info` → `{party}`; server đẩy `"party"` `{party}`, `"party_invite"` `{from, name}`, `"shared"` `{key, hp, n}` (máu chung khi đánh cùng). Chat tổ đội: `"chat"` `{text, to: "party"}` |
| push `"inspect"` | `{uid}` → thông tin người chơi khác: tên, lớp, cấp, `look`, danh hiệu, bang, đồ đang mặc, điểm đấu trường |
| push `"visit"` | `{uid}` → `{id, name, look, decor, comfort, likes, liked}`: nhà của người khác |
| push `"home_like"` | `{uid}` → `{likes}`: khen nhà (mỗi nhà một lần; chủ nhà nhận `"notice"`) |
| push `"trade"` | `{op, ...}`: `request {uid}`, `accept`, `decline`, `cancel`, `offer {offer: {items: {id: n}, gear: [uid], gold}}`, `ready`, `info` → `{trade}`; server đẩy `"trade"` `{trade}` (`null` khi xong/hủy) và `"trade_request"` `{from, name}`. Đổi món thì cả hai phải xác nhận lại |
| push `"arena"` | → `{me: {rating, wins, losses, today, per_day}, suggestions, top}` |
| push `"market"` | `{q?}` → `{listings: [{id, seller, name, item, count, gear, price, mine}], fee, max}` |
| push `"mail"` | → `{mails: [{id, subject, body, gold, xp, items, claimed, at}], unread}`; server đẩy `"mail"` `{unread}` khi có thư mới hoặc vừa mở thư |
| push `"admin"` | Chỉ admin. `{op, ...}`: `reports`, `lookup {name}`, `resolve {id, action: dismiss/mute/ban, minutes}`, `mute`/`ban {uid, minutes?, reason?}` (không có `minutes` là vĩnh viễn), `unmute`/`unban {uid}`, `announce {text}`, `gift {uid | all: true, subject, body?, gold?, xp?, items?}`, `world_boss` |
| server push `"world_boss"` | `{alive, name, hp, maxHp, endsAt, nextAt, now, fighters, top}` khi trùm thế giới thay đổi |
| server push `"notice"` | `{msg}`: thông báo riêng (vd. nhận thưởng trùm thế giới) |
| push `"leaderboard"` | → `{level, kills, dragon, tower, guild, arena, me}` (mỗi bảng 10 người kèm `title`, `me` là hạng theo cấp) |

Các `act`: `create {name, cls}`, `reset`, `move {dir, confirm?}` (`up`/`down`/`left`/`right`;
bước vào trùm thì nhận `confirm: "boss"`, gửi lại với `confirm: true` để đấu),
`teleport {to}` (đứng cạnh đá dịch chuyển; bước vào đá thì nhận `waystone: true`),
`attack`, `skill {skill?}` (id kỹ năng, không có thì dùng kỹ năng đầu), `potion`, `flee`, `leave`, `alloc {stat, n}`, `equip {id}`,
`unequip {slot}`, `use {id}` (`equip`, `sell`, `upgrade` nhận cả id đồ ngẫu nhiên `#...`), `rebirth`
(Trưởng Làng, cấp 50), `mail_claim {id}` (mở thư, nhận quà), `title_set {id}` (`null` để
bỏ danh hiệu), `fish_cast` (đứng cạnh nước; trả `wait` mili giây tới lúc cá cắn và `window`),
`fish_reel`, `chest_open` (Rương Gia Truyền ở Nhà), `chest_buy {tier}` (Thợ Rèn: wood/silver/gold),
`guild_create {name, tag}`, `guild_donate {amount}`, `pet_buy {id}` (Người Nuôi Thú),
`pet_tame {id}` (Người Nuôi Thú, id quái đã hạ ≥ 100 con), `pet_choose {id}` (`null` để thú ở nhà), `decor_buy {id}` (Thợ Mộc), `decor_place {id, x, y}`,
`decor_take {x, y}` (ở Nhà), `pvp_challenge {uid}` (thách đấu), `market_sell {id, count, price}`,
`market_buy {listing}`, `market_cancel {listing}` (đứng cạnh Chủ Chợ). Bước vào NPC thì nhận `npc: id`; các lệnh sau phải đứng cạnh
đúng NPC: `buy {id, n}`, `sell {id}` (Thợ Rèn, Bà Lang), `upgrade {slot}` (Thợ Rèn), `craft {id}` (Bà Lang), `rest`
(Chủ Quán Trọ), `quest_accept {id}`, `quest_turnin {id}` (Trưởng Làng), `daily_claim {i}`
(Bảng Tin), `tower_enter {floor}` (Người Gác Tháp).

Trạng thái nhân vật có `pos: {map, x, y}`, `waystones` (các đá đã ghi nhớ),
`quests: {active: {id: số_đã_hạ}, done: [id]}`, `daily: {date, tasks}`, `upgrades: {id_đồ: cấp}`,
`guild` (bang đang ở: `{id, name, tag, level, role}`, không lưu trong bảng characters),
`chest_day`, `pet`, `pets`, `furniture: {id: số}` (đồ trang trí trong kho), `decor: [{id, x, y}]`
(đồ đã đặt), `view.look` (`{hair, weapon, armor, shield, pet}`: lớp hình để vẽ nhân vật),
`view.comfort`, `fish_caught`, `gear: [{uid, base, rarity, bonus}]` (đồ ngẫu nhiên; `view.gear` có tên, chỉ số,
giá bán), `bestiary: {id_quái: số}`, `rebirths`, `battle.effects: {player, monster}` (hiệu ứng
`[{id, turns, power}]`), `battle.cds` (hồi chiêu `[{id, turns}]`), `achievements: [id]`, `title` (id thành tựu làm danh hiệu), `view.achievements`
(`[{id, done, have}]`), `view.forge` (đồ đang mặc, cấp nâng và giá lên cấp tiếp), `tutorial` (bước
hướng dẫn đang làm, `null` khi xong; `view.tutorial` là `{step, total, text, hint, target}`
với `target` là ô cần tới trên bản đồ đang đứng), `tower` (tầng tháp
đang leo: `floor, tiles, stairs, exit, monsters`, khi `pos.map` là `"tower"`), `tower_best`; khi đang đánh, `battle.encounter` cho biết con quái
nào trên bản đồ.

## Production

```bash
export DATABASE_URL=ecto://USER:PASS@HOST/hac_long
export SECRET_KEY_BASE=$(mix phx.gen.secret)
export PHX_HOST=game.example.com
MIX_ENV=prod mix do compile, ecto.migrate
MIX_ENV=prod PHX_SERVER=true mix phx.server
```

Ép buổi trong ngày để thử: `TIME_OF_DAY=night mix phx.server` (dawn, day, dusk, night).

Trùm thế giới chỉnh bằng `config :hac_long, :world_boss` hoặc biến môi trường
`WORLD_BOSS_FIRST_MINUTES`, `WORLD_BOSS_EVERY_MINUTES`, `WORLD_BOSS_DURATION_MINUTES`,
`WORLD_BOSS_HP` (vd. `WORLD_BOSS_FIRST_MINUTES=0.5 WORLD_BOSS_HP=5000 mix phx.server` để thử).

Nếu chạy sau proxy (nginx, load balancer), khai báo IP của proxy để giới hạn theo IP thấy IP
thật của người chơi (lấy từ `X-Forwarded-For`; header từ kết nối khác bị bỏ qua):

```bash
export TRUSTED_PROXIES="127.0.0.1,10.0.0.0/8"
```

Cấp hoặc thu hồi quyền quản trị (tab Quản trị hiện sau khi tải lại trang):

```bash
mix hac_long.admin TÊN_ĐĂNG_NHẬP            # MIX_ENV=prod khi chạy trên server
mix hac_long.admin TÊN_ĐĂNG_NHẬP --revoke
```

## Hướng phát triển tiếp

Xem [docs/ROADMAP.md](docs/ROADMAP.md): giới hạn tần suất, bảng xếp hạng, nhiệm vụ hằng ngày,
chat, trùm thế giới, bản đồ ô vuông để đi lại và đánh quái...

## Bản quyền hình ảnh

Hình quái vật và ô bản đồ từ Dungeon Crawl Stone Soup (CC0) và icon từ game-icons.net (CC BY 3.0).
Chi tiết và ghi tên tác giả xem [CREDITS.md](CREDITS.md).
