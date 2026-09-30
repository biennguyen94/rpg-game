# Lộ trình phát triển

Các tính năng của Hắc Long RPG: đã làm gì, còn lại gì. Đánh dấu `[x]` khi làm xong.
Chi tiết kỹ thuật của từng phần nằm trong `README.md` và tài liệu đầu mỗi module.

## Còn lại (theo thứ tự đề xuất)

Ước lượng công sức: nhỏ (vài giờ), vừa (khoảng một ngày), lớn (nhiều ngày).

1. **Đóng gói app Android** (PWA: nhỏ, Capacitor: vừa).
2. Các việc còn mở trong từng mục dưới đây (thăm nhà người khác, thú hỗ trợ đánh, nhạc nền,
   nhiệm vụ bang, giao dịch trực tiếp...).

---

## A. Cần làm trước khi mở cho người khác chơi

- [x] **Giới hạn tần suất** (`HacLong.RateLimit`, bộ đếm trong ETS):
  - đăng nhập 10 lần/5 phút mỗi tên tài khoản, 30 lần/5 phút mỗi IP;
  - đăng ký 5 tài khoản/giờ mỗi IP; đổi mật khẩu 5 lần/5 phút; chat 5 tin/10 giây;
  - trong game (`Session`): khoảng 12 lệnh/giây, bước đi khoảng 11 bước/giây.
- [x] **Đăng xuất, đăng xuất mọi thiết bị, đổi mật khẩu**: token lưu trong bảng `user_tokens`
  (chỉ lưu mã băm), mỗi thiết bị một token; thu hồi token thì ngắt luôn kết nối game đang mở.
- [x] **Tự kết nối lại khi mất mạng**: thanh "Mất kết nối, đang kết nối lại…", vào lại kênh
  thì lấy trạng thái mới nhất; token bị thu hồi thì về màn đăng nhập.
- [x] **Tên nhân vật duy nhất** (không phân biệt hoa thường; 2–16 ký tự chữ có dấu, số,
  khoảng trắng, `-`, `_`), để không mạo danh trong chat và bảng xếp hạng.
- [x] **Chạy sau proxy** (`HacLongWeb.RemoteIp`): đọc `X-Forwarded-For` chỉ khi kết nối đến
  từ proxy tin cậy (biến `TRUSTED_PROXIES`, nhận cả dải CIDR), lấy IP ngoài cùng bên phải
  không phải proxy, nên người chơi không giả IP được.
- [x] **CI**: GitHub Actions chạy `mix format --check-formatted`, biên dịch không cảnh báo và
  `mix test` (có Postgres) cho mỗi PR và mỗi lần đẩy lên `main`.
- [x] **Hướng dẫn người mới** (`HacLong.Game.Tutorial`): 5 bước "Ra khỏi nhà" → "Gặp Trưởng
  Làng" → "Ra Rừng Mê" → "Hạ 5 Dơi Hang" → "Về trả việc", thẻ hướng dẫn trên bản đồ, vòng
  sáng và mũi tên chỉ tới NPC hoặc cổng cần đi; xong được quà tân thủ, bỏ qua được.
- [x] **Công cụ quản trị** (`HacLong.Moderation`, tab Quản trị chỉ hiện với admin; cấp quyền
  bằng `mix hac_long.admin TÊN`): xử lý báo cáo, tra cứu người chơi, cấm chat có thời hạn,
  khóa tài khoản (thu hồi token, ngắt kết nối, lúc đăng nhập báo lý do và thời hạn), gửi
  thông báo cho cả server, gọi trùm thế giới. Mọi thao tác ghi log.
  - [x] Gửi quà cho một người hoặc mọi người (qua hộp thư).

## B. Giữ người chơi quay lại

- [x] **Bảng xếp hạng** (tab Hành trình): cấp cao nhất, săn nhiều quái nhất, Tháp Vô Tận,
  ai hạ Hắc Long trước; hiện hạng của mình.
