# 双屏「扩展」时远端画面异常：原因、尝试与回退

> 本文由 `~/uu-双屏诊断/诊断说明.md` 摘出（去掉本地截图）。

> **当前状态（2026-10-12 14:31 更新）**：
> 1) 文中的「让画布跟随整桌面」修复已于 14:09 **回退**（见文末「六、回退记录」）；
> 2) 现在采用的是**把中继裁剪到单块显示器**：`UURB_RELAY_CLIP=auto`
>    → 远端只看到**主屏（笔记本内屏）**、原生尺寸、点击位置正确（见文末「七」）。
> 下面「一、结论」里的**原因仍然成立**，但「修法」已不再启用。

> 诊断：2026-10-12 13:36 ｜ 首次修复：13:53 ｜ 回退：14:09
> 被控机：本机（Deepin 25，X11 会话，桌面 `:0`）

---

## 一、结论（一句话）

中继抓的是**整块虚拟桌面的外接矩形**（两块屏合起来 1922×2280），
而 UU 真正编码的画布（私有屏 `:20` 的 Xvfb 屏幕）被**固定成了 1920×1200**（单屏尺寸）。
两者对不上时，TigerVNC **不缩放、只显示左上角那一块** ——
于是"外接屏整屏 + 内屏最上面 120 行"被塞进同一幅画面；两块屏又是同一张壁纸，
看起来就像两个屏幕叠在了一起。

**当时的修法（⚠️ 已回退）**：把画布改成和桌面一样大（1922×2280），并打开"跟随桌面"开关，让以后插拔屏自动对齐。

---

## 二、本机实测数据

| 项 | 原来 | 曾改成（已回退） | 依据 |
|---|---|---|---|
| 外接屏 DP-1-2 | 1920×1080 **+2+0**（在上） | 同左 | `xrandr --listmonitors` |
| 内屏 eDP-1 | 1920×1200 **+0+1080**（在下） | 同左 | `xrandr --listmonitors` |
| 桌面总尺寸（root window） | **1922×2280** | 同左 | `xdpyinfo` / `xwininfo -root` |
| 中继抓到的帧 | 1922×2280 | 1922×2280 | `desktop-x11vnc.log`：`Xinerama: sub-screen[0] 1920x1200+0+1080`、`Sending rfbEncodingExtDesktopSize for size (1922x2280)` |
| UU 的画布（`:20`） | **1920×1200** ❌ | **1922×2280** ✅ | `environment` 的 `UURB_RESOLUTION`；`:20` 由 `Xvfb -screen 0 ${resolution}x24` 建立 |
| 是否跟随桌面 | `off` | `on` | `environment` 的 `UURB_FOLLOW_DESKTOP_RESOLUTION` |
| GameViewer 上报的屏 | — | **1922×2280** | `ProgramData/Netease/GameViewer/cache_setting.ini`（13:55 更新） |

补充证据：桌面是**今天 13:34~13:36 才变成双屏的**：

```
13:34:57  rfbNewFramebuffer(..., 1920, 1080, ...)      ← 之前（单屏）
13:36:00  rfbNewFramebuffer(..., 1922, 2280, ...)      ← 插上第二块屏、设为扩展后
```

而 `:20` 的画布是安装当天按"单屏 1920×1200"写死的，之后不会自己改。

---

## 三、复现验证（不是猜的，两次都做了逐像素比对）

用**同样的 TigerVNC 1.15、同样的参数**（`-FullScreen=1 -Shared=1`），
把同一个中继（`127.0.0.1:5922`，内容就是本机 `:0`）显示在一块新建的 Xvfb 屏上，截图后算 PSNR：

