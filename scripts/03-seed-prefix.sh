#!/usr/bin/env bash
# deepin-port：用 WineHQ Wine 11 建干净前缀，并从**本机已有的 UU 文件**种子
# UU 4.42.1.2835（绕过 32 位官方安装器——Deepin 无法提供 i386 运行库）
#
# 种子来源见 config/guide.env 的 SEED_SRC（★ 真实前置条件）：
#   默认值 = Spark 商店版 potplayer 前缀里的 GameViewer 目录；换机时请改这里，
#   或者把一份 UU 4.42.1.2835 的 GameViewer 目录放到该路径上。
set -Eeuo pipefail
GUIDE_DIR="${UURB_GUIDE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC1091
. "$GUIDE_DIR/config/guide.env"

export WINEPREFIX="$WINE_PREFIX"
export WINEDEBUG=-all
export WINEDLLOVERRIDES='mscoree,mshtml='

echo "== seed start: $(date) =="
echo "user=$(id -un) prefix=$WINEPREFIX"
echo "seed 源: $SEED_SRC"

if [ ! -d "$SEED_SRC/bin" ]; then
    echo "!! 种子源不存在或不是 UU 目录: $SEED_SRC"
    echo "   请准备一份已认证的 UU 4.42.1.2835 GameViewer 目录，"
    echo "   并设置 SEED_SRC 指向它（见 README『本机前置条件』）。"
    exit 1
fi

rm -rf "$WINEPREFIX"
mkdir -p "$WINEPREFIX"

echo "-- wineboot（64 位构建会有 syswow64 警告，属预期）"
"$WINE_BIN" wineboot -u 2>&1 | grep -v -E "^$" || true
sleep 3
"$WINESERVER_BIN" -w 2>/dev/null || true

echo "-- winecfg win10"
/opt/wine-stable/bin/winecfg -v win10 2>&1 | tail -1 || true
"$WINESERVER_BIN" -w 2>/dev/null || true

echo "-- 复制已认证的 UU 4.42.1.2835（哈希已与 prebuilt/release-manifest.json 核对一致）"
mkdir -p "$WINEPREFIX/drive_c/Program Files/Netease"
cp -a "$SEED_SRC" "$WINEPREFIX/drive_c/Program Files/Netease/"

echo "== seed done: $(date) =="
ls "$WINEPREFIX/drive_c/Program Files/Netease/GameViewer/bin" | wc -l