- [x] **Nhiệm vụ** ở Trưởng Làng: 18 việc, mỗi vùng một việc diệt quái, một việc thu thập,
  một việc hạ trùm; tab Nhiệm vụ theo dõi tiến độ.
- [x] **Việc hằng ngày** ở Bảng Tin: mỗi ngày 3 việc riêng cho mỗi người (hạ một loại quái,
  hạ quái ở một vùng, hái/đào nguyên liệu) ở hai vùng cao nhất đã mở; tự tính tiến độ; làm mới
  lúc 0 giờ giờ Việt Nam.
- [x] **Tháp Vô Tận** (gặp Người Gác Tháp ở Làng): mỗi tầng một bản đồ nhỏ sinh ngẫu nhiên riêng
  cho mình; tầng N có quái cấp N, từ tầng 37 mạnh thêm 4% mỗi tầng (không có trần); 5 tầng một
  trùm tầng; hạ hết quái thì lên tầng và nhận thưởng; máu không tự hồi, gục ngã là hết lượt;
  vượt mỗi 10 tầng thì lần sau vào thẳng được.
- [x] **Chuyển sinh**: ở cấp 50 gặp Trưởng Làng để về cấp 1, giữ vàng, đồ, vùng đã mở, nhiệm vụ,
  thành tựu; mỗi lần cho thêm 15 điểm tiềm năng vĩnh viễn (tối đa 10 lần). Bảng xếp hạng cấp
  tính số lần chuyển sinh trước.
- [x] **Danh hiệu và thành tựu** (`HacLong.Game.Achievements`): 21 thành tựu (săn quái, trùm,
  diệt rồng, cấp, nhiệm vụ, đá dịch chuyển, tháp, câu cá, rèn +5, Vảy Cổ Long, vàng, số lần
  gục ngã), tính từ trạng thái nhân vật nên người cũ nhận ngay; 15 cái cho danh hiệu, chọn ở tab
  Nhân vật, hiện cạnh tên trong chat và bảng xếp hạng.
  - [ ] Thành tựu cần đếm thêm: top 3 trùm thế giới, số việc hằng ngày đã làm.
- [x] **Sổ tay quái vật** (`HacLong.Game.Bestiary`): đếm số con đã hạ của 30 loài; 25 con thì
  +5% sát thương lên loài đó, 100 con +10%, mỗi mốc thưởng vàng. Thẻ ở tab Hành trình, loài
  chưa gặp hiện bóng đen.

## C. Làm game sâu hơn

- [x] **Thu thập và pha chế**: Thảo Dược, Linh Chi, Quặng Sắt, Quặng Mithril mọc trên bản đồ
  vùng; Bà Lang pha bình máu từ thảo dược.
- [x] **Đồ có chỉ số ngẫu nhiên** (`HacLong.Game.Gear`): quái rơi đồ (4% quái thường, 35% trùm,
  50% trùm tầng tháp) theo đồ gốc hợp cấp quái, kèm 1–3 dòng chỉ số cộng thêm (Tốt, Hiếm, Sử
  Thi). Mỗi món một bản riêng; mặc, bán, nâng cấp như đồ thường; túi tối đa 20 món.
- [x] **Thêm kỹ năng theo cấp**: mỗi lớp thêm 2 kỹ năng ở cấp 10 và 25 (choáng, cuồng nộ, tẩm
  độc, ảnh bộ, thủ thế, làm suy yếu), hồi chiêu riêng từng kỹ năng.
- [x] **Hiệu ứng trạng thái**: độc, bỏng, chảy máu, choáng, suy yếu, cuồng nộ, thủ thế, ảnh bộ.
  Đòn đặc biệt của trùm và một số quái gây hiệu ứng; bình máu giải độc/bỏng/chảy máu.
