# Lộ trình phát triển

Các tính năng dự định cho Hắc Long RPG, xếp theo thứ tự ưu tiên. Đánh dấu `[x]` khi làm xong.

## Thứ tự đề xuất

1. Giới hạn tần suất và tự kết nối lại (mục A): bắt buộc, làm nhanh.
2. Bảng xếp hạng và chat thế giới (mục B, D): rẻ, thấy ngay giá trị online.
3. Bản đồ ô vuông, giai đoạn 1 (mục E).
4. Nhiệm vụ hằng ngày và Tháp vô tận (mục B).
5. Trùm thế giới (mục D).

---

## A. Cần làm trước khi mở cho người khác chơi

- [x] **Giới hạn tần suất (rate limit)**
  - Đăng nhập: 10 lần/5 phút mỗi tên tài khoản, 30 lần/5 phút mỗi IP; đăng ký 5 tài
    khoản/giờ mỗi IP; đổi mật khẩu 5 lần/5 phút (`HacLong.RateLimit`, bộ đếm trong ETS).
  - Lệnh game: khoảng 12 lệnh/giây (bước đi khoảng 11 bước/giây) trong `Session`.
- [x] **Đổi mật khẩu, đăng xuất khỏi mọi thiết bị.** Token lưu trong bảng `user_tokens`
  (chỉ lưu mã băm), mỗi thiết bị một token; đăng xuất, đăng xuất mọi thiết bị, đổi mật
  khẩu đều thu hồi token và ngắt kết nối game đang mở.
- [x] **Tự kết nối lại khi mất mạng.** Thanh "Mất kết nối, đang kết nối lại…", tự vào lại
  kênh và lấy trạng thái mới nhất; token bị thu hồi thì về màn đăng nhập.
- [ ] Chạy sau proxy (nginx, load balancer): thêm plug đọc `X-Forwarded-For` để giới hạn
  theo IP thật.

## B. Giữ người chơi quay lại

- [x] **Bảng xếp hạng**: cấp cao nhất, săn nhiều quái nhất, và ai hạ Hắc Long trước (ghi
  thời điểm `victory_at`); hiện hạng của mình. Ở tab Hành trình.
- [ ] **Nhiệm vụ hằng ngày**, ví dụ "Hạ 20 quái ở Nghĩa Địa Cổ", "Thắng 1 trùm"; thưởng vàng
  hoặc bình máu, làm mới mỗi ngày. Hiện sau khoảng 430 trận là phá đảo và hết việc để làm.
- [ ] **Nội dung sau khi phá đảo**
  - Tháp vô tận: mỗi tầng quái mạnh hơn, có bảng kỷ lục tầng cao nhất.
  - Chuyển sinh: về cấp 1, nhận chỉ số cộng thêm vĩnh viễn.

## C. Làm game sâu hơn

- [ ] **Đồ có chỉ số ngẫu nhiên** rơi từ quái (vd. "Kiếm Sắt +3, Chí mạng +2%"), cho người
  chơi lý do đi săn thay vì chỉ mua món tốt hơn.
- [ ] **Thêm kỹ năng theo cấp**: kỹ năng thứ 2 ở cấp 15, thứ 3 ở cấp 30 cho mỗi lớp.
- [ ] **Hiệu ứng trạng thái**: độc, choáng, chảy máu (vd. quái Đầm Lầy gây độc). Mở rộng từ
  cơ chế `special` / `every` có sẵn trong engine.

## D. Tính năng nhiều người chơi (Phoenix Channels / PubSub)

- [x] **Chat thế giới**: khung chat dưới bản đồ, bong bóng lời nói trên đầu người đang ở
  cùng bản đồ, giữ 50 tin gần nhất trong bộ nhớ (không lưu database), 5 tin/10 giây mỗi người.
- [x] Tên nhân vật duy nhất (không phân biệt hoa thường, 2–16 ký tự chữ/số/khoảng trắng/-/_),
  để không mạo danh trong chat và bảng xếp hạng.
- [ ] Chặn/báo cáo người chat xấu.
- [ ] **Trùm thế giới**: trùm cực mạnh xuất hiện theo giờ, mọi người đánh chung một thanh máu
  theo thời gian thực, chia thưởng theo sát thương. Một GenServer giữ máu trùm và phát cho mọi người.
- [ ] **Chợ giữa người chơi**: rao bán đồ. Phải dùng transaction trong database để không
  bị nhân đôi đồ.
