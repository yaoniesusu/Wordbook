#!/usr/bin/env bash
# 用一张方形 PNG 生成 macOS AppIcon.icns（/usr/bin/sips、/usr/bin/iconutil）
# 注意：中间文件不可放在 .iconset 内，否则 iconutil 会失败。
set -euo pipefail

SRC="${1:?用法: $0 源图.png [输出AppIcon.icns路径]}"
OUT_ICNS="${2:-"$(cd "$(dirname "$0")" && pwd)/AppIcon.icns"}"
ICONSET="${OUT_ICNS%.icns}.iconset"
BASE="${TMPDIR:-/tmp}/wordbook-icon-base-$$.png"
trap '/bin/rm -f "$BASE"' EXIT

if [[ ! -f "$SRC" ]]; then
	echo "源图不存在: $SRC" >&2
	exit 1
fi

echo "==> 生成 AppIcon（iconset）…"
rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"
/usr/bin/sips -s format png -Z 1024 "$SRC" --out "$BASE" >/dev/null

/usr/bin/sips -s format png -z 16 16     "$BASE" --out "${ICONSET}/icon_16x16.png"       >/dev/null
/usr/bin/sips -s format png -z 32 32     "$BASE" --out "${ICONSET}/icon_16x16@2x.png"    >/dev/null
/usr/bin/sips -s format png -z 32 32     "$BASE" --out "${ICONSET}/icon_32x32.png"      >/dev/null
/usr/bin/sips -s format png -z 64 64     "$BASE" --out "${ICONSET}/icon_32x32@2x.png"   >/dev/null
/usr/bin/sips -s format png -z 128 128   "$BASE" --out "${ICONSET}/icon_128x128.png"     >/dev/null
/usr/bin/sips -s format png -z 256 256   "$BASE" --out "${ICONSET}/icon_128x128@2x.png"  >/dev/null
/usr/bin/sips -s format png -z 256 256   "$BASE" --out "${ICONSET}/icon_256x256.png"     >/dev/null
/usr/bin/sips -s format png -z 512 512   "$BASE" --out "${ICONSET}/icon_256x256@2x.png"  >/dev/null
/usr/bin/sips -s format png -z 512 512   "$BASE" --out "${ICONSET}/icon_512x512.png"     >/dev/null
/usr/bin/sips -s format png -z 1024 1024 "$BASE" --out "${ICONSET}/icon_512x512@2x.png"  >/dev/null

/usr/bin/iconutil -c icns "$ICONSET" -o "$OUT_ICNS"
rm -rf "$ICONSET"
echo "==> 已生成: $OUT_ICNS"
