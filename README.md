# Hắc Long RPG

Game nhập vai chạy trên trình duyệt, tối ưu cho điện thoại. Lấy cảm hứng từ các game RPG web kiểu
menu: đánh quái, lên cấp, mua đồ, hạ trùm từng vùng và cuối cùng tiêu diệt **Hắc Long**.

Bản hiện tại là **bản một người chơi**, dữ liệu lưu trong trình duyệt (localStorage).
Chưa có server, đăng nhập, clan hay PvP.

## Chơi thử

Không cần cài gì. Chạy một web server tĩnh trong thư mục repo rồi mở trình duyệt:

```bash
python3 -m http.server 8000
# mở http://localhost:8000
```

Mở trực tiếp `index.html` bằng cách nhấp đúp cũng chạy được, nhưng font chữ cần mạng.

## Nội dung

- 3 lớp nhân vật: **Chiến Binh**, **Thích Khách**, **Hiệp Sĩ**, mỗi lớp một kỹ năng riêng
- 6 vùng đất, 24 loại quái thường, 6 trùm (hạ trùm để mở vùng tiếp theo)
- Chiến đấu theo lượt: tấn công, kỹ năng (có hồi chiêu), uống máu, bỏ chạy
- Lên cấp nhận 3 điểm tiềm năng để cộng vào Sức mạnh, Thể lực, Nhanh nhẹn, Phòng thủ
- Cửa hàng vũ khí, giáp, khiên, bình máu; 2 món đồ hiếm chỉ rơi từ trùm
- Gục ngã mất 10% vàng và về làng
- Tự động lưu sau mỗi thao tác

Một lượt chơi từ đầu đến khi hạ Hắc Long mất khoảng 430 trận (theo mô phỏng).

## Cấu trúc

```
index.html          Khung trang
css/style.css       Giao diện
js/data.js          Dữ liệu: lớp nhân vật, vùng đất, quái, vật phẩm, cửa hàng
js/engine.js        Logic game thuần (không đụng DOM), chạy được cả trong Node
js/ui.js            Vẽ màn hình và xử lý thao tác
assets/monsters/    Hình quái và nhân vật (PNG 32×32)
assets/icons/       Icon vật phẩm, kỹ năng, menu (SVG)
assets/floors/      Nền cho từng vùng đất
tools/simulate.js   Mô phỏng một người chơi để kiểm tra cân bằng
tools/build.js      Gộp tất cả thành một file HTML duy nhất (dist/hac-long.html)
```

## Chỉnh sửa game

- **Thêm quái / vùng / đồ**: sửa `js/data.js`. Chỉ số quái được tính tự động từ cấp độ
  (`makeMonster` trong `js/engine.js`), dùng `mult` để làm một con mạnh hoặc yếu hơn.
- **Đổi công thức chiến đấu**: `derived`, `makeMonster`, `damage` trong `js/engine.js`.
- Sau khi đổi số, chạy mô phỏng để xem game có quá dễ hay quá khó:

```bash
node tools/simulate.js 10
```

Kết quả in ra số trận trung bình để thắng, số lần chết và cấp độ lúc hạ từng trùm.

## Tạo bản một file

```bash
node tools/build.js
```

Tạo `dist/hac-long.html` với CSS, JS và toàn bộ hình ảnh nhúng sẵn.

## Hướng phát triển tiếp

1. Server (Node.js + PostgreSQL), đăng nhập, lưu nhân vật trên server
2. Chống gian lận: chuyển logic chiến đấu (`engine.js`) sang chạy trên server
3. Chat, clan, PvP, chợ mua bán giữa người chơi
4. Đóng gói app Android (PWA hoặc Capacitor)

## Bản quyền hình ảnh

Hình quái vật từ Dungeon Crawl Stone Soup (CC0) và icon từ game-icons.net (CC BY 3.0).
Chi tiết và ghi tên tác giả xem [CREDITS.md](CREDITS.md).