| 场景 | 假设 | PSNR | 判定 |
|---|---|---|---|
| 画布 1920×1200（修复前） | = 桌面左上角 1920×1200 裁切 | **41.1 dB** | ✅ 几乎逐像素相同 → 确认是"裁切" |
| 画布 1920×1200（修复前） | = 整屏 1922×2280 等比缩放 | 5.9 dB | ❌ 完全不相关 |
| 画布 1922×2280（修复后） | = **完整桌面 1922×2280** | **39.8 dB** | ✅ 几乎逐像素相同 → 确认"整屏都能看到" |

结论：**改画布尺寸就能决定远控看到多少**，1922×2280 时远端拿到的是完整双屏。

---

## 四、关键坑：`xdotool getdisplaygeometry` 只报"主屏"

桥接里原来用 `xdotool getdisplaygeometry` 读桌面尺寸。**这个命令在多屏 Xinerama 下只返回主屏
（eDP-1，1920×1200）的尺寸，不是整个 root window**：

```bash
$ DISPLAY=:0 xdotool getdisplaygeometry     # → 1920 1200   ← 只报主屏！
$ DISPLAY=:0 xdpyinfo | grep dimensions     # → 1922x2280   ← 真正的桌面总尺寸
$ DISPLAY=:0 xwininfo -root | grep -E 'Width|Height'   # → 1922 / 2280
```

后果很严重：**只开 `UURB_FOLLOW_DESKTOP_RESOLUTION=on` 是没用的** ——
它算出来的 1920×1200 和当时的画布一样，函数直接认为"无需改动"，什么都不会发生。

所以修复分两步：**先改探测方式，再打开开关**。

---

## 五、实际做的修复

### 1) 补丁：把 `desktop_geometry()` 改成读整个 root window

文件：`~/Desktop/uu-remote-ubuntu-bridge/scripts/uu-remote-bridge`
（函数 `desktop_geometry()`，原来读 `xdotool getdisplaygeometry`）

改为：

```bash
# The relay mirrors the whole root window, so on a multi-monitor desktop
# the canvas has to match the combined geometry of every monitor.
# xdotool getdisplaygeometry only reports the primary Xinerama screen,
# which silently clips all other monitors, so query the root window from
# the X server and keep xdotool as a fallback for unusual setups.
geometry="$(/usr/bin/env \
    DISPLAY="$desktop_display" \
    XAUTHORITY="$selected_xauthority" \
    /usr/bin/xdpyinfo 2>/dev/null |
    /usr/bin/awk '/dimensions:/{print $2; exit}')"
if [[ "$geometry" =~ ^[0-9]+x[0-9]+$ ]]; then
    width="${geometry%x*}"
    height="${geometry#*x}"
else
    read -r width height < <(   # 兜底：老办法
        /usr/bin/env DISPLAY="$desktop_display" XAUTHORITY="$selected_xauthority" \
            /usr/bin/xdotool getdisplaygeometry 2>/dev/null
    ) || return 1
fi
```

### 2) 部署：**注意服务跑的是 `~/.local/bin/` 里那份独立拷贝**

```bash
cp -f ~/Desktop/uu-remote-ubuntu-bridge/scripts/uu-remote-bridge ~/.local/bin/uu-remote-bridge
bash -n ~/.local/bin/uu-remote-bridge && echo OK
```

### 3) 配置：打开跟随 + 把当前画布设成桌面总尺寸

`~/.config/uu-remote-bridge/environment`：

```
UURB_RESOLUTION=1922x2280
UURB_FOLLOW_DESKTOP_RESOLUTION=on
```

> 两条都要写：`FOLLOW=on` 管"以后自动对齐"，`RESOLUTION` 管"本次立刻生效"。

### 4) 重启桥接

```bash
rrs        # = systemctl --user restart uu-remote-bridge.service
```

重启后日志时间戳（`~/.local/state/uu-remote-bridge/`）全部刷新为 13:53:27~13:54:07，
`vncviewer-relay.log` 末尾为新一轮 TigerVNC 启动记录。

### 5) 验证（三条独立证据）

