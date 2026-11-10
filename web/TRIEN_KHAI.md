# Deploying 8gb.beeca.vn

The website is a static site: no backend, no database, no Docker. Any web server that serves static files over HTTPS will do. Real server details (address, accounts, keys) are not kept in this repository.

The file name `TRIEN_KHAI.md` ("deployment" in Vietnamese) and the folder names `anh/` (images) and `tai-ve/` (downloads) are kept because the live site and download links use them.

## 1. Layout on the server

```
<web root>/
├── index.html, style.css, main.js
├── en/index.html              English page
├── favicon-32.png, apple-touch-icon.png, robots.txt, sitemap.xml
├── anh/                       screenshots, icon, BEECA logo, og.jpg
└── tai-ve/
    ├── 8GB-Vibe-<version>.dmg
    └── 8GB-Vibe-<version>.dmg.sha256
```

Copy only the site files. Do not copy `TRIEN_KHAI.md`, `nginx-8gb.conf`, the `.sh` scripts or `tai-ve/.gitignore`.

## 2. First setup

1. Point the domain's DNS record at the server.
2. Copy the site to the server, for example with rsync over SSH (key only, no password):

   ```bash
   rsync -av --exclude 'TRIEN_KHAI.md' --exclude '*.conf' --exclude '*.sh' --exclude '.gitignore' --exclude 'tai-ve/' web/ <user>@<server>:<web root>/
   ```

3. Copy the DMG (notarized and stapled builds only) into `tai-ve/`.
4. Permissions: folders 755, files 644.
5. Get an HTTPS certificate, for example with certbot in webroot mode:

   ```bash
   certbot certonly --webroot -w <web root> -d 8gb.beeca.vn
   ```

6. Configure nginx from [nginx-8gb.conf](nginx-8gb.conf) (HTTP redirects 301 to HTTPS, security headers, no listing of `tai-ve/`), run `nginx -t`, then reload.
7. Add a renewal hook so nginx reloads after certbot renews the certificate (for example in `/etc/letsencrypt/renewal-hooks/deploy/`).

## 3. Checks after deploying

```bash
curl -sI https://8gb.beeca.vn/ | head -20
```

```bash
curl -s https://8gb.beeca.vn/tai-ve/8GB-Vibe-<version>.dmg | shasum -a 256
```

Expect:

- The home page and `/en/` return 200 with `Strict-Transport-Security`, `Content-Security-Policy` and `Cache-Control: no-cache`.
- The DMG returns 200 with `Content-Type: application/x-apple-diskimage`, and its SHA-256 matches the one on the page.
- `http://` redirects 301 to `https://`.
- `https://8gb.beeca.vn/tai-ve/` returns 403 or 404.
- The DMG downloads in Safari on another Mac, opens, and Gatekeeper does not block it.

## 4. Releasing a new version

1. Build and notarize with `scripts/release.sh`. Output: `build/release/8GB-Vibe-<version>.dmg`.
2. Update the version, date, size, SHA-256 and link on both pages (`index.html` and `en/index.html`). Run it **after stapling**, because stapling changes the SHA-256:

   ```bash
   web/update-version.sh build/release/8GB-Vibe-<version>.dmg
   ```

   `web/cap-nhat-phien-ban.sh` is the old name of the same script. If you edit by hand, change every element with a `data-pb` attribute and the JSON-LD block (`softwareVersion`, `downloadUrl`). Release notes are written by hand on both pages.
3. Copy the new DMG to `tai-ve/` first, then the pages, so the download button never points to a missing file.
4. Keep the previous DMG for a few days, then delete it.
5. Update `lastmod` in `sitemap.xml` when the content changes a lot.

## 5. CSS and JS caching

`index.html` loads `/style.css?v=...` and `/main.js?v=...`. When you change `style.css` or `main.js`, change the `v=` value so browsers fetch the new file at once. Images in `anh/` are cached for one day: when you replace an image under the same name, change its `?v=` too, including `og:image`.

## 6. Screenshots

- Each image in `anh/` has an 800 px and a 1600 px version (`srcset`). English screenshots use `-en-` in the name.
- Capture with `--window <page>` and `screencapture -l <window id>`, not the whole screen.
- Before publishing, blur project names, paths and anything private in the image.

## 7. Rolling back

- Site: copy back the `web/` folder from the previous commit.
- nginx: restore the previous vhost file, run `nginx -t`, reload.
