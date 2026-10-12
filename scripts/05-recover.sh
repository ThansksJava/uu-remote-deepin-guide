#!/usr/bin/env bash
# UU 窗口恢复 + 输入链路诊断（不改机器相关取值；用户名/屏号/路径见 config/guide.env）
set -u
GUIDE_DIR="${UURB_GUIDE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC1091
. "$GUIDE_DIR/config/guide.env"
mkdir -p "$LOG_DIR"

P="$LOG_DIR"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus"
BR="$RUNTIME_DIR/uu-remote-bridge"
AUTH="$BR/Xauthority"
PREFIX="$WINE_PREFIX"
APP="$PREFIX/drive_c/Program Files/Netease/GameViewer"
DISP="$(uurb_private_display)"
DESK="$(uurb_desktop_display)"

{
echo "== $(date '+%T') 恢复开始 =="
echo "user=$(id -un) uid=$(id -u) host=$(hostname) 私有屏=$DISP 真实桌面=$DESK"
echo "bridge: $(systemctl --user is-active uu-remote-bridge.service)"

# 1) 清掉残留投屏单元
systemctl --user reset-failed 'uu-window-*' 2>/dev/null
systemctl --user stop 'uu-window-*' 2>/dev/null

# 2) 客户端不在就拉起
if ! pgrep -x GameViewer.exe >/dev/null; then
    echo "-- 拉起 UU 客户端"
    cd "$APP" && setsid env DISPLAY="$DISP" XAUTHORITY="$AUTH" WINEPREFIX="$PREFIX" \
        LIBGL_ALWAYS_SOFTWARE=1 nohup "$WINE_BIN" ./GameViewer.exe \
        >"$P/client-r4.log" 2>&1 < /dev/null &
    sleep 15
fi
echo "client pid: $(pgrep -x GameViewer.exe | head -1)"

# 3) openbox 没了就补
if ! pgrep -x openbox >/dev/null; then
    echo "-- 重启 openbox"
    setsid env DISPLAY="$DISP" XAUTHORITY="$AUTH" nohup /usr/bin/openbox \
        >>"$P/openbox-restart.log" 2>&1 < /dev/null &
    sleep 4
fi

# 4) 投屏
echo "-- 投屏"
systemd-run --user --unit=uu-window-open --setenv=DISPLAY="$DESK" \
    "$HOME/.local/bin/uu-remote-console" window >"$P/window-open2.log" 2>&1 &
sleep 20
VW=$(DISPLAY="$DESK" xdotool search --name 'UU Remote - TigerVNC' 2>/dev/null | head -1)
echo "viewer 窗口: ${VW:-无}"

# 5) 输入链路诊断：console-focus 文件 + 私有屏上活动窗口是不是 UU
echo "console-focus 文件: $([ -e "$BR/console-focus" ] && echo 存在 || echo 不存在)"
AW=$(DISPLAY="$DISP" XAUTHORITY="$AUTH" xdotool getactivewindow 2>/dev/null)
AWn=$(DISPLAY="$DISP" XAUTHORITY="$AUTH" xdotool getwindowname "$AW" 2>/dev/null)
echo "私有屏活动窗口: ${AW:-无} ($AWn)"
UW=$(DISPLAY="$DISP" XAUTHORITY="$AUTH" xdotool search --name '网易UU远程' 2>/dev/null | tail -1)
echo "UU 窗口 id: ${UW:-无}（viewer 应捕获它）"
DISPLAY="$DISP" XAUTHORITY="$AUTH" xdotool windowactivate --sync "$UW" 2>/dev/null
AW=$(DISPLAY="$DISP" XAUTHORITY="$AUTH" xdotool getactivewindow 2>/dev/null)
echo "手动激活后私有屏活动窗口: ${AW:-无}"
echo "== 恢复结束（日志：$P/recover.log）=="
} > "$P/recover.log" 2>&1