```bash
# ① 画布尺寸：GameViewer 自己上报的屏尺寸
grep -E 'width|height' \
  ~/.local/share/wineprefixes/uu-remote/drive_c/ProgramData/Netease/GameViewer/cache_setting.ini
#   → width=1922 / height=2280   （monitor_friendly_name=Display1）

# ② 中继侧：x11vnc 对外声明的桌面尺寸
grep -E 'rfbEncodingExtDesktopSize|sub-screen' \
  ~/.local/state/uu-remote-bridge/desktop-x11vnc.log | tail -3
#   → sub-screen[0] 1920x1200+0+1080 / sub-screen[1] 1920x1080+2+0
#   → Sending rfbEncodingExtDesktopSize for size (1922x2280)

# ③ 客户端侧（复现）：同版本 TigerVNC 把中继显示到 1922×2280 的屏上截图
#   → 与真实桌面全图 PSNR = 39.8 dB（完整双屏，无裁切）
```

---

## 六、以后怎么办 / 怎么回滚

- **换显示器、改分辨率、改排列**：什么都不用做。`FOLLOW=on` 后，桥接的守护逻辑
  每 20 个检查周期读一次桌面尺寸，**连续 3 次稳定不同**就写回 `UURB_RESOLUTION` 并自动重启对齐
  （约 15 秒判定 + 一次重启；重启会断开当前远控，重连即可）。
- **想远端是"横向双屏"**：在 DDE 显示设置里把两块屏改成左右排列（总尺寸 3840×1200），
  等它自动对齐即可（或直接 `rrs`）。
- **只想远控其中一块屏**：桥接目前不支持自定义 x11vnc 参数（没有 `-clip`）。
  最省事是在 DDE 里把另一块屏设成"仅此屏 / 关闭"；要保留双屏只远控一块，得给桥接加个
  `UURB_RELAY_CLIP` 之类的开关（改源码）。
- **回滚**：把 `environment` 里 `UURB_FOLLOW_DESKTOP_RESOLUTION` 改回 `off`、
  `UURB_RESOLUTION` 改回单屏尺寸，再 `rrs`。

判断是否对齐的方法：

```bash
grep UURB_RESOLUTION ~/.config/uu-remote-bridge/environment
DISPLAY=:0 xdpyinfo | grep dimensions        # 两者应一致
```

> 附注：外接屏起点是 `+2`，所以总宽 1922 不是 4 的倍数，x11vnc 会警告
> `Width (1922) is not a multiple of 4. VncViewer has problems with that.` —— 实测无害。
> 想彻底消掉，可以在 DDE 显示设置里把两块屏左边缘对齐（起点变 +0，总宽 1920）。

---

---

## 七、结语

复现脚本用的是同版本 TigerVNC 连本机中继：

```bash
mkdir -p /tmp/.X11-unix
Xvfb :97 -screen 0 1922x2280x24 -dpi 96 -nolisten tcp -noreset -ac &
sleep 3; DISPLAY=:97 openbox & sleep 1
DISPLAY=:97 vncviewer -FullScreen=1 -Shared=1 127.0.0.1:5922 &
sleep 16
DISPLAY=:97 ffmpeg -f x11grab -video_size 1922x2280 -i :97.0 -frames:v 1 -y /tmp/after.png
```

再把 `/tmp/after.png` 与真实桌面全图比对：

```bash
DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority ffmpeg -f x11grab -video_size 1922x2280 -i :0.0 -frames:v 1 -y /tmp/real.png
ffmpeg -i /tmp/real.png -i /tmp/after.png -lavfi psnr -f null -   # 期望 ~40 dB
```

---

## 六、回退记录（2026-10-12 14:09）

**为什么回退**（实际体验）：

1. **画面太小**：把整块桌面（1922×2280）当画布后，客户端只能在窗口里等比缩小显示，
   字和图都过小，反而不如原来"裁切"看得清。