- [x] **Công dụng cho quặng**: Thợ Rèn nâng đồ đang mặc tới +5 (mỗi cấp +8% chỉ số gốc) bằng
  Quặng Sắt hoặc Mithril và vàng; +5 cần thêm Vảy Cổ Long. Cấp nâng giữ theo món đồ. Mô phỏng:
  không đổi số trận (tiến độ theo cấp) nhưng hút bớt khoảng một nửa vàng thừa cuối game.

## D. Nhiều người chơi (Phoenix Channels / PubSub)

- [x] **Chat thế giới**: khung chat dưới bản đồ, bong bóng lời nói trên đầu người cùng bản đồ,
  tin hệ thống màu riêng; giữ 50 tin gần nhất trong bộ nhớ (không lưu database).
- [x] **Trùm thế giới** (`HacLong.WorldBoss`): Cổ Long Ba Đầu xuất hiện định kỳ ở Tế Đàn, cả
  server đánh chung một thanh máu, chia thưởng theo phần sát thương, top 3 được Vảy Cổ Long,
  người ra đòn cuối thêm vàng; hết giờ thì bay đi.
- [x] **Chặn/báo cáo người chat xấu**: bấm tên trong khung chat để báo cáo tin đó (quản trị
  viên xử lý ở tab Quản trị) hoặc chặn người đó (không thấy chat của họ nữa; bỏ chặn trong thẻ
  Dữ liệu ở tab Làng).
- [x] **PvP bất đồng bộ** (`HacLong.Arena`, bảng `pvp`): đánh với bản sao chỉ số của người khác
  (đọc từ database, họ không cần online, mặc đúng đồ); điểm Elo cho cả hai; thắng thêm ít vàng,
  thua không mất gì; 15 trận mỗi ngày; đối thủ gợi ý gần điểm; bảng xếp hạng đấu trường.
- [x] **Chợ giữa người chơi** (`HacLong.Market`, Chủ Chợ trong Làng): rao bán đồ thường hoặc đồ
  chỉ số ngẫu nhiên (giữ cấp nâng), mua, rút về. Mua trong transaction khóa dòng hàng nên không
  nhân đôi đồ; người bán nhận tiền qua hộp thư, trừ 5% phí.
- [x] **Hộp thư** (`HacLong.Mailbox`): thư hệ thống kèm quà (vàng, kinh nghiệm, đồ); nút phong
  bì trên HUD có số thư chưa mở. Mở thư là nhận quà, trong cùng transaction với lần ghi nhân vật
  nên không nhận đôi. Thưởng trùm thế giới lúc không online gửi qua đây; quản trị viên tặng quà
  cho một người hoặc mọi người.
  - [x] Nhận tiền khi bán được đồ ở chợ.
- [x] **Bang hội** (`HacLong.Guilds`): lập bang 5.000 vàng (tên, ký hiệu không trùng); bang mở
  vào ngay, bang đóng thì xin vào; bang chủ / phó bang / thành viên (phong, nhường, mời ra, rời,
  giải tán); góp quỹ lên cấp (tối đa 5: thêm chỗ, +2% kinh nghiệm mỗi cấp từ cấp 2); kênh chat
  bang; ký hiệu bang cạnh tên trong chat; bảng xếp hạng bang theo quỹ.
  - [ ] Bảng xếp hạng bang theo sát thương lên trùm thế giới; nhiệm vụ bang.
- [x] **Tổ đội** (`HacLong.Party`, giữ trong bộ nhớ): mời người đang online (tối đa 3), kênh chat
  tổ đội, thẻ tổ đội có máu từng người. Đồng đội chạm vào con quái mình đang đánh thì vào cùng
  trận, máu quái chung; quái gục thì mọi người cùng thắng, được tính nhiệm vụ/việc hằng
  ngày/sổ tay; thưởng mỗi người = gốc × 1,2 / số người.
- [x] **Chạm vào người chơi khác**: xem cấp, lớp, bang, danh hiệu, đồ đang mặc, điểm đấu trường;
  mời tổ đội, thách đấu, chặn chat.
  - [ ] Giao dịch trực tiếp giữa hai người (hiện dùng chợ).

