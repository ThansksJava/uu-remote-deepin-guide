#!/usr/bin/env bash
# 把 UU 窗口置顶并验证
set -u
GUIDE_DIR="${UURB_GUIDE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC1091
. "$GUIDE_DIR/config/guide.env"
mkdir -p "$LOG_DIR"

P="$LOG_DIR"
BR="$(uurb_runtime_dir)"
AUTH="$BR/Xauthority"
DISP="$(uurb_private_display)"
X() { DISPLAY="$DISP" XAUTHORITY="$AUTH" xdotool "$@"; }
{
echo "== $(date '+%T') =="
echo "私有屏=$DISP"
UW=$(X search --name '网易UU远程' 2>/dev/null | tail -1)
echo "UU 窗口: ${UW:-无}"
[ -n "$UW" ] || { echo "未找到 UU 窗口，先跑 05-recover.sh"; }
X windowraise "$UW" 2>&1
X windowactivate --sync "$UW" 2>&1
X windowfocus "$UW" 2>&1
sleep 1
AW=$(X getactivewindow 2>/dev/null)
echo "置顶后活动窗口: ${AW:-无} ($(X getwindowname "$AW" 2>/dev/null))"
X getwindowname "$AW" 2>/dev/null
# 若活动窗口仍不是 UU，再试一次 windowmap+activate
if [ -n "$UW" ] && [ "$AW" != "$UW" ]; then
    echo "-- 再试 windowmap + activate"
    X windowmap "$UW" 2>&1
    X windowactivate "$UW" 2>&1
    sleep 1
    AW=$(X getactivewindow 2>/dev/null)
    echo "二次置顶后活动窗口: ${AW:-无} ($(X getwindowname "$AW" 2>/dev/null))"
fi
echo "-- console-focus: $([ -e "$BR/console-focus" ] && echo 存在 || echo 不存在)"
echo "GameViewer(小窗) id: $(X search --name '^GameViewer$' 2>/dev/null)"
echo "== done（日志：$P/raise.log）=="
} > "$P/raise.log" 2>&1