- [ ] **PvP bất đồng bộ**: đánh với bản sao chỉ số của người chơi khác (đấu trường).

## E. Bản đồ ô vuông và di chuyển

Thay tab "Săn quái" bằng thế giới gồm nhiều bản đồ ô vuông (kiểu Pokémon đời đầu).
Nhân vật là 1 ô, đi từng bước. Quái là 1 ô trên bản đồ. Chạm vào quái thì vào màn đánh
nhau hiện tại. Engine chiến đấu giữ nguyên, chỉ đổi cách bắt đầu trận.

### Hệ thống bản đồ

```
[Nhà riêng] ──cửa──> [Làng] ──cổng Bắc──> [Rừng Mê 1] ──> [Rừng Mê 2] ──> [Hang Sói (trùm)]
                        │
                        └──cổng Đông──> [Trại Goblin 1] ──> ...
```

- **Nhà riêng**: mỗi người chơi một bản đồ riêng. Giường để nghỉ miễn phí, rương cất đồ,
  sau này cho trang trí nhà.
- **Làng**: bản đồ chung. NPC bán đồ (thay tab Cửa hàng), nhà trọ, bảng nhiệm vụ.
- **Bản đồ quái**: mỗi vùng hiện tại (6 vùng) tách thành 2–3 bản đồ, bản đồ cuối là phòng trùm.
- **Phòng trùm**: khóa bằng điều kiện có sẵn `zone_unlocked?`.

### Định dạng bản đồ

Mỗi bản đồ một file `priv/maps/<id>.json`, vẽ bằng ký tự để dễ sửa tay:

```json
{
  "id": "forest_1", "name": "Rừng Mê", "zone": 0, "floor": "forest",
  "tiles": [
    "TTTTTTTTTTTTTTTT",
    "T......TT.....>T",
    "T..~~..T..R....T",
    "T..~~.....R..h.T",
    "T<.............T",
    "TTTTTTTTTTTTTTTT"
  ],
  "legend": { "T": "tree", "R": "rock", "~": "water", ".": "grass", "h": "herb" },
  "portals": [
    { "at": [1, 4],  "to": "village",  "spawn": [14, 2] },
    { "at": [14, 1], "to": "forest_2", "spawn": [1, 5] }
  ],
  "spawns": [
    { "monster": "bat",    "max": 3, "respawn": 30 },
    { "monster": "jackal", "max": 2, "respawn": 45 }
  ]
}
```

- Ô không đi qua được: cây, đá, nước, tường.
- Ô tương tác: cổng, cây thuốc, quặng, rương, NPC, bảng tin. (Đã có: cổng, NPC, cây thuốc,
  quặng, giếng, đá dịch chuyển. Chưa có: rương, bảng tin.)
- Hình ảnh: bộ tile Dungeon Crawl Stone Soup (CC0, 32×32) có sẵn cây, đá, nước, cửa, tường,
  cùng phong cách với hình quái đang dùng.
- Sau này có thể đọc file của Tiled Map Editor để vẽ bản đồ trực quan.

### Chạm vào ô

| Chạm vào | Kết quả |
| --- | --- |
| Quái | Vào trận. Thắng: quái biến mất, hồi lại sau N giây. Chạy thoát: đứng yên tại chỗ, quái được nhả ra. Thua: tỉnh dậy ở nhà |
| Trùm | Hỏi xác nhận trước khi đấu (có cảnh báo nếu cấp còn thấp) |
| Đá dịch chuyển | Lần đầu chạm thì ghi nhớ; mở bảng chọn nơi đến (Làng và các đá đã ghi nhớ) |
| Cổng | Chuyển bản đồ |
| NPC | Cửa hàng, hội thoại, nhận nhiệm vụ |
| Cây thuốc, quặng | Thu thập nguyên liệu (cho chế tạo sau này) |
| Rương | Mở mỗi ngày một lần |
| Giếng nước ở nhà | Hồi đầy máu (thay cho giường vì bộ tile không có giường) |
| Người chơi khác | Xem thông tin; sau này mời PvP hoặc giao dịch |

### Kiến trúc server

- **Mỗi bản đồ một tiến trình `MapServer`**: giữ vị trí quái, người chơi đang có mặt, thời gian
  hồi quái. Nhà riêng tạo tiến trình theo người chơi khi cần.
