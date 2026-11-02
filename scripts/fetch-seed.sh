#!/usr/bin/env bash
# deepin-port：没有现成种子（SEED_SRC）时，从官方安装包现取一份 UU GameViewer 目录
#
# 官方安装器是 32 位 NSIS，WineHQ 的 64 位 Wine 跑不了，7z 也解不开它的载荷。
# Deepin 源里的 deepin-wine11-stable 自带新式 WoW64（含 i386-windows），能跑它：
#   1. 下载版本化安装包并校验 SHA-256（SEED_INSTALLER_URL / SEED_INSTALLER_SHA256）；
#   2. 临时装 deepin-wine11-stable（需要 sudo；原本没装的话结束后会卸掉）；
#   3. 在临时前缀里静默安装（/S），校验 GameViewerServer.exe 与桥接仓库某个已批准清单一致；
#   4. 把 GameViewer 目录拷到 SEED_CACHE，清理临时前缀和安装器生成的桌面/菜单快捷方式。
#
# 普通用户在真实桌面的终端里运行（安装器需要 DISPLAY）。
set -Eeuo pipefail
GUIDE_DIR="${UURB_GUIDE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC1091
. "$GUIDE_DIR/config/guide.env"

DW_PKG=deepin-wine11-stable
DW_WINE=/opt/deepin-wine11-stable/bin/wine
DW_SERVER=/opt/deepin-wine11-stable/bin/wineserver
INSTALLER="$REPO_DIR/build/downloads/uu-4.42.1.2835.exe"

echo "== fetch-seed start: $(date) =="

echo "-- [1/4] 下载并校验安装包"
mkdir -p "$(dirname "$INSTALLER")"
if ! printf '%s  %s\n' "$SEED_INSTALLER_SHA256" "$INSTALLER" | sha256sum -c - >/dev/null 2>&1; then
    curl -fL --connect-timeout 20 --max-time 900 -o "$INSTALLER.part" "$SEED_INSTALLER_URL"
    mv -f "$INSTALLER.part" "$INSTALLER"
fi
printf '%s  %s\n' "$SEED_INSTALLER_SHA256" "$INSTALLER" | sha256sum -c -

echo "-- [2/4] 准备 $DW_PKG"
dw_installed_here=false
if ! dpkg -s "$DW_PKG" >/dev/null 2>&1; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$DW_PKG"
    dw_installed_here=true
fi

WORK="$(mktemp -d)"
TMP_PREFIX="$WORK/prefix"
cleanup() {
    WINEPREFIX="$TMP_PREFIX" "$DW_SERVER" -k >/dev/null 2>&1 || true
    # 安装器会在桌面 / 开始菜单留下指向临时前缀的快捷方式，双击会起第二个 UU，删掉
    grep -lsF "$TMP_PREFIX" "$HOME/Desktop/"*.desktop \
        "$HOME/.local/share/applications/wine/Programs/"*.desktop 2>/dev/null |
        while read -r f; do rm -f -- "$f" "${f%.desktop}.lnk"; done
    rm -rf -- "$WORK"
    if [ "$dw_installed_here" = true ]; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y "$DW_PKG" || true
    fi
}
trap cleanup EXIT

echo "-- [3/4] 临时前缀里静默安装"
export WINEPREFIX="$TMP_PREFIX" WINEDEBUG=-all WINEDLLOVERRIDES='mscoree,mshtml='
export DISPLAY="${DISPLAY:-:0}"
timeout 180 "$DW_WINE" wineboot -u >/dev/null 2>&1 || true
timeout 600 "$DW_WINE" "$INSTALLER" /S || true
timeout 60 "$DW_SERVER" -w || true
"$DW_SERVER" -k >/dev/null 2>&1 || true
APP="$TMP_PREFIX/drive_c/Program Files/Netease/GameViewer"
[ -f "$APP/bin/GameViewerServer.exe" ] || { echo "!! 安装器没有产出 GameViewerServer.exe"; exit 1; }

server_sha="$(sha256sum "$APP/bin/GameViewerServer.exe" | awk '{print $1}')"
manifest="$(grep -lF "\"original_sha256\": \"$server_sha\"" "$REPO_DIR"/patches/*.json 2>/dev/null | head -1 || true)"
if [ -z "$manifest" ]; then
    echo "!! GameViewerServer.exe ($server_sha) 不匹配 $REPO_DIR/patches/ 里任何已批准清单"
    echo "   需要先按桥接仓库 docs/upstream-maintenance.md 为它生成新清单（见 TROUBLESHOOTING 第 20 条）"
    exit 1
fi
echo "   匹配清单: $(basename "$manifest")"

echo "-- [4/4] 拷贝种子 → $SEED_CACHE"
rm -rf -- "$SEED_CACHE"
mkdir -p "$(dirname "$SEED_CACHE")"
cp -a "$APP" "$SEED_CACHE"

echo "== fetch-seed done: $(date) =="
echo "SEED=$SEED_CACHE"