2. **断屏不自适应**：拔掉扩展屏后画布不会立刻跟着变，要等守护逻辑连续判定稳定后重启对齐，
   体感上就是"不自动"。

**回退了什么**：

- `~/.config/uu-remote-bridge/environment`：恢复 `UURB_RESOLUTION=1920x1200`、`UURB_FOLLOW_DESKTOP_RESOLUTION=off`
- `scripts/uu-remote-bridge` 的 `desktop_geometry()` 恢复用 `xdotool`（提交 `448700c` 是 `77e2d36` 的 revert）
- 部署：`cp -f scripts/uu-remote-bridge ~/.local/bin/uu-remote-bridge`，然后重启服务

**记录保留在哪**：本文件 + `TROUBLESHOOTING.md` 第 15 条 + 桥接仓库提交 `77e2d36`（尝试）/ `448700c`（回退）。

**想重新启用**：

```bash
git -C ~/Desktop/uu-remote-ubuntu-bridge revert -n 448700c     # 取回 xdpyinfo 探测补丁
cp -f ~/Desktop/uu-remote-ubuntu-bridge/scripts/uu-remote-bridge ~/.local/bin/uu-remote-bridge
# environment: UURB_RESOLUTION=<桌面总尺寸> + UURB_FOLLOW_DESKTOP_RESOLUTION=on
rrs
```

---

## 七、为什么用不了 UU 自带的「多屏选择」

UU 远程的"顶部屏幕页签 / 切换显示器"要求**被控端是 Windows 10 及以上或 macOS 11 及以上**
（官方帮助 `https://uuyc.163.com/help/multiscreen.html`，且多屏映射目前**仅支持被控端为 Windows**）。
本机是 Linux 被控端，UU 跑在 Wine 里：它眼里的"显示器"只有一个 —— 私有屏 `:20` 的那块 Xvfb 画布，
所以客户端不会出现两个屏幕的页签。真实的两块物理屏是在**中继层**（x11vnc 抓 `:0` 的 root window）
才被合成一张画面的。

**实际采用的替代方案（已实装，2026-10-12 14:31）**：把中继裁剪到**一块显示器**，
默认就是主屏（笔记本内屏）—— 这样远控窗口里的画面就是内屏本身，原生尺寸、点击位置也正确，
正好可以在内屏上打开控制中心去关掉扩展屏。

开关（`~/.config/uu-remote-bridge/environment`）：

```bash
UURB_RELAY_CLIP=auto            # off（默认整体桌面）| auto（主屏）| WxH+X+Y（指定那块屏）
UURB_RESOLUTION=1920x1200       # 画布；auto 模式会按主屏尺寸自动对齐，不用手改
UURB_FOLLOW_DESKTOP_RESOLUTION=off
```

实现要点：

1. `resolve_relay_clip()` 用 `xrandr --listmonitors` 里带 `*` 的那块（主屏）取 `WxH+X+Y`，
   本机解析结果 `1920x1200+0+1080`；
2. 同一几何同时给 **x11vnc**（`-clip`）和 **uu-x11-input**（`--clip`）——
   注入侧必须按裁剪矩形做偏移映射，否则归一化坐标会被当成整个 root 而点偏；
3. `supervise_server` 每 5 秒比对一次主屏几何，连续 3 次不同就重启桥接重新对齐——
   所以你在远控里把外接屏关掉之后，桥接会自己跟着变成"整块屏"。

验证：

```bash
# 中继对外声明的帧尺寸应等于主屏尺寸（本机 1920x1200），而不是桌面总尺寸 1922x2280
grep rfbEncodingExtDesktopSize ~/.local/state/uu-remote-bridge/desktop-x11vnc.log | tail -1
# 坐标映射自带验收测试
bash ~/Desktop/uu-remote-ubuntu-bridge/scripts/test-x11-input-clip.sh
```

提交：`deepin-port` 分支（`uu-x11-input --clip`、桥接 `UURB_RELAY_CLIP`、新增测试脚本）。
