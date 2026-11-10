#!/bin/bash
# Updates the version, date, size, SHA-256 and DMG link in web/index.html and web/en/index.html.
# Usage: web/update-version.sh build/release/8GB-Vibe-1.0.1.dmg
# Run it AFTER notarizing and stapling (stapling changes the file's SHA-256).
# web/cap-nhat-phien-ban.sh is the old name and still works (it calls this script).
set -euo pipefail

dmg="${1:?Usage: web/update-version.sh <path to .dmg>}"
[ -f "$dmg" ] || { echo "File not found: $dmg" >&2; exit 1; }

web_dir="$(cd "$(dirname "$0")" && pwd)"
file="$(basename "$dmg")"
version="${file#8GB-Vibe-}"; version="${version%.dmg}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "File name must look like 8GB-Vibe-X.Y.Z.dmg" >&2; exit 1; }
sha="$(shasum -a 256 "$dmg" | awk '{print $1}')"
bytes="$(stat -f%z "$dmg")"
mb_en="$(awk -v b="$bytes" 'BEGIN{printf "%.1f", b/1000000}')"

# Each page has its own number and date style: Vietnamese "7,2 MB", "09/11/2026"; English "7.2 MB", "9 November 2026".
update_page() {
  local html="$1" mb="$2" date_text="$3"
  [ -f "$html" ] || { echo "Not found: $html" >&2; exit 1; }
  export version file sha mb date_text
  perl -0pi -e '
    s{(data-pb="link" href="/tai-ve/)[^"]+(")}{$1$ENV{file}$2}g;
    s{(<span data-pb="so">)[^<]*(</span>)}{$1$ENV{version}$2}g;
    s{(<span data-pb="ngay">)[^<]*(</span>)}{$1$ENV{date_text}$2}g;
    s{(<span data-pb="dungluong">)[^<]*(</span>)}{$1$ENV{mb} MB$2}g;
    s{(<span data-pb="tep">)[^<]*(</span>)}{$1$ENV{file}$2}g;
    s{(<code data-pb="sha">)[^<]*(</code>)}{$1$ENV{sha}$2}g;
    s{("softwareVersion":")[^"]*(")}{$1$ENV{version}$2}g;
    s{("fileSize":")[^"]*(")}{$1$ENV{mb} MB$2}g;
    s{("downloadUrl":"https://8gb.beeca.vn/tai-ve/)[^"]*(")}{$1$ENV{file}$2}g;
  ' "$html"
  echo "Updated ${html#$web_dir/}: $version · $date_text · $mb MB"
}
update_page "$web_dir/index.html" "$(echo "$mb_en" | tr . ,)" "$(date +%d/%m/%Y)"
update_page "$web_dir/en/index.html" "$mb_en" "$(LC_ALL=C date '+%-d %B %Y')"
echo "Release notes are written by hand on both pages (Có gì mới / What's new)."
echo "SHA-256: $sha"
echo "Remember to copy $file to the server's tai-ve/ folder (see web/TRIEN_KHAI.md)."
