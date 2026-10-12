#!/usr/bin/env bash
# Deepin 适配版：UU 管理窗口一键拉起（自愈：自动补起 openbox 和客户端）
# 机器相关取值（用户名/UID/私有屏号/前缀/Wine 路径/日志目录）统一来自 config/guide.env
set -u
GUIDE_DIR="${UURB_GUIDE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC1091
. "$GUIDE_DIR/config/guide.env"
mkdir -p "$LOG_DIR"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus"
P="$LOG_DIR"
BR="$RUNTIME_DIR/uu-remote-bridge"
BR_AUTH="$BR/Xauthority"
PREFIX="$WINE_PREFIX"
APP="$PREFIX/drive_c/Program Files/Netease/GameViewer"
DISP="$(uurb_private_display)"
DESK="$(uurb_desktop_display)"

echo "== $(date '+%F %T') =="
echo "-- user=$(id -un) uid=$(id -u) host=$(hostname) 私有屏=$DISP 真实桌面=$DESK"

# 1. 桥接服务
state="$(systemctl --user is-active uu-remote-bridge.service 2>/dev/null || true)"
if [[ "$state" != active ]]; then
    echo "-- 启动桥接服务"
    systemctl --user start uu-remote-bridge.service
    sleep 30
fi
echo "-- bridge 服务: $(systemctl --user is-active uu-remote-bridge.service)"

# 2. 私有屏上的 openbox（此前崩溃过会导致窗口无法被识别）
if ! DISPLAY="$DISP" XAUTHORITY="$BR_AUTH" xdpyinfo >/dev/null 2>&1; then
    echo "-- 私有屏 $DISP 不可用，等待桥接自愈"; sleep 20
fi
if ! pgrep -x openbox >/dev/null 2>&1; then
    echo "-- 重启 openbox"
    setsid env DISPLAY="$DISP" XAUTHORITY="$BR_AUTH" \
        nohup /usr/bin/openbox >>"$P/openbox-restart.log" 2>&1 < /dev/null &
    sleep 4
fi

# 3. UU 客户端（桥接只在服务启动那一刻拉一次，掉了要补）
if ! pgrep -x GameViewer.exe >/dev/null 2>&1; then
    echo "-- 拉起 UU 客户端"
    cd "$APP" && setsid env DISPLAY="$DISP" XAUTHORITY="$BR_AUTH" \
        WINEPREFIX="$PREFIX" LIBGL_ALWAYS_SOFTWARE=1 \
        nohup "$WINE_BIN" ./GameViewer.exe \
        >"$P/client-manual.log" 2>&1 < /dev/null &
    sleep 14
fi

# 4. 投屏到桌面（长驻进程，后台运行）
echo "-- 投屏 UU 窗口到桌面"
systemctl --user reset-failed 'uu-window-*' 2>/dev/null
setsid systemd-run --user --unit=uu-window-open --setenv=DISPLAY="$DESK" \
    "$HOME/.local/bin/uu-remote-console" window \
    >"$P/window-open.log" 2>&1 &
sleep 20
if DISPLAY="$DESK" xdotool search --name "UU Remote - TigerVNC" >/dev/null 2>&1; then
    echo "✅ UU 窗口已显示在桌面上"
else
    echo "❌ 仍未出现，日志: $P/window-open.log"
    tail -3 "$P/window-open.log"
fi
echo "== OPEN_DONE =="