- **Server kiểm tra từng bước đi**: chỉ sang ô kề bên, không xuyên vật cản, tối đa khoảng 6–8
  bước/giây. Chống dịch chuyển tức thời và đi xuyên tường.
- **Client đi trước cho mượt**: di chuyển ngay trên màn hình, server sai thì kéo về đúng chỗ.
- **Thấy người chơi khác**: Phoenix Presence và kênh `map:<id>`.
- **Tranh quái**: người chạm trước khóa con quái; người khác thấy nó đang trong trận.
- **Database**: bảng `characters` thêm `map_id`, `x`, `y`.

### Giao diện điện thoại

- Canvas 2D, ảnh giữ nét pixel (`image-rendering: pixelated`). Camera đi theo nhân vật,
  màn hình điện thoại thấy khoảng 11×15 ô.
- Điều khiển: chạm vào ô muốn đến (tự tìm đường A*), hoặc nút 4 hướng trên màn hình;
  máy tính dùng phím mũi tên hoặc WASD.
- Tab Nhân vật, Túi đồ giữ dạng menu. Màn đánh nhau giữ nguyên, hiện đè lên bản đồ.

### Nối với các tính năng khác

- Nhiệm vụ hằng ngày: "Hạ 10 Chó Rừng ở Rừng Mê 2", "Hái 5 cây thuốc".
- Trùm thế giới xuất hiện ở một ô trên bản đồ.
- Chat hiện bong bóng chữ trên đầu nhân vật.
- PvP ở bản đồ đấu trường. Tháp vô tận: mỗi tầng là một bản đồ sinh ngẫu nhiên.

### Giai đoạn

- [x] **Giai đoạn 1**: định dạng bản đồ; Nhà, Làng và 6 vùng (mỗi vùng 1 bản đồ, trùm đứng trong
  bản đồ); đi lại, qua cổng, chạm quái vào trận. Quái dùng chung, đi lang thang, hồi theo thời
  gian; thấy người chơi khác. Bỏ tab "Săn quái". (Vì bỏ nút săn nhanh nên phải có đủ 6 vùng
  ngay từ đầu; bản đồ chung và thấy người chơi khác gộp luôn vào đây.)
- [x] **Giai đoạn 2**: mỗi vùng tách thành 2 bản đồ quái (bản đồ 2 có quái mạnh hơn) và một
  phòng trùm riêng; di chuyển mượt (nội suy vị trí cho mình, người khác và quái); đá dịch
  chuyển ở Làng và ở bản đồ 2 mỗi vùng (chạm lần đầu để ghi nhớ, đứng cạnh đá nào cũng
  dịch chuyển được tới các đá đã ghi nhớ); hỏi xác nhận trước khi đấu trùm.
- [x] **Giai đoạn 3**: NPC ở Làng (Trưởng Làng giao nhiệm vụ, Thợ Rèn bán vũ khí/giáp/khiên,
  Bà Lang bán thuốc và pha thuốc từ thảo dược, Chủ Quán Trọ cho nghỉ, người dân chỉ đường) thay
  cho tab Cửa hàng; mua/bán/nghỉ phải đứng cạnh NPC. Điểm thu thập dùng chung (Thảo Dược, Linh
  Chi, Quặng Sắt, Quặng Mithril) mọc ngẫu nhiên và mọc lại. 18 nhiệm vụ (mỗi vùng: diệt quái,
  thu thập, hạ trùm), tab Nhiệm vụ theo dõi tiến độ.
- [ ] **Giai đoạn 4**: trang trí nhà, trùm thế giới trên bản đồ.

### Đã quyết định

- **Quái dùng chung**: mọi người trong cùng bản đồ thấy cùng một bầy quái. Người chạm trước
  khóa con quái, người khác thấy nó đang giao chiến. Trùm cũng dùng chung.
- **Bỏ nút "Săn quái nhanh"**: chỉ gặp quái bằng cách đi trên bản đồ; tab "Săn quái" thay bằng "Bản đồ".
- **Quái đi lang thang** chậm, chưa đuổi theo người chơi. Quái không tự bước vào người chơi;
  trận chỉ bắt đầu khi người chơi bước vào ô có quái.

## F. Khác

- [ ] Đóng gói app Android (PWA hoặc Capacitor).
- [ ] CI chạy `mix test` trên GitHub Actions (hiện repo chưa có CI).
