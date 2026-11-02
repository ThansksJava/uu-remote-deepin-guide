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
    if [ ! -d "$SEED_CACHE/bin" ]; then
        echo "-- SEED_SRC 不存在，改从官方安装包取种子（scripts/fetch-seed.sh）"
        bash "$GUIDE_DIR/scripts/fetch-seed.sh"
    fi
    SEED_SRC="$SEED_CACHE"
    echo "seed 源（改用）: $SEED_SRC"
fi
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
"$WINE_BIN" winecfg -v win10 2>&1 | tail -1 || true
"$WINESERVER_BIN" -w 2>/dev/null || true

echo "-- 复制 UU 文件（02-install.sh 会按 GameViewerServer.exe 的哈希选清单并校验）"
mkdir -p "$WINEPREFIX/drive_c/Program Files/Netease"
cp -a "$SEED_SRC" "$WINEPREFIX/drive_c/Program Files/Netease/GameViewer"

# 种子前缀没跑过官方安装器，GameViewerService 没注册 → 桥接起不来后台进程
# （"UU Remote background processes did not become ready"，见 TROUBLESHOOTING 第 21 条）
echo "-- 注册 GameViewerService"
K='HKLM\System\CurrentControlSet\Services\GameViewerService'
"$WINE_BIN" reg add "$K" /v DisplayName /t REG_SZ /d GameViewerService /f >/dev/null
"$WINE_BIN" reg add "$K" /v ErrorControl /t REG_DWORD /d 1 /f >/dev/null
"$WINE_BIN" reg add "$K" /v ImagePath /t REG_EXPAND_SZ \
    /d '"C:\Program Files\Netease\GameViewer\GameViewerService.exe" --service' /f >/dev/null
"$WINE_BIN" reg add "$K" /v ObjectName /t REG_SZ /d LocalSystem /f >/dev/null
"$WINE_BIN" reg add "$K" /v Start /t REG_DWORD /d 2 /f >/dev/null
"$WINE_BIN" reg add "$K" /v Type /t REG_DWORD /d 16 /f >/dev/null
"$WINESERVER_BIN" -w 2>/dev/null || true

echo "== seed done: $(date) =="
ls "$WINEPREFIX/drive_c/Program Files/Netease/GameViewer/bin" | wc -l
