# 命令速查 · 网易UU远程 Deepin 25 适配

> 全部命令均可直接复制；`把 $P` 之类变量先设好（**下面没有写死的用户名 / UID / 主机名 / 分辨率**）：
> ```bash
> P=~/.local/share/wineprefixes/uu-remote        # Wine 前缀
> U="$(id -un)"                                  # 前缀内的用户名（= 建前缀时的 Linux 用户名）
> BR="/run/user/$(id -u)/uu-remote-bridge"       # 桥接运行时目录
> REPO=~/Desktop/uu-remote-ubuntu-bridge         # 桥接仓库（可改，见 config/guide.env 的 REPO_DIR）
> G="$(cd "$(dirname "$0")" 2>/dev/null; pwd)"   # 本指南目录：直接 cd 进去就是它
> DISP="$(cat "$BR/private-display" 2>/dev/null || echo :20)"   # 私有屏号（桥接自动选）
> RES="$(DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}')"
> LOG=~/.local/state/uu-deepin-port              # 指南脚本的输出目录
> ```
> 统一的默认值都在 `config/guide.env`（所有脚本会自动读取），换机时改这里即可。

---

## 一、安装期命令（按顺序）

```bash
# 0) 准备仓库（已有 deepin-port 分支可跳过）
cd ~/Desktop && git clone https://github.com/lachlanchen/uu-remote-ubuntu-bridge.git
cd uu-remote-ubuntu-bridge && git checkout deepin-port
#    若只有上游 main，则用补丁建分支：
#    git checkout -b deepin-port && git am $G/patches/*.patch

# 1) 系统依赖 + Wine 11（需要 sudo）
sudo bash $G/scripts/01-prep.sh

# 2) 建 Wine 前缀 + 种子 UU 4.42.1.2835 文件（普通用户）
bash $G/scripts/03-seed-prefix.sh

# 3) 跑桥接安装器（必须在真实桌面的终端里，普通用户）
bash $G/scripts/02-install.sh
#    等价于：
#    cd $REPO
#    printf '%s\n%s\n' "$RELAY_PASS" "$RELAY_PASS" | ./install.sh --skip-packages --skip-account-login \
#        --desktop-relay vnc --desktop-target :0 --display auto --resolution "$RES"

# 4) 覆盖为本机验证过的配置并重启
mkdir -p ~/.config/uu-remote-bridge
cp $G/config/environment ~/.config/uu-remote-bridge/environment
systemctl --user restart uu-remote-bridge.service

# 5) 安装日常快捷命令
install -m 755 $G/bin/rrs $G/bin/uurr $G/bin/rrx $G/bin/rrd $G/bin/rrp $G/bin/uurec ~/.local/bin/
#    uurec 会自动在 UURB_GUIDE_DIR / 自身上级目录 / ~/.local/share 等处找指南目录，
#    换机后也可以 export UURB_GUIDE_DIR=<指南目录> 显式指定。

# 6) 抓登录二维码 → 手机 UU App 扫码
bash $G/scripts/09-clickbtn.sh && ls -l ~/.local/state/uu-deepin-port/login.png

# 7) 开机自启
systemctl --user enable uu-remote-bridge.service
```

---

## 二、日常使用命令

```bash
rrs                    # 重启桥接服务（= uurr）
rrx                    # 重启 + 中继窗口重新置顶 + 报告 → ~/uu-stack.txt
rrd                    # 只看窗口堆叠 → ~/uu-stack.txt
rrp                    # 抓私有屏画面（客户端视角）→ ~/uu-before.png / ~/uu-after.png
uurec                  # 抓登录二维码 → login.png
uurec 等价于： bash $G/scripts/09-clickbtn.sh

# 状态
systemctl --user status uu-remote-bridge.service --no-pager | head -8
systemctl --user is-active  uu-remote-bridge.service
cat $BR/private-display                  # 私有屏号（实测 :20）
ls  $BR                                  # Xauthority / private-display / x11-input.port / x11-clipboard.port / terminal.port / console-focus
```

---

## 三、核心路径一览

