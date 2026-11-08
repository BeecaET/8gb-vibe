# Triển khai trang 8gb.beeca.vn

Trang là site tĩnh: không backend, không cơ sở dữ liệu, không Docker. Bất kỳ máy chủ web nào phục vụ được tệp tĩnh qua HTTPS đều dùng được. Thông tin máy chủ thật (địa chỉ, tài khoản, khoá) không ghi trong repo.

## 1. Cấu trúc trên máy chủ

```
<thư mục web>/
├── index.html, style.css, main.js
├── favicon-32.png, apple-touch-icon.png, robots.txt, sitemap.xml
├── anh/                       ảnh chụp, icon, logo BEECA, og.jpg
└── tai-ve/
    ├── 8GB-Vibe-<phiên bản>.dmg
    └── 8GB-Vibe-<phiên bản>.dmg.sha256
```

Chỉ chép các tệp của trang. Không chép `TRIEN_KHAI.md`, `nginx-8gb.conf`, `cap-nhat-phien-ban.sh`, `tai-ve/.gitignore`.

## 2. Cài lần đầu

1. Trỏ bản ghi DNS của tên miền về máy chủ.
2. Chép trang lên máy chủ, ví dụ bằng rsync qua SSH (dùng khoá, không dùng mật khẩu):

   ```bash
   rsync -av --exclude 'TRIEN_KHAI.md' --exclude '*.conf' --exclude '*.sh' --exclude '.gitignore' --exclude 'tai-ve/' web/ <user>@<máy chủ>:<thư mục web>/
   ```

3. Chép DMG (chỉ bản đã notarize và staple) vào `tai-ve/`.
4. Quyền tệp: thư mục 755, tệp 644.
5. Cấp chứng chỉ HTTPS, ví dụ certbot chế độ webroot:

   ```bash
   certbot certonly --webroot -w <thư mục web> -d 8gb.beeca.vn
   ```

6. Cấu hình nginx theo [nginx-8gb.conf](nginx-8gb.conf) (HTTP chuyển 301 sang HTTPS, header bảo mật, không liệt kê `tai-ve/`), chạy `nginx -t` rồi reload.
7. Đặt hook gia hạn chứng chỉ để reload nginx sau khi certbot gia hạn (ví dụ trong `/etc/letsencrypt/renewal-hooks/deploy/`).

## 3. Kiểm tra sau khi triển khai

```bash
curl -sI https://8gb.beeca.vn/ | head -20
```

```bash
curl -s https://8gb.beeca.vn/tai-ve/8GB-Vibe-<phiên bản>.dmg | shasum -a 256
```

Cần thấy:

- Trang chính 200, có `Strict-Transport-Security`, `Content-Security-Policy`, `Cache-Control: no-cache`.
- DMG 200, `Content-Type: application/x-apple-diskimage`, SHA-256 khớp mã trên trang.
- `http://` chuyển 301 sang `https://`.
- `https://8gb.beeca.vn/tai-ve/` trả 403 hoặc 404.
- Tải DMG bằng Safari trên một máy Mac khác, mở được, Gatekeeper không chặn.

## 4. Khi có bản mới

1. Build và notarize bằng `scripts/release.sh`, ra `build/release/8GB-Vibe-<phiên bản>.dmg`.
2. Cập nhật số phiên bản, ngày, dung lượng, SHA-256 và đường dẫn trong `index.html`. Chạy **sau khi staple**, vì staple làm đổi SHA-256:

   ```bash
   web/cap-nhat-phien-ban.sh build/release/8GB-Vibe-<phiên bản>.dmg
   ```

   Nếu sửa tay, sửa đủ các chỗ có thuộc tính `data-pb` và khối JSON-LD (`softwareVersion`, `downloadUrl`).
3. Chép DMG mới lên `tai-ve/` trước, rồi mới chép `index.html`, để nút tải không trỏ tới tệp chưa có.
4. Giữ bản DMG cũ vài ngày rồi xoá.
5. Cập nhật `lastmod` trong `sitemap.xml` nếu nội dung trang đổi nhiều.

## 5. Bộ nhớ đệm CSS và JS

`index.html` gọi `/style.css?v=...` và `/main.js?v=...`. Khi sửa `style.css` hoặc `main.js`, đổi chuỗi `v=` để trình duyệt tải bản mới ngay.

## 6. Ảnh chụp

- Mỗi ảnh trong `anh/` có bản 800 px và 1600 px (`srcset`).
- Chụp bằng `--window <trang>` và `screencapture -l <window id>`, không chụp toàn màn hình.
- Trước khi đưa lên trang, làm mờ tên dự án, đường dẫn và mọi thông tin riêng trong ảnh.

## 7. Quay lui

- Trang: chép lại bản `web/` của commit trước.
- nginx: đưa tệp vhost về bản trước, `nginx -t`, reload.
