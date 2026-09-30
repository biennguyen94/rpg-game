# Lộ trình phát triển

Các tính năng của Hắc Long RPG: đã làm gì, còn lại gì. Đánh dấu `[x]` khi làm xong.
Chi tiết kỹ thuật của từng phần nằm trong `README.md` và tài liệu đầu mỗi module.

## Còn lại (theo thứ tự đề xuất)

Ước lượng công sức: nhỏ (vài giờ), vừa (khoảng một ngày), lớn (nhiều ngày).

1. **CI chạy `mix test` trên GitHub Actions** (nhỏ). Repo chưa có kiểm tra tự động nào.
2. **Mô phỏng cân bằng có nhiệm vụ** (vừa): cho bot làm nhiệm vụ, việc hằng ngày, tháp, trùm
   thế giới để đo các nguồn thưởng mới trước khi thêm tính năng cho thêm thưởng.
3. **Đọc `X-Forwarded-For` khi chạy sau proxy** (nhỏ). Không có thì giới hạn đăng nhập theo IP
   tính chung mọi người thành IP của proxy.
4. **Đồ có chỉ số ngẫu nhiên** (vừa), **công dụng cho quặng** (nhỏ–vừa, Thợ Rèn nâng cấp đồ
   bằng quặng) và **thêm kỹ năng theo cấp** (vừa): trận đánh hiện gần như chỉ là bấm kỹ năng
   rồi tấn công, và đồ đạc chỉ là mua món tốt hơn.
5. **Hiệu ứng trạng thái** (vừa), **chuyển sinh** (nhỏ–vừa).
6. **Chặn/báo cáo người chat xấu** (nhỏ–vừa).
7. **Rương** (nhỏ), **trang trí nhà** (vừa–lớn).
8. **Chạm vào người chơi khác** (nhỏ, lối vào cho hai việc sau), **PvP bất đồng bộ** (vừa),
   **chợ giữa người chơi** (lớn).
9. **Đóng gói app Android** (PWA: nhỏ, Capacitor: vừa).

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
- [ ] **Chạy sau proxy** (nginx, load balancer): thêm plug đọc `X-Forwarded-For` để giới hạn
  theo IP thật.
- [ ] **CI**: chạy `mix test` trên GitHub Actions.

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
- [ ] **Chuyển sinh**: về cấp 1, nhận chỉ số cộng thêm vĩnh viễn.

## C. Làm game sâu hơn

- [x] **Thu thập và pha chế**: Thảo Dược, Linh Chi, Quặng Sắt, Quặng Mithril mọc trên bản đồ
  vùng; Bà Lang pha bình máu từ thảo dược.
- [ ] **Đồ có chỉ số ngẫu nhiên** rơi từ quái (vd. "Kiếm Sắt +3, Chí mạng +2%").
- [ ] **Thêm kỹ năng theo cấp**: kỹ năng thứ 2 ở cấp 15, thứ 3 ở cấp 30 cho mỗi lớp.
- [ ] **Hiệu ứng trạng thái**: độc, choáng, chảy máu (vd. quái Đầm Lầy gây độc). Mở rộng từ
  cơ chế `special` / `every` có sẵn trong engine.
- [ ] **Công dụng cho quặng**: hiện quặng chỉ để bán và nộp nhiệm vụ; có thể cho Thợ Rèn
  nâng cấp vũ khí/giáp bằng quặng.

## D. Nhiều người chơi (Phoenix Channels / PubSub)

- [x] **Chat thế giới**: khung chat dưới bản đồ, bong bóng lời nói trên đầu người cùng bản đồ,
  tin hệ thống màu riêng; giữ 50 tin gần nhất trong bộ nhớ (không lưu database).
- [x] **Trùm thế giới** (`HacLong.WorldBoss`): Cổ Long Ba Đầu xuất hiện định kỳ ở Tế Đàn, cả
  server đánh chung một thanh máu, chia thưởng theo phần sát thương, top 3 được Vảy Cổ Long,
  người ra đòn cuối thêm vàng; hết giờ thì bay đi.
- [ ] **Chặn/báo cáo người chat xấu.**
- [ ] **PvP bất đồng bộ**: đánh với bản sao chỉ số của người chơi khác (đấu trường).
- [ ] **Chợ giữa người chơi**: rao bán đồ; phải dùng transaction trong database để không bị
  nhân đôi đồ.
- [ ] **Chạm vào người chơi khác** để xem thông tin, mời PvP hoặc giao dịch (hiện người chơi
  đi xuyên qua nhau, chạm vào không có gì).

## E. Bản đồ ô vuông

- [x] **Giai đoạn 1**: định dạng bản đồ; Nhà, Làng và 6 vùng; đi lại, qua cổng, chạm quái vào
  trận; quái dùng chung, đi lang thang, hồi theo thời gian; thấy người chơi khác; bỏ tab
  "Săn quái".
- [x] **Giai đoạn 2**: mỗi vùng gồm 2 bản đồ quái (bản đồ 2 mạnh hơn) và một phòng trùm; di
  chuyển mượt; đá dịch chuyển; hỏi xác nhận trước khi đấu trùm.
- [x] **Giai đoạn 3**: NPC ở Làng thay tab Cửa hàng; điểm thu thập; nhiệm vụ.
- [ ] **Giai đoạn 4**: trang trí nhà, rương mở mỗi ngày một lần. (Trùm thế giới trên bản đồ,
  dự tính cho giai đoạn này, đã làm ở mục D.)

## F. Khác

- [ ] **Đóng gói app Android** (PWA hoặc Capacitor).
- [ ] **Mô phỏng cân bằng có nhiệm vụ**: bot `mix hac_long.simulate` chưa làm nhiệm vụ, việc
  hằng ngày, tháp hay trùm thế giới, nên chưa đo được các nguồn thưởng này ảnh hưởng thế nào.

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