## E. Bản đồ ô vuông

- [x] **Giai đoạn 1**: định dạng bản đồ; Nhà, Làng và 6 vùng; đi lại, qua cổng, chạm quái vào
  trận; quái dùng chung, đi lang thang, hồi theo thời gian; thấy người chơi khác; bỏ tab
  "Săn quái".
- [x] **Giai đoạn 2**: mỗi vùng gồm 2 bản đồ quái (bản đồ 2 mạnh hơn) và một phòng trùm; di
  chuyển mượt; đá dịch chuyển; hỏi xác nhận trước khi đấu trùm.
- [x] **Giai đoạn 3**: NPC ở Làng thay tab Cửa hàng; điểm thu thập; nhiệm vụ.
- [x] **Giai đoạn 4**: trang trí nhà, rương mở mỗi ngày một lần, trùm thế giới.
- [x] **Trang trí nhà** (`HacLong.Game.Home`): Thợ Mộc trong Làng bán 13 món (chậu cây, đèn lồng,
  tượng, cây, đài phun nước, tượng vàng...); về Nhà bấm Trang trí, chọn món rồi chạm ô để đặt,
  chạm đồ đã đặt để cất. Đồ chặn đường, không được chắn lối; mỗi 10 điểm tiện nghi +1% kinh
  nghiệm mỗi trận (tối đa +5%).
  - [ ] Cho người khác vào thăm nhà.
- [x] **Rương** (`HacLong.Game.Chests`): Rương Gia Truyền ở Nhà mở mỗi ngày một lần (vàng, bình
  máu, nguyên liệu, 20% kèm đồ); Thợ Rèn bán Rương Gỗ/Bạc/Vàng ra đồ chỉ số ngẫu nhiên, giá gấp
  2/4/8 lần giá bán lại vũ khí tốt nhất cùng cấp nên mua về bán lại luôn lỗ. Mô phỏng: bot mua
  rương tiêu 7.000–16.000 vàng mỗi ván.
- [x] **Câu cá** (`HacLong.Game.Fishing`): đứng cạnh nước bất kỳ (hồ Làng, Rừng Mê, Đầm Lầy,
  Hang Rồng) bấm Câu cá; phao chìm sau 3–8 giây, giật trong 1 giây mới được (server tính giờ).
  Cá Diếc, Cá Chép, Lươn Điện ở vùng sâu, Cá Chép Vàng rất hiếm, và ủng cũ. Tiền câu cá ngang
  đánh quái lúc đầu game nhưng không có kinh nghiệm.
  - [ ] Công thức nấu cá ở Bà Lang; việc hằng ngày câu cá.
- [x] **Ngày và đêm** (`HacLong.World.Clock`): bình minh, ngày, hoàng hôn, đêm theo giờ Việt
  Nam; bản đồ ngoài trời tối dần, quanh nhân vật vẫn sáng. Ban đêm 12% quái mới sinh là quái
  Bóng Đêm (mạnh gấp rưỡi, thưởng gấp rưỡi, 25% rơi đồ). Ép buổi để thử bằng `TIME_OF_DAY`.

## F. Hình ảnh và âm thanh

- [x] **Âm thanh** (`priv/static/js/sound.js`): hiệu ứng tổng hợp bằng Web Audio, không cần
  file: đánh, chí mạng, trượt, bị đánh, kỹ năng, thắng/thua, lên cấp, mua bán, hái/đào, qua
  cổng, rèn, pha thuốc, nhiệm vụ, thư mới, câu cá, thành tựu. Bật/tắt và âm lượng ở tab Hành
  trình.
  - [ ] Nhạc nền nhẹ (cần bộ nhạc CC0 hoặc tự tổng hợp).
