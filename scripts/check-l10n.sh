#!/bin/bash
# Checks that every localized key the compiler extracts from Sources/ has a Vietnamese entry in
# Resources/vi.lproj/Localizable.strings, with the same format specifiers. Run from the repo root.
set -euo pipefail
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
swift build -j 2 -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$dir" >/dev/null
python3 -I - "$dir" Resources/vi.lproj/Localizable.strings <<'PY'
import glob, json, plistlib, re, subprocess, sys
folder, strings = sys.argv[1], sys.argv[2]
keys = set()
for f in glob.glob(folder + '/*.stringsdata'):
    for table in json.load(open(f)).get('tables', {}).values():
        keys.update(e['key'] for e in table)
# .strings is an old-style property list; plutil converts it exactly (escapes included).
vi = plistlib.loads(subprocess.run(['plutil', '-convert', 'xml1', '-o', '-', strings], check=True, capture_output=True).stdout)
spec = re.compile(r'%(?:\d+\$)?(lld|llu|ld|lu|d|u|lf|f|@)')
missing = sorted(k for k in keys if k not in vi)
bad = sorted(k for k in keys if k in vi and sorted(spec.findall(k)) != sorted(spec.findall(vi[k])))
for k in missing: print('missing in vi.lproj:', repr(k))
for k in bad: print('specifiers differ:', repr(k), '->', repr(vi[k]))
print(f'{len(keys)} keys, {len(missing)} missing, {len(bad)} with different specifiers')
sys.exit(1 if missing or bad else 0)
PY
