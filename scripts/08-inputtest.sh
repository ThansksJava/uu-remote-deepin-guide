#!/usr/bin/env bash
# 输入链路分段测试：直接对私有屏上的 UU 窗口发 XTEST 点击，验证注入通道是否通
#
# 说明：窗口 id 与位置**不再写死**——先按窗口名查到 UU 主窗，再用它的实时几何
# 计算"立即登录"按钮位置（窗口宽 49.4% / 高 80% 处，与原实测比例一致）。
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

# 找 UU 主窗（若还没登录就是"网易UU远程"主窗）
UW="$(X search --name '网易UU远程' 2>/dev/null | tail -1)"
[ -n "$UW" ] || UW="$(X search --name 'GameViewer' 2>/dev/null | tail -1)"
if [ -z "$UW" ]; then
    echo "未找到 UU 窗口，先跑 04-open.sh / 05-recover.sh"
    echo "== done =="
    exit 0
fi

eval "$(X getwindowgeometry --shell "$UW")"   # 得到 X / Y / WIDTH / HEIGHT
echo "UU 窗口 id=$UW 位置=$X,$Y 尺寸=${WIDTH}x${HEIGHT}"
X windowactivate "$UW" 2>/dev/null; sleep 1

BX=$(( X + WIDTH  * 494 / 1000 ))
BY=$(( Y + HEIGHT * 800 / 1000 ))
echo "-- 直接 XTEST 点击按钮位置 ($BX,$BY)（窗口内 49.4%/80%）"
X mousemove --sync "$BX" "$BY"
sleep 0.5
X click 1
sleep 4
echo "-- 点击完成，查 $DISP 是否出现新窗口（登录二维码窗）"
X search --onlyvisible --name "." 2>/dev/null | while read -r w; do
    n=$(X getwindowname "$w" 2>/dev/null)
    echo "  $w | $n"
done
echo "== done（日志：$P/inputtest.log）=="
} > "$P/inputtest.log" 2>&1