- [x] **Nhân vật mặc đúng đồ đang trang bị** (`priv/static/js/doll.js`): ghép thân, quần, giày,
  tóc theo lớp nhân vật, giáp, vũ khí, khiên (`doll` trong dữ liệu đồ, lớp hình từ `player/`
  của Dungeon Crawl, đã đối chiếu danh sách chưa rõ giấy phép). Hiện ở HUD, tab Nhân vật, trận
  đánh và trên bản đồ; người cùng bản đồ thấy đồ của nhau (`look` gửi kèm trạng thái bản đồ).
- [x] **Thú cưng** (`HacLong.Game.Pets`): Người Nuôi Thú trong Làng bán 6 con (Cừu Bông, Chó
  Săn, Heo Hồng, Sóc Túi, Bướm Lửa, Bằng Mã Lửa), mỗi con cộng một ít máu/tấn công/phòng thủ/
  vàng/kinh nghiệm. Thú đang dắt đi sau nhân vật một ô, người khác cũng thấy; đổi ở tab Nhân vật.
  - [ ] Thuần phục quái đã hạ nhiều lần; thú hỗ trợ đánh trong trận.

## G. Khác

- [ ] **Đóng gói app Android** (PWA hoặc Capacitor).
- [x] **Mô phỏng cân bằng có nhiệm vụ**: `mix hac_long.simulate` so ba cách chơi (chỉ đánh,
  +nhiệm vụ, +việc hằng ngày với 60 trận một ngày, hái nguyên liệu mỗi 3 trận). Kết quả: nhiệm
  vụ rút khoảng 15% số trận tới Hắc Long (~430 → ~370), hằng ngày thêm ~7% (~340); cấp lúc hạ
  từng trùm không đổi. Phần thưởng hợp lý, chưa cần chỉnh.
  - [ ] Cho bot leo tháp và đánh trùm thế giới (cần giả lập nhiều người chơi).

---

## Thiết kế bản đồ (đã làm)

### Các bản đồ

```
                 [Rừng Mê 1] → [Rừng Mê 2] → [Hang Sói (trùm)]
                 [Trại Goblin 1] → [Trại Goblin 2] → [Lều Tướng Orc]
[Nhà riêng] ─── [Làng] ─ 6 cổng ─ ... (mỗi vùng: bản đồ 1 → bản đồ 2 → phòng trùm)
                   │
                   ├── cổng dưới trái → [Tế Đàn] (trùm thế giới)
                   └── Người Gác Tháp → [Tháp Vô Tận] (tầng sinh ngẫu nhiên, riêng từng người)
```

- **Nhà riêng**: mỗi người một bản đồ riêng, có giếng nước hồi đầy máu miễn phí (bộ hình không
  có giường). Gục ngã thì tỉnh dậy ở đây.
- **Làng**: bản đồ chung; 6 cổng sang 6 vùng (cổng vào vùng chưa mở bị khóa), NPC, đá dịch
  chuyển, cổng Tế Đàn.
- **Mỗi vùng**: `<vùng>_1` (quái yếu hơn) → `<vùng>_2` (quái mạnh hơn, có đá dịch chuyển) →
  `<vùng>_boss` (phòng trùm).
- **Tháp Vô Tận**: không có file bản đồ; tầng được sinh từ `HacLong.Game.Tower` và nằm trong
  trạng thái nhân vật.

### Định dạng file

Mỗi bản đồ một file `priv/maps/<id>.json`. Ý nghĩa các ký tự (dùng chung cho mọi bản đồ) và
các trường nằm ở `lib/hac_long/world/maps.ex`. Ví dụ rút gọn:

```json
{
  "id": "forest_2", "name": "Rừng Mê 2", "zone": 0, "floor": "floors/forest",
  "tiles": ["TTTTTTTTTTTTTATTTTTTTTTTTT", "T......*.....::*.....*T..T", "..."],
  "portals": [
    { "at": [13, 17], "to": "forest_1", "spawn": [13, 1] },
    { "at": [13, 0], "to": "forest_boss", "spawn": [7, 9] }
  ],
  "spawns": [{ "monster": "spider", "max": 3, "respawn": 25 }],
  "gather": [{ "item": "herb", "max": 2, "respawn": 60 }],
  "waystone": { "at": [16, 15], "spawn": [16, 16] }
}
```

