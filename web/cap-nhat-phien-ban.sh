#!/bin/bash
# Cập nhật số phiên bản, ngày, dung lượng, SHA-256 và đường dẫn DMG trong web/index.html.
# Dùng: web/cap-nhat-phien-ban.sh build/release/8GB-Vibe-1.0.1.dmg
# Chạy SAU khi notarize + staple xong (staple làm đổi SHA-256 của tệp).
set -euo pipefail

dmg="${1:?Cần đường dẫn tệp .dmg}"
[ -f "$dmg" ] || { echo "Không thấy tệp: $dmg" >&2; exit 1; }

thu_muc="$(cd "$(dirname "$0")" && pwd)"
html="$thu_muc/index.html"
tep="$(basename "$dmg")"
so="${tep#8GB-Vibe-}"; so="${so%.dmg}"
[[ "$so" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Tên tệp phải dạng 8GB-Vibe-X.Y.Z.dmg" >&2; exit 1; }
sha="$(shasum -a 256 "$dmg" | awk '{print $1}')"
byte="$(stat -f%z "$dmg")"
mb="$(awk -v b="$byte" 'BEGIN{printf "%.1f", b/1000000}' | tr . ,)"
ngay="$(date +%d/%m/%Y)"

export so tep sha mb ngay
perl -0pi -e '
  s{(data-pb="link" href="/tai-ve/)[^"]+(")}{$1$ENV{tep}$2}g;
  s{(<span data-pb="so">)[^<]*(</span>)}{$1$ENV{so}$2}g;
  s{(<span data-pb="ngay">)[^<]*(</span>)}{$1$ENV{ngay}$2}g;
  s{(<span data-pb="dungluong">)[^<]*(</span>)}{$1$ENV{mb} MB$2}g;
  s{(<span data-pb="tep">)[^<]*(</span>)}{$1$ENV{tep}$2}g;
  s{(<code data-pb="sha">)[^<]*(</code>)}{$1$ENV{sha}$2}g;
  s{("softwareVersion":")[^"]*(")}{$1$ENV{so}$2}g;
  s{("fileSize":")[^"]*(")}{$1$ENV{mb} MB$2}g;
  s{("downloadUrl":"https://8gb.beeca.vn/tai-ve/)[^"]*(")}{$1$ENV{tep}$2}g;
' "$html"

echo "Đã cập nhật index.html: $so · $ngay · $mb MB"
echo "SHA-256: $sha"
echo "Nhớ chép $tep lên máy chủ vào thư mục tai-ve/ (xem web/TRIEN_KHAI.md)."
