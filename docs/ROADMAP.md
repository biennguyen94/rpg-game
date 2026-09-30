# Lộ trình phát triển

Các tính năng của Hắc Long RPG: đã làm gì, còn lại gì. Đánh dấu `[x]` khi làm xong.
Chi tiết kỹ thuật của từng phần nằm trong `README.md` và tài liệu đầu mỗi module.

## Còn lại (theo thứ tự đề xuất)

Ước lượng công sức: nhỏ (vài giờ), vừa (khoảng một ngày), lớn (nhiều ngày).

1. **CI chạy `mix test` trên GitHub Actions** (nhỏ). Repo chưa có kiểm tra tự động nào.
2. **Hướng dẫn người mới** (nhỏ): không có nó, người mới vào không biết làm gì và bỏ đi.
3. **Công cụ quản trị** (vừa) và **chặn/báo cáo người chat xấu** (nhỏ–vừa): cần có trước khi
   mở game cho người lạ.
4. **Mô phỏng cân bằng có nhiệm vụ** (vừa): cho bot làm nhiệm vụ, việc hằng ngày, tháp, trùm
   thế giới để đo các nguồn thưởng mới trước khi thêm tính năng cho thêm thưởng.
5. **Đọc `X-Forwarded-For` khi chạy sau proxy** (nhỏ). Không có thì giới hạn đăng nhập theo IP
   tính chung mọi người thành IP của proxy.
6. **Hộp thư** (vừa): báo thưởng nhận lúc vắng mặt; nền cho chợ và quà quản trị.
7. **Âm thanh** (nhỏ), **câu cá** (nhỏ–vừa), **danh hiệu và thành tựu** (nhỏ–vừa): rẻ mà làm
   game vui hơn hẳn.
8. **Đồ có chỉ số ngẫu nhiên** (vừa), **công dụng cho quặng** (nhỏ–vừa, Thợ Rèn nâng cấp đồ
   bằng quặng) và **thêm kỹ năng theo cấp** (vừa): trận đánh hiện gần như chỉ là bấm kỹ năng
   rồi tấn công, và đồ đạc chỉ là mua món tốt hơn.
9. **Hiệu ứng trạng thái** (vừa), **chuyển sinh** (nhỏ–vừa), **sổ tay quái vật** (nhỏ),
   **ngày và đêm** (nhỏ).
10. **Bang hội** (lớn), **tổ đội** (vừa–lớn): giữ người chơi lâu dài.
11. **Rương** (nhỏ), **trang trí nhà** (vừa–lớn), **nhân vật mặc đúng đồ** (vừa),
    **thú cưng** (vừa).
12. **Chạm vào người chơi khác** (nhỏ, lối vào cho hai việc sau), **PvP bất đồng bộ** (vừa),
    **chợ giữa người chơi** (lớn).
13. **Đóng gói app Android** (PWA: nhỏ, Capacitor: vừa).

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
- [ ] **Hướng dẫn người mới**: chuỗi việc tân thủ ngắn ("Ra khỏi nhà" → "Gặp Trưởng Làng" →
  "Hạ 3 Dơi Hang"), mũi tên chỉ đường trên bản đồ. Hiện nhân vật mới đứng ở Nhà mà không biết
  chạm vào quái để đánh hay gặp NPC để nhận việc.
- [ ] **Công cụ quản trị**: trang chỉ tài khoản admin vào được: khóa tài khoản, cấm chat có
  thời hạn, xem và xử lý báo cáo, gọi trùm thế giới, gửi thông báo cho cả server, gửi quà
  (qua hộp thư). Hiện muốn làm những việc này phải sửa thẳng database.

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
- [ ] **Danh hiệu và thành tựu**: vd. "Diệt 1.000 quái", "Leo tháp tầng 30", "Top 3 trùm thế
  giới", "Hạ Hắc Long". Mỗi thành tựu cho một danh hiệu hiện cạnh tên trong chat và bảng xếp
  hạng. Dữ liệu để đếm phần lớn đã có (kills, bosses, tower_best...).
- [ ] **Sổ tay quái vật**: ghi số con đã hạ của từng loài; hạ đủ mốc (vd. 100 con) thì được
  thưởng nhỏ, vd. +1% sát thương lên loài đó. Cho lý do quay lại các vùng thấp.

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
- [ ] **Hộp thư**: thư hệ thống kèm quà (vàng, đồ). Dùng để báo thưởng trùm thế giới nhận lúc
  vắng mặt (hiện vẫn nhận nhưng không có gì báo), nhận tiền khi bán được đồ ở chợ, quà quản trị.
- [ ] **Bang hội**: lập/vào bang, kênh chat riêng của bang, quỹ bang, bảng xếp hạng bang (vd.
  tổng sát thương lên trùm thế giới). Có trong kế hoạch ban đầu ("chat, clan, PvP") nhưng bị
  sót khi viết lộ trình này.
- [ ] **Tổ đội**: mời người khác vào nhóm, đánh chung một trận với một con quái, chia kinh
  nghiệm; việc hằng ngày và nhiệm vụ tính cho cả nhóm. Hiện ngoài trùm thế giới thì ai cũng
  đánh một mình.
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
- [ ] **Câu cá** ở hồ giữa Làng (hiện chỉ để trang trí): trò chơi nhỏ bấm đúng lúc phao chìm,
  câu được cá để bán, thỉnh thoảng vớt được đồ hiếm. Việc nhẹ nhàng để làm lúc chờ trùm thế giới
  hay ngồi chat.
- [ ] **Ngày và đêm**: bản đồ tối dần theo giờ thật (giờ Việt Nam); ban đêm có quái hiếm xuất
  hiện, rơi nhiều đồ hơn.

## F. Hình ảnh và âm thanh

- [ ] **Âm thanh**: tiếng đánh, chí mạng, lên cấp, nhận thưởng, bước chân, nhạc nền nhẹ; có nút
  tắt. Dùng các bộ âm thanh CC0. Hiện game hoàn toàn im lặng.
- [ ] **Nhân vật mặc đúng đồ đang trang bị**: ghép hình áo giáp, vũ khí, khiên lên hình nhân
  vật (bộ tile Dungeon Crawl có sẵn các phần này ở `player/`, phải đối chiếu danh sách chưa rõ
  giấy phép như các hình khác). Hiện ai cũng cùng một hình.
- [ ] **Thú cưng**: thuần phục quái đã hạ nhiều lần, cho đi theo sau nhân vật trên bản đồ, có
  thể hỗ trợ đánh.

## G. Khác

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