| 用途 | 路径 |
|---|---|
| 桥接仓库 | `~/Desktop/uu-remote-ubuntu-bridge`（分支 `deepin-port`） |
| 服务实际运行的脚本 | `~/.local/bin/uu-remote-bridge` ← **独立拷贝，改仓库后必须覆盖这里** |
| systemd 用户单元 | `~/.config/systemd/user/uu-remote-bridge.service` |
| 环境变量（开关都在这） | `~/.config/uu-remote-bridge/environment` |
| VNC 中继密码 | `~/.config/uu-remote-bridge/relay-vnc.pass` |
| Wine 前缀 | `~/.local/share/wineprefixes/uu-remote` |
| Wine 侧 compat 组件 | `$P/compat/`（`uu-input-bridge.dll`、`uu-input-broker.exe`、`uu-x11-input`、`uu-cursor-guard.dll` …） |
| UU 程序目录 | `$P/drive_c/Program Files/Netease/GameViewer` |
| UU 官方安装包（离线备用） | `$REPO/build/downloads/uu-4.42.1.2835.exe` |
| 私有屏 X 授权 | `$BR/Xauthority` |
| 桥接状态日志目录 | `~/.local/state/uu-remote-bridge/` |

---

## 四、日志速查

| 文件 | 内容 | 什么时候看 |
|---|---|---|
| `$P/drive_c/users/$U/AppData/Local/Temp/uu-input-bridge.log` | **DLL 侧**：每条输入的 `route=broker/direct`、`result`、`error` | 排查点击/打字为什么不生效 |
| `$P/drive_c/users/$U/Temp/uu-input-broker.log` | **broker 侧**：`keyboard-route=x11` banner、每条事件的 `route=x11*` | 确认是否真的注入到 X |
| `$P/drive_c/users/$U/AppData/Local/Temp/uu-cursor-guard.log` | 光标守护是否激活 | 客户端看不到指针时 |
| `~/.local/state/uu-remote-bridge/vncviewer-relay.log` | TigerVNC 中继查看器输出 | 中继窗口起不来 |
| `~/.local/state/uu-remote-bridge/desktop-x11vnc.log` | x11vnc 抓屏 | 画面黑/卡 |
| `~/.local/state/uu-remote-bridge/x11-input.log` | X11 输入助手 | 注入失败 |
| `~/.local/state/uu-remote-bridge/openbox.log` | 私有屏窗口管理器 | 窗口认不到 |
| `~/.local/state/uu-deepin-port/*.log` | 指南各脚本的输出（`recover.log` / `diag.log` / `raise.log` / `inputtest.log` / `login.png` …） | 排查记录 |

常用过滤：

```bash
# 键盘/鼠标各自走了哪条路
grep 'category=keyboard' $P/drive_c/users/$U/Temp/uu-input-broker.log | tail -5
grep 'category=mouse'    $P/drive_c/users/$U/Temp/uu-input-broker.log | tail -5
# 统计
grep 'category=keyboard' $P/drive_c/users/$U/Temp/uu-input-broker.log \
  | sed 's/.*route=\([a-z0-9-]*\).*/\1/' | sort | uniq -c
```

---

## 五、诊断 / 修复脚本（`$G/scripts/`）

| 脚本 | 用途 | 输出 |
|---|---|---|
| `01-prep.sh` | root：系统依赖 + Wine 11 | 屏幕输出 |
| `01b-i386.sh` | ❌ **失败路线留档，勿执行** | — |
| `02-install.sh` | 调官方 install.sh（VNC 中继参数） | 屏幕输出 |
| `03-seed-prefix.sh` | 建前缀 + 种子 UU 文件 | 屏幕输出 |
| `04-open.sh` | 拉起 UU 管理窗口（openbox/客户端自愈） | `$LOG/window-open.log` |
| `05-recover.sh` | 恢复 + 输入链路诊断 | `recover.log` |
| `06-diag.sh` | :20 诊断（进程/窗口/映射状态） | `diag.log` |
| `07-raise.sh` | 把 UU 窗口置顶并验证 | `raise.log` |
| `08-inputtest.sh` | 在 :20 上对按钮做 XTEST 点击测试 | `inputtest.log` |
| `09-clickbtn.sh` | 抓登录二维码 | `login.png` |

> `05-recover.sh` 是最常用的"一把救回来"脚本：补客户端 → 补 openbox → 重建投屏 → 打印输入链路诊断。
> 它**不会重启服务**，所以不会断你当前的远程会话。

---

## 六、自测工具（`$G/tools/`）

不依赖手机/客户端，直接模拟一个 VNC 客户端连到本机中继端口，发点击/拖拽，用来判断"是本机链路坏，还是上游客户端的问题"：

