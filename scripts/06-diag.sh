#!/usr/bin/env bash
# 私有屏诊断（Windows / 进程 / 映射状态）
set -u
GUIDE_DIR="${UURB_GUIDE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC1091
. "$GUIDE_DIR/config/guide.env"
mkdir -p "$LOG_DIR"

P="$LOG_DIR"
BR="$(uurb_runtime_dir)"
AUTH="$BR/Xauthority"
DISP="$(uurb_private_display)"
{
echo "== $(date '+%T') =="
echo "user=$(id -un) uid=$(id -u) host=$(hostname) 私有屏=$DISP"
echo "-- wine 进程 (pgrep -af):"
pgrep -af "GameViewer" | head -6
echo "-- ps 兜底:"
ps -u "$(id -u)" -o pid,comm,args | grep -i -E "gameviewer|wine" | grep -v grep | head -8
echo "-- $DISP 可见窗口:"
DISPLAY="$DISP" XAUTHORITY="$AUTH" xdotool search --onlyvisible --name "." 2>/dev/null | while read -r w; do
    n=$(DISPLAY="$DISP" XAUTHORITY="$AUTH" xdotool getwindowname "$w" 2>/dev/null)
    s=$(DISPLAY="$DISP" XAUTHORITY="$AUTH" xprop -id "$w" WM_STATE 2>/dev/null | head -1)
    g=$(DISPLAY="$DISP" XAUTHORITY="$AUTH" xdotool getwindowgeometry "$w" 2>/dev/null | tr '\n' ' ')
    echo "  $w | $n | $s | $g"
done
echo "-- UU 窗口映射状态:"
UW=$(DISPLAY="$DISP" XAUTHORITY="$AUTH" xdotool search --name '网易UU远程' 2>/dev/null | tail -1)
[ -n "$UW" ] && DISPLAY="$DISP" XAUTHORITY="$AUTH" xprop -id "$UW" WM_STATE WM_MAP_STATE 2>/dev/null
echo "-- viewer 捕获目标 x11vnc 进程:"
pgrep -af "x11vnc.*5921" | head -2
echo "-- console 单元:"
systemctl --user is-active uu-window-open 2>&1
echo "== 日志：$P/diag.log =="
} > "$P/diag.log" 2>&1
