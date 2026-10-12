#!/usr/bin/env bash
# 抓取 UU 登录二维码 → $LOG_DIR/login.png
#
# 说明：登录窗的位置/尺寸**不再写死**（原实现固定 808x608 @ 556,328），
# 改为先按窗口名找到登录窗，再用它的实时几何去截取。
set -u
GUIDE_DIR="${UURB_GUIDE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC1091
. "$GUIDE_DIR/config/guide.env"
mkdir -p "$LOG_DIR"

BR="$(uurb_runtime_dir)"
AUTH="$BR/Xauthority"
DISP="$(uurb_private_display)"
P="$LOG_DIR"
{
echo "== $(date '+%T')"
X() { DISPLAY="$DISP" XAUTHORITY="$AUTH" xdotool "$@"; }
echo "私有屏=$DISP"

LW=$(X search --name '^GameViewer$' 2>/dev/null | tail -1)
if [ -z "$LW" ]; then
    echo "未找到登录窗（标题 GameViewer）——可能还没弹登录窗，或已经登录完成。"
    echo "可先跑 08-inputtest.sh 点开登录窗，或 05-recover.sh 重建投屏。"
    echo "== done"
    exit 0
fi
X windowactivate "$LW" 2>/dev/null; sleep 1
echo "堆叠: $(DISPLAY="$DISP" XAUTHORITY="$AUTH" xprop -root _NET_CLIENT_LIST_STACKING 2>/dev/null | grep -o '0x[0-9a-f]*' | tr '\n' ' ')"
echo "登录窗: $LW (hex $(printf '0x%x' "$LW"))"

eval "$(X getwindowgeometry --shell "$LW")"   # X / Y / WIDTH / HEIGHT
echo "登录窗几何: $X,$Y ${WIDTH}x${HEIGHT}"
DISPLAY="$DISP" XAUTHORITY="$AUTH" ffmpeg -hide_banner -loglevel error \
    -f x11grab -video_size "${WIDTH}x${HEIGHT}" -i "$DISP.0+$X,$Y" -frames:v 1 -y "$P/login.png" 2>&1 | tail -2
ls -l "$P/login.png"
echo "二维码已存到 $P/login.png —— 用手机 UU App 扫码（1-2 分钟过期）"
echo "== done"
} > "$P/loginshot2.log" 2>&1