```bash
python3 $G/tools/vnc-click-test.py     # 发一次点击
python3 $G/tools/vnc-drag-test.py      # 发一次拖拽
# 运行后立刻从 :0 截图对比效果：
DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority \
  ffmpeg -hide_banner -loglevel error -f x11grab -video_size "$RES" \
         -i :0.0 -frames:v 1 -y /tmp/after.png
```

手工看某块屏幕（**不要用 `-grab_x/-grab_y`，用 `:0.0+X,Y` 这种写法**）：

```bash
export DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority
ffmpeg -f x11grab -video_size "$RES" -i :0.0 -frames:v 1 -y /tmp/full.png           # 真实桌面（加 -draw_mouse 1 可带光标）
export DISPLAY="$DISP" XAUTHORITY=$BR/Xauthority                                    # 私有屏（客户端看到的）
ffmpeg -f x11grab -video_size "$RES" -i "$DISP.0" -frames:v 1 -y /tmp/relay.png
```

---

## 七、重新编译 / 部署（改源码后必做）

```bash
# ① 全量重编 compat（推荐）
cd $REPO && SOURCE_DATE_EPOCH=1 bash scripts/build-compat.sh build/compat

# ①' 只改 uu_input_bridge.c 时单文件重编（快）
cd $REPO && SOURCE_DATE_EPOCH=1 x86_64-w64-mingw32-gcc -std=c11 -O2 -Wall -Wextra -Werror \
    -Wl,--no-insert-timestamp -shared -o build/compat/uu-input-bridge.dll src/uu_input_bridge.c -luser32 \
  && x86_64-w64-mingw32-strip build/compat/uu-input-bridge.dll

# ② 部署到 Wine 前缀
cp $REPO/build/compat/uu-input-bridge.dll $P/compat/uu-input-bridge.dll
chmod 755 $P/compat/uu-input-bridge.dll

# ③ 改过桥接主脚本的话，覆盖运行位置
cd $REPO && bash -n scripts/uu-remote-bridge \
  && cp scripts/uu-remote-bridge ~/.local/bin/uu-remote-bridge && chmod 755 ~/.local/bin/uu-remote-bridge

# ④ 重启
rrs

# ⑤ 校验：构建产物与部署文件的哈希要一致
sha256sum $REPO/build/compat/uu-input-bridge.dll $P/compat/uu-input-bridge.dll
```

---

## 八、关键开关（`~/.config/uu-remote-bridge/environment`）

| 变量 | 本机取值 | 作用 / 注意 |
|---|---|---|
| `UURB_DESKTOP_RELAY` | `vnc` | 中继方案，Deepin 下必须是 `vnc` |
| `UURB_DESKTOP_TARGET` | `:0` | 被控的真实桌面 |
| `UURB_KEYBOARD_ROUTE` | `x11` | ★ 键盘走 X11；改成 `rdp` 会导致电脑端打不了字 |
| `UURB_INPUT_ROUTE` | `x11` | ★ 鼠标走 X11（本移植新增，DLL 默认已是走 broker）；`direct` 才会退回 Wine |
| `UURB_CURSOR_GUARD` | `on` | ★ 让电脑客户端能看到鼠标指针（默认 `off`） |
| `UURB_VNC_GRAB_KEYBOARD` | `on` | x11vnc 抓键盘 |
| `UURB_PHYSICAL_KEY_DELAY_MS` | `0` | 按键节奏；若个别应用漏键可试着调到 `8~20` |

> `config/environment` 里的 `UURB_RESOLUTION=1920x1200` 是**本机实测分辨率**，换机后按 `xrandr` 的真实值改。
| `UURB_TEXT_KEY_DELAY_MS` | `8` | 手机文本逐字符节奏 |

改完必须 `rrs` 重启才生效。

---

## 九、终端输入的坑（很关键）

在终端里敲命令时：

1. **先确认搜狗输入法是英文态**——中文态会把命令吞成候选词（`rrs` → 弹"仍然是/日顺/热热身"）；
2. 判定方法：**输入后看是否原样回显**（托盘图标太小，不可靠）；
3. 切英文：`Esc` 取消组字 → 按 `Shift`；
4. 自动化注入时：用 `xdotool key ctrl+u` 先清空当前行，`xdotool type --delay 50 -- '命令'`，最后 `xdotool key Return`；
5. 剪贴板粘贴（`ctrl+shift+v`）在终端里**不可靠**（xclip 的持有进程容易被回收），不如直接 `type`。
