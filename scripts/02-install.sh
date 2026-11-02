#!/usr/bin/env bash
# deepin-port：运行打补丁后的 install.sh（VNC 中继路径）
# 以**当前登录用户**在真实桌面终端运行；中继密码经 stdin 喂入。
# 仓库位置 / 分辨率 / 密码都来自 config/guide.env（可用环境变量覆盖）。
set -uo pipefail
GUIDE_DIR="${UURB_GUIDE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC1091
. "$GUIDE_DIR/config/guide.env"

RES="$(uurb_resolution)"
echo "== install: repo=$REPO_DIR resolution=$RES target=$(uurb_desktop_display) user=$(id -un)"
cd "$REPO_DIR" || { echo "找不到仓库 $REPO_DIR（改 config/guide.env 里的 REPO_DIR）"; exit 1; }

# 按前缀里 GameViewerServer.exe 的哈希选清单：同是 4.42.1.2835，NetEase 重新发布过的构建
# 哈希不同，要用 uu-remote-4.42.1.2835-r0924.json（见 TROUBLESHOOTING 第 20 条）。
# 已打过补丁时 .uu-original 才是原版。
SERVER="$WINE_PREFIX/drive_c/Program Files/Netease/GameViewer/bin/GameViewerServer.exe"
[ -f "$SERVER.uu-original" ] && SERVER="$SERVER.uu-original"
SERVER_SHA="$(sha256sum "$SERVER" 2>/dev/null | awk '{print $1}')"
MANIFEST="$(grep -lF "\"original_sha256\": \"$SERVER_SHA\"" patches/*.json 2>/dev/null | head -1)"
if [ -z "$SERVER_SHA" ] || [ -z "$MANIFEST" ]; then
    echo "!! 前缀里的 GameViewerServer.exe（${SERVER_SHA:-不存在}）不匹配 patches/ 里任何清单"
    echo "   先跑 scripts/03-seed-prefix.sh；仍不匹配见 TROUBLESHOOTING 第 20 条"
    exit 1
fi
echo "== release manifest: $MANIFEST"

printf '%s\n%s\n' "$RELAY_PASS" "$RELAY_PASS" | ./install.sh \
    --release-manifest "$MANIFEST" \
    --skip-packages \
    --skip-account-login \
    --desktop-relay vnc \
    --desktop-target "$(uurb_desktop_display)" \
    --display auto \
    --resolution "$RES"
rc=$?
echo "INSTALL_EXIT=$rc"
exit $rc
