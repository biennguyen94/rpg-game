# Triển khai Hắc Long bằng Docker

Hướng dẫn đưa game lên một VPS bằng Docker Compose. Có 3 cách, chọn theo những gì bạn có:

| Cách | Khi nào dùng | Người chơi vào bằng |
|---|---|---|
| [1. Chỉ có IP](#cách-1-chỉ-có-ip-chưa-có-domain) | Chạy thử, chưa mua domain | `http://203.0.113.10:4000` |
| [2. Domain + Caddy](#cách-2-có-domain-caddy-làm-tls-proxy-khuyên-dùng) (khuyên dùng) | Có domain, muốn HTTPS tự động | `https://game.example.com` |
| [3. Domain + nginx](#cách-3-có-domain-nginx-cài-trên-vps-làm-tls-proxy) | VPS đã có nginx chạy web khác | `https://game.example.com` |

Có dùng thêm Cloudflare (đám mây cam) thì đọc thêm [mục Cloudflare](#thêm-cloudflare-đứng-trước).

Trong tài liệu này `203.0.113.10` là IP ví dụ của VPS, `game.example.com` là domain ví dụ;
thay bằng IP và domain của bạn.

## Tổng quan

```
Người chơi ──(https / wss)──> TLS proxy ──(http / ws)──> app:4000 ──> db:5432
                              Caddy, nginx               game          PostgreSQL 16
                              hoặc Cloudflare            (release)     (volume "db")
```

- **app**: bản release của game, build bằng `Dockerfile`. Lúc khởi động tự chạy migration
  (`rel/overlays/bin/start`) rồi bật server ở cổng 4000. Giao diện (HTML, JS, hình) nằm sẵn
  trong release, không cần build riêng.
- **db**: PostgreSQL 16, dữ liệu trong volume `db`. Cổng database không mở ra ngoài.
- **TLS proxy** (cách 2, 3): nhận HTTPS từ người chơi, chuyển tiếp vào `app:4000`. Game dùng
  WebSocket (`/socket`), proxy phải chuyển tiếp được WebSocket (Caddy tự làm; nginx cần cấu
  hình, đã có sẵn trong `deploy/nginx.conf`).
- Một số thứ chỉ giữ trong bộ nhớ: tổ đội, giao dịch đang dở, trùm thế giới đang đánh, chat
  gần đây. Khởi động lại container thì chúng mất; nhân vật, đồ, vàng... nằm trong database nên
  không mất. Người chơi đang online tự kết nối lại.

Các file liên quan:

| File | Dùng làm gì |
|---|---|
| `Dockerfile` | Build bản release (Elixir 1.17, OTP 25, Debian bookworm) |
| `docker-compose.yml` | Chạy `app` + `db` |
| `docker-compose.caddy.yml` | Thêm Caddy làm TLS proxy (cách 2) |
| `deploy/Caddyfile` | Cấu hình Caddy |
| `deploy/nginx.conf` | Mẫu cấu hình nginx (cách 3) |
| `.env.example` | Mẫu file cấu hình `.env` |
| `rel/overlays/bin/start` | Chạy migration rồi bật server trong container |
| `lib/hac_long/release.ex` | Migration và cấp quyền quản trị khi không có `mix` |

## Chuẩn bị VPS

- Ubuntu 22.04/24.04 hoặc Debian 12, 1 vCPU, 1 GB RAM là chạy được. **Lần build đầu cần khoảng
  2 GB RAM**; VPS 1 GB thì thêm swap trước khi build:

  ```bash
  sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
  sudo mkswap /swapfile && sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  ```

- Cài Docker Engine và Docker Compose (bản 2.24 trở lên; `docker compose version` để xem):

  ```bash
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker $USER   # đăng xuất rồi đăng nhập lại để dùng docker không cần sudo
  ```

- Lấy code và tạo file `.env`:

  ```bash
  git clone https://github.com/biennguyen94/rpg-game.git hac-long
  cd hac-long
  cp .env.example .env && chmod 600 .env
  ```

- Tạo hai giá trị bí mật rồi dán vào `.env` (`POSTGRES_PASSWORD`, `SECRET_KEY_BASE`):

  ```bash
  openssl rand -hex 24      # → POSTGRES_PASSWORD
  openssl rand -base64 48   # → SECRET_KEY_BASE
  ```

  Giữ hai giá trị này bí mật và **không đổi sau khi đã chạy**. Đổi `POSTGRES_PASSWORD` sau
  khi database đã tạo thì app không đăng nhập vào database được nữa (Postgres chỉ dùng biến
  này lúc tạo database lần đầu).

## Các biến trong `.env`

| Biến | Bắt buộc | Ý nghĩa |
|---|---|---|
| `POSTGRES_PASSWORD` | có | Mật khẩu database |
| `SECRET_KEY_BASE` | có | Khóa bí mật của server (64 ký tự trở lên) |
| `PHX_HOST` | có | **IP hoặc domain người chơi gõ vào trình duyệt**, không có `http://`, không có cổng |
| `PHX_SCHEME` | | `http` (chỉ có IP) hoặc `https` (có TLS proxy). Mặc định `https` |
| `PHX_URL_PORT` | | Cổng trong địa chỉ người chơi dùng: `4000` (cách 1), `443` (có TLS). Mặc định 443 với https, 80 với http |
| `APP_PORT` | | Cổng mở ra ngoài của game (cách 1, 3). Mặc định `4000` |
| `APP_BIND` | | `127.0.0.1` để chỉ proxy trên cùng VPS vào được game (cách 3). Mặc định mở cho mọi nơi |
| `TRUSTED_PROXIES` | khi có proxy | IP/dải IP của proxy, cách nhau bởi dấu phẩy. Xem [IP thật của người chơi](#ip-thật-của-người-chơi-trusted_proxies) |
| `CADDY_TRUSTED_PROXIES` | | Dải IP của proxy đứng trước Caddy (Cloudflare), cách nhau bởi dấu cách |
| `CHECK_ORIGIN` | | Danh sách địa chỉ trang game được phép mở kết nối game, khi vào bằng nhiều địa chỉ |
| `COMPOSE_FILE` | | `docker-compose.yml:docker-compose.caddy.yml` để lệnh `docker compose` tự dùng cả Caddy (cách 2) |
| `PHX_IPV6` | | `true` để game nghe cả IPv6 (chỉ khi Docker đã bật IPv6) |

Biến thử nghiệm, không cần cho server thật: `EVENT` (bật một lễ hội bất kỳ, vd.
`mid_autumn`, hay `none` để tắt), `TIME_OF_DAY` (`dawn`, `day`, `dusk`, `night`),
`WORLD_BOSS_FIRST_MINUTES`, `WORLD_BOSS_EVERY_MINUTES`, `WORLD_BOSS_DURATION_MINUTES`,
`WORLD_BOSS_HP`. Muốn dùng thì thêm vào mục `environment` của `app` trong `docker-compose.yml`.

### Vì sao `PHX_HOST` phải đúng

Trình duyệt mở kết nối game (WebSocket `/socket`) kèm địa chỉ trang đang mở. Server chỉ nhận
kết nối khi host của trang **trùng `PHX_HOST`**, để trang web khác không mượn được phiên đăng
nhập của người chơi.

Ví dụ `PHX_HOST=203.0.113.10` nhưng người chơi vào bằng `http://game.example.com:4000`: trang
vẫn hiện, đăng nhập vẫn được, nhưng vào game thì báo **"Mất kết nối, đang kết nối lại"** mãi.
Log của app có dòng `Could not check origin for Phoenix.Socket transport`.

Muốn vào được bằng nhiều địa chỉ cùng lúc (vd. lúc chuyển từ IP sang domain), liệt kê đủ ở
`CHECK_ORIGIN`, mỗi địa chỉ gồm cả `http(s)://` và cổng nếu có:

```bash
CHECK_ORIGIN=https://game.example.com,http://203.0.113.10:4000
```

## Cách 1: chỉ có IP, chưa có domain

Sửa `.env`:

```bash
PHX_HOST=203.0.113.10      # IP của VPS
PHX_SCHEME=http
PHX_URL_PORT=4000
```

Chạy:

```bash
docker compose up -d --build
docker compose logs -f app   # đợi dòng "Running HacLongWeb.Endpoint ... at 0.0.0.0:4000"
```

Mở `http://203.0.113.10:4000`. Cổng 4000 phải mở ở tường lửa của nhà cung cấp VPS (security
group, firewall trên trang quản lý).

Lưu ý:
- **Không mã hóa**: mật khẩu và mọi thứ gửi dạng rõ trên mạng. Chỉ nên dùng để chạy thử; có
  người chơi thật thì chuyển sang cách 2.
- Muốn bỏ `:4000` trong địa chỉ: đặt `APP_PORT=80` và `PHX_URL_PORT=80`, rồi vào
  `http://203.0.113.10`.
- **Docker mở cổng đi vòng qua `ufw`**: cổng đã khai báo trong `ports:` luôn mở ra Internet
  dù `ufw` đang chặn. Muốn chặn thì dùng tường lửa của nhà cung cấp VPS hoặc `APP_BIND`.

## Cách 2: có domain, Caddy làm TLS proxy (khuyên dùng)

Caddy chạy trong Docker cùng game. Nó tự xin chứng chỉ Let's Encrypt, tự gia hạn, tự chuyển
`http` sang `https`, và chuyển tiếp WebSocket. Game không mở cổng 4000 ra ngoài nữa, chỉ
Caddy vào được.

1. **Trỏ domain về VPS**: ở nơi quản lý DNS, tạo bản ghi `A` cho `game.example.com` trỏ về
   `203.0.113.10` (thêm `AAAA` nếu VPS có IPv6). Kiểm tra: `ping game.example.com` ra đúng IP.
   Nếu dùng Cloudflare, lúc đầu để **đám mây xám** (DNS only); xem mục Cloudflare sau.
2. **Mở cổng 80 và 443** ở tường lửa của nhà cung cấp VPS. Cổng 80 cần cho Let's Encrypt kiểm
   tra domain, và để chuyển người vào bằng http sang https.
3. **Sửa `.env`**:

   ```bash
   COMPOSE_FILE=docker-compose.yml:docker-compose.caddy.yml
   PHX_HOST=game.example.com
   PHX_SCHEME=https
   PHX_URL_PORT=443
   TRUSTED_PROXIES=172.16.0.0/12
   ```

   `COMPOSE_FILE` giúp các lệnh `docker compose ...` sau đó tự dùng cả hai file. Không đặt thì
   lệnh nào cũng phải thêm `-f docker-compose.yml -f docker-compose.caddy.yml`.
   `TRUSTED_PROXIES=172.16.0.0/12` là dải mạng nội bộ Docker, nơi Caddy chạy
   ([vì sao cần](#ip-thật-của-người-chơi-trusted_proxies)).
4. **Chạy**:

   ```bash
   docker compose up -d --build
   docker compose logs -f caddy   # đợi "certificate obtained successfully"
   ```

5. Mở `https://game.example.com`.

Đang chạy cách 1 rồi thì chỉ cần sửa `.env` như bước 3 (bỏ các dòng của cách 1) rồi chạy lại
`docker compose up -d`. Dữ liệu trong database giữ nguyên.

## Cách 3: có domain, nginx cài trên VPS làm TLS proxy

Dùng khi VPS đã có nginx phục vụ trang web khác trên cổng 80/443.

1. Trỏ domain về VPS như cách 2, bước 1.
2. Sửa `.env`:

   ```bash
   PHX_HOST=game.example.com
   PHX_SCHEME=https
   PHX_URL_PORT=443
   APP_BIND=127.0.0.1
   TRUSTED_PROXIES=127.0.0.1,172.16.0.0/12
   ```

   `APP_BIND=127.0.0.1` để cổng 4000 chỉ mở cho nginx trên chính VPS. Kết nối từ nginx đi qua
   Docker nên game thấy IP của cổng mạng Docker (thuộc `172.16.0.0/12`), vì vậy
   `TRUSTED_PROXIES` có cả dải đó.
3. Chạy game: `docker compose up -d --build`.
4. Lấy chứng chỉ trước (cấu hình mẫu trỏ tới file chứng chỉ; chưa có file thì nginx không
   nạp được cấu hình). Certbot tự tạm cấu hình nginx để Let's Encrypt kiểm tra domain, và tự
   gia hạn về sau:

   ```bash
   sudo apt install certbot python3-certbot-nginx
   sudo certbot certonly --nginx -d game.example.com
   ```

5. Bật cấu hình nginx từ mẫu `deploy/nginx.conf` (thay `game.example.com`):

   ```bash
   sudo cp deploy/nginx.conf /etc/nginx/sites-available/hac-long
   sudo sed -i 's/game.example.com/tên-miền-của-bạn/g' /etc/nginx/sites-available/hac-long
   sudo ln -s /etc/nginx/sites-available/hac-long /etc/nginx/sites-enabled/
   sudo nginx -t && sudo systemctl reload nginx
   ```

Những dòng không được bỏ trong cấu hình nginx:
- `proxy_http_version 1.1`, `Upgrade`, `Connection`: thiếu thì WebSocket không nối được, vào
  game báo mất kết nối.
- `proxy_read_timeout 3600s`: kết nối game mở lâu; mặc định 60 giây thì người chơi bị ngắt
  liên tục.
- `X-Forwarded-For`: để game biết IP thật của người chơi.

## Thêm Cloudflare đứng trước

Nếu bật **đám mây cam** (proxied) ở Cloudflare, người chơi nối tới Cloudflare, Cloudflare nối
tới Caddy/nginx trên VPS:

```
Người chơi ──> Cloudflare ──> Caddy (hoặc nginx) ──> app:4000
```

1. Chạy cách 2 (hoặc 3) với đám mây xám cho tới khi `https://game.example.com` chạy được.
2. Ở Cloudflare: **SSL/TLS → Overview → Full (strict)**. Chế độ "Flexible" sẽ gây vòng chuyển
   hướng vô tận vì Caddy chuyển http sang https. WebSocket được Cloudflare hỗ trợ sẵn.
3. Bật đám mây cam cho bản ghi `game.example.com`.
4. Khai báo dải IP của Cloudflare là proxy tin cậy, nếu không thì game thấy mọi người chơi
   có IP của Cloudflare (xem mục sau). Chạy trên VPS để lấy danh sách mới nhất:

   ```bash
   CF=$( (curl -s https://www.cloudflare.com/ips-v4; echo; curl -s https://www.cloudflare.com/ips-v6) | grep -v '^$')
   echo "CADDY_TRUSTED_PROXIES=$(echo $CF)"
   echo "TRUSTED_PROXIES=172.16.0.0/12,$(echo $CF | tr ' ' ',')"
   ```

   Dán hai dòng in ra vào `.env` (thay dòng `TRUSTED_PROXIES` cũ) rồi `docker compose up -d`.
   Cloudflare thỉnh thoảng thêm dải IP mới; nên chạy lại lệnh trên vài tháng một lần.

   Dùng nginx (cách 3) thay vì Caddy thì thêm các dải đó vào `TRUSTED_PROXIES` như trên, và
   trong nginx thêm `set_real_ip_from <dải>;` cho từng dải cùng `real_ip_header X-Forwarded-For;`
   để nginx giữ IP thật.

Chứng chỉ: Caddy vẫn tự xin được chứng chỉ Let's Encrypt khi đã bật đám mây cam. Nếu gặp lỗi
xin chứng chỉ, tạm tắt đám mây cam, đợi Caddy lấy xong rồi bật lại. Hoặc dùng Cloudflare
Origin Certificate (SSL/TLS → Origin Server) với nginx.

## IP thật của người chơi (`TRUSTED_PROXIES`)

Game giới hạn theo IP: mỗi IP đăng ký tối đa 5 tài khoản mỗi giờ và đăng nhập tối đa 30 lần
mỗi 5 phút. Khi có proxy (Caddy, nginx, Cloudflare), kết nối tới game đến từ proxy. Proxy ghi IP
thật vào header `X-Forwarded-For`, nhưng header này ai cũng tự ghi được. Vì vậy game chỉ đọc
header khi kết nối đến từ một địa chỉ trong `TRUSTED_PROXIES`.

- **Quên đặt `TRUSTED_PROXIES`** khi có proxy: game coi mọi người chơi là một IP (IP của
  proxy). Cả server chỉ đăng ký được 5 tài khoản mỗi giờ và đăng nhập 30 lần mỗi 5 phút; người
  sau bị báo thao tác quá nhiều, dù là người khác nhau.
- **Đặt quá rộng** (vd. `0.0.0.0/0`) khi không có proxy: người chơi tự ghi header giả IP để
  lách giới hạn.
- **Chỉ có IP, không proxy** (cách 1): để trống `TRUSTED_PROXIES`.

| Cách | `TRUSTED_PROXIES` |
|---|---|
| 1. Chỉ có IP | để trống |
| 2. Caddy trong Docker | `172.16.0.0/12` |
| 3. nginx trên VPS | `127.0.0.1,172.16.0.0/12` |
| Thêm Cloudflare | thêm các dải IP của Cloudflare (mục trên) |

`172.16.0.0/12` gồm mọi mạng nội bộ Docker tạo mặc định (`172.17.x.x`, `172.18.x.x`...).
Xem đúng mạng của compose: `docker network inspect hac-long_default | grep Subnet` (tên mạng
là tên thư mục + `_default`).

## Vận hành

Các lệnh chạy trong thư mục code trên VPS.

```bash
docker compose ps                    # trạng thái các container
docker compose logs -f app           # log game (Ctrl+C để thoát)
docker compose restart app           # khởi động lại game
docker compose down                  # dừng tất cả (dữ liệu vẫn còn)
```

**Cập nhật phiên bản mới**: migration tự chạy lúc app khởi động.

```bash
git pull
docker compose up -d --build
```

**Cấp quyền quản trị** (tab Quản trị hiện sau khi người đó tải lại trang):

```bash
docker compose exec app bin/hac_long eval 'HacLong.Release.admin("ten_dang_nhap")'
docker compose exec app bin/hac_long eval 'HacLong.Release.admin("ten_dang_nhap", false)'  # thu hồi
```

**Sao lưu database**. Nên chạy hằng ngày bằng cron và chép file ra ngoài VPS:

```bash
docker compose exec -T db pg_dump -U hac_long -d hac_long -Fc > backup-$(date +%F).dump
```

**Khôi phục** từ bản sao lưu (ghi đè dữ liệu hiện tại):

```bash
docker compose stop app
docker compose exec -T db pg_restore -U hac_long -d hac_long --clean --if-exists < backup-2026-10-01.dump
docker compose start app
```

**Vào console của server đang chạy** (cho người biết Elixir):
`docker compose exec app bin/hac_long remote`.

## Sự cố thường gặp

| Hiện tượng | Nguyên nhân | Cách sửa |
|---|---|---|
| Đăng nhập được nhưng vào game báo "Mất kết nối, đang kết nối lại" mãi; log app có `Could not check origin` | Địa chỉ trên trình duyệt khác `PHX_HOST` | Sửa `PHX_HOST` cho đúng, hoặc thêm địa chỉ vào `CHECK_ORIGIN`; rồi `docker compose up -d` |
| Như trên nhưng log không có `check origin` (qua nginx) | nginx chưa chuyển tiếp WebSocket | Thêm `proxy_http_version 1.1` và các header `Upgrade`, `Connection` như `deploy/nginx.conf` |
| Bị ngắt kết nối đều đặn mỗi phút (qua nginx) | Timeout mặc định 60 giây | `proxy_read_timeout 3600s;` |
| Người chơi mới đăng ký hoặc đăng nhập bị báo quá nhiều lần | Thiếu `TRUSTED_PROXIES` khi có proxy | Xem mục [IP thật của người chơi](#ip-thật-của-người-chơi-trusted_proxies) |
| `docker compose up` báo `required variable ... is missing` (vd. "đặt SECRET_KEY_BASE trong .env") | Thiếu biến trong `.env`, hoặc chạy lệnh ở thư mục khác | Điền `.env`, chạy lệnh trong thư mục code |
| App khởi động lại liên tục, log có `password authentication failed` | Đổi `POSTGRES_PASSWORD` sau khi database đã tạo | Đặt lại mật khẩu cũ; hoặc đổi mật khẩu trong Postgres: `docker compose exec db psql -U hac_long -c "ALTER USER hac_long PASSWORD 'mới'"` |
| App tắt ngay, log có `:eafnosupport` | Đặt `PHX_IPV6=true` nhưng Docker không có IPv6 | Bỏ `PHX_IPV6` |
| Caddy không lấy được chứng chỉ | Domain chưa trỏ đúng IP, cổng 80 bị chặn, hoặc Cloudflare đang bật | Kiểm tra DNS, mở cổng 80/443, tạm tắt đám mây cam |
| Cloudflare báo lỗi 521/522 | Cổng 443 trên VPS chưa mở, hoặc Caddy chưa chạy | `docker compose ps`, mở cổng 443 |
| Cloudflare: trang chuyển hướng vô tận | Chế độ SSL "Flexible" | Đổi sang "Full (strict)" |
| Build bị dừng giữa chừng, `Killed` | Hết RAM lúc biên dịch | Thêm swap (mục Chuẩn bị VPS) |
| Trang mở được bằng IP:4000 dù đã có Caddy | Chưa dùng `docker-compose.caddy.yml` | Đặt `COMPOSE_FILE` trong `.env` như cách 2, chạy lại `docker compose up -d` |

## Kiểm tra sau khi triển khai

- [ ] Mở trang bằng đúng địa chỉ `PHX_HOST`, đăng ký, tạo nhân vật, đi lại trên bản đồ được.
- [ ] Có TLS: `http://` tự chuyển sang `https://`; trình duyệt hiện ổ khóa.
- [ ] Có proxy: cổng 4000 **không** vào được từ bên ngoài (`curl http://203.0.113.10:4000` từ
      máy khác phải lỗi).
- [ ] Cổng 5432 (database) không mở ra ngoài.
- [ ] `docker compose restart app` xong người chơi tự vào lại được, nhân vật còn nguyên.
- [ ] Đã thử sao lưu một lần và có lịch sao lưu tự động.
- [ ] Đã cấp quyền quản trị cho tài khoản của mình.
