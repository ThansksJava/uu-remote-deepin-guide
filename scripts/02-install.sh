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

printf '%s\n%s\n' "$RELAY_PASS" "$RELAY_PASS" | ./install.sh \
    --skip-packages \
    --skip-account-login \
    --desktop-relay vnc \
    --desktop-target "$(uurb_desktop_display)" \
    --display auto \
    --resolution "$RES"
rc=$?
echo "INSTALL_EXIT=$rc"
exit $rc