Các trường khác: `boss` (chỗ trùm vùng đứng), `npcs` (NPC và vai trò), `world_boss` (chỗ trùm
thế giới), `private` (bản đồ riêng từng người). Hình ô lấy từ Dungeon Crawl Stone Soup (CC0);
hình bảng tin và cầu thang tự vẽ.

### Chạm vào ô

| Chạm vào | Kết quả |
| --- | --- |
| Quái | Vào trận. Thắng: quái biến mất, hồi lại sau vài chục giây. Chạy thoát: đứng yên, quái được nhả ra. Thua: tỉnh dậy ở Nhà |
| Trùm vùng, trùm thế giới | Hỏi xác nhận trước khi đấu (cảnh báo nếu cấp còn thấp) |
| Cổng | Sang bản đồ khác (cổng vào vùng chưa mở bị khóa) |
| Đá dịch chuyển | Lần đầu thì ghi nhớ; mở bảng chọn nơi đến (Làng và các đá đã ghi nhớ) |
| NPC | Mở màn hình nói chuyện: nhiệm vụ, mua bán, pha thuốc, nghỉ trọ, việc hằng ngày, vào tháp |
| Bụi thảo dược, mỏ quặng | Nhận nguyên liệu; điểm đó biến mất và mọc lại chỗ khác |
| Giếng nước ở Nhà | Hồi đầy máu |
| Cầu thang trong tháp | Lên tầng (khi đã hạ hết quái) hoặc về Làng |
| Người chơi khác | Đi xuyên qua, chưa có tương tác |

### Kiến trúc server

- **Mỗi bản đồ dùng chung một tiến trình `MapServer`**: giữ quái, điểm thu thập, người chơi
  đang có mặt; xử lý lần lượt nên người chạm quái trước được đánh, người sau thấy quái đang
  giao chiến; phát trạng thái qua PubSub `map:<id>`. Nhà và tháp không có tiến trình riêng
  (chỉ một người nên chỉ cần kiểm tra địa hình).
- **Server kiểm tra từng bước đi**: chỉ sang ô kề bên, không xuyên vật cản, giới hạn tốc độ.
  Client gửi từng bước, nhận vị trí mới rồi mới đi tiếp (khoảng 7–8 bước/giây), và trượt hình
  giữa hai ô cho mượt.
- **Thấy người chơi khác**: `MapServer` ghi ai đang ở bản đồ (theo tab đang mở của người đó)
  và gửi kèm trong trạng thái bản đồ.
- **Database**: bảng `characters` có `map_id`, `x`, `y`; vị trí được ghi theo lô, và ghi ngay
  khi đổi bản đồ, vào trận hoặc đóng game.

### Giao diện điện thoại

- Canvas 2D, ảnh giữ nét pixel; camera đi theo nhân vật.
- Điều khiển: chạm vào ô để tự tìm đường (tìm theo chiều rộng), nút 4 hướng, phím mũi tên
  hoặc WASD. Đường đi tự động không đi ngang qua cổng và cầu thang.
- Tab Nhân vật, Túi đồ, Nhiệm vụ, Hành trình giữ dạng menu; màn đánh nhau như cũ.

### Đã quyết định

- **Quái dùng chung**: mọi người trong cùng bản đồ thấy cùng một bầy quái; trùm cũng dùng chung.
- **Bỏ nút "Săn quái nhanh"**: chỉ gặp quái bằng cách đi trên bản đồ.
- **Quái đi lang thang** chậm, không đuổi theo người chơi; trận chỉ bắt đầu khi người chơi
  bước vào ô có quái.
