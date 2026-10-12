# 网易UU远程 · Deepin 25 适配安装指南

> 记录时间：2026-10-11 ~ 2026-10-12
> 记录对象：在 **Deepin 25 (DDE)** 上把官方桥接项目 `uu-remote-ubuntu-bridge`（原本面向 Ubuntu 24.04 + GNOME + gnome-remote-desktop + FreeRDP）移植并完整跑通的全过程。
> 用途：以后重装系统 / 换机器 / 升级后重新部署，照着这份文档一步步做即可复现。
> 本目录已把脚本、配置、补丁、预编译组件、自测工具全部收齐，离线也能照着做。
> **日常用（重启后恢复、重新登录）：直接看 [`QUICKSTART.md`](QUICKSTART.md)，一页搞定，不用翻本文。**

---

## 一、做完之后能实现什么

- 本机作被控端，**手机 App** 和**另一台电脑的 UU 客户端**都能连上并看到**真实桌面**（不是虚拟空桌面）；
- 鼠标移动、左键/右键点击、滚轮、窗口右上角按钮、任务栏图标、拖拽全部可用；
- **物理键盘**（电脑客户端打字）和**文本/中文输入**（手机端）都能落到真实桌面；
- 客户端画面里**能看到鼠标指针**（电脑客户端不再是一片"没有鼠标"）。

---

## 二、整体架构（先看懂这张图，后面所有坑都源于它）

```
                   ┌───────────────── 被控机 Deepin 25 ─────────────────┐
                   │                                                   │
  手机 App /       │   真实桌面 :0 (DDE 1920x1200)                      │
  电脑 UU 客户端   │        │  画面                                     │
     │             │        ▼  ①下行                                    │
     │             │   x11vnc（抓 :0） ───► 127.0.0.1:5922 ─┐           │
     │             │                                        ▼           │
     │             │   私有显示 :20（Xvfb + openbox 窗口管理器）          │
     │             │     ├─ TigerVNC viewer（全屏，播放 127.0.0.1:5922） │
     │             │     └─ Wine 11 里的 UU 服务端：                     │
     │             │          GameViewerServer.exe + GameViewer.exe      │
     │             │          （UU 捕获 :20 整屏 → 编码 → 上报服务器）    │
     │             │                                                   │
     │             │   ②上行：客户端鼠标/键盘 → UU 服务端               │
     │             │        → uu-input-bridge.dll（钩 SendInput）        │
     │             │        → uu-input-broker.exe（命名管道）            │
     │             │        → uu-x11-input → XTEST → 注入 :0             │
                   └───────────────────────────────────────────────────┘
```

**一句话原理**：Wine 里的 UU 只能"看见"Wine 自己的窗口。于是让它全屏盯着一个**Linux 版 TigerVNC 窗口**（窗口内容就是真实桌面 :0）。因为那个窗口不是 Wine 窗口，**任何交给 Wine 去投递的输入都会"假成功真丢失"**，所以鼠标、键盘、文本**全部必须绕过 Wine，走 broker → XTEST 直接注入 :0**。

三种输入对应三条通道（都在 broker 里汇合）：

| 输入类型 | 路径 | 说明 |
|---|---|---|
| 指针移动 | broker → `uu-x11-input` → XTEST 注入 :0 | 走鼠标通道 |
| 鼠标按键/滚轮 | broker → `uu-x11-input` → XTEST 注入 :0 | 默认走 broker（可用 `UURB_INPUT_ROUTE=direct` 退回 Wine） |
| 物理键盘（电脑端打字） | broker → `uu-x11-input` → XTEST 注入 :0 | 默认走 broker（可用 `UURB_KEYBOARD_ROUTE=direct` 退回 Wine） |
| 手机端文本/中文 | broker → `uu-x11-clipboard`（剪贴板 + 粘贴） | 手机文本走语义通道 |
| 光标形状 | `uu-cursor-guard.dll` 注入 GameViewerServer.exe | 兜底上报 48x48 标准箭头 |

---

## 三、本机实测环境

| 项目 | 版本 / 路径 |
|---|---|
| 系统 | Deepin 25（codename `crimson`），内核 `6.6.155-amd64-desktop-hwe`，x86_64 |
| 桌面 | DDE（Deepin Desktop Environment），分辨率 1920x1200 |
| Wine | **WineHQ Wine 11.0**，`/opt/wine-stable/bin/wine` |
| Wine 前缀 | `~/.local/share/wineprefixes/uu-remote` |
| UU 程序目录 | `~/.local/share/wineprefixes/uu-remote/drive_c/Program Files/Netease/GameViewer` |
| UU 版本 | **4.42.1.2835**（哈希已与 `patches/uu-remote-4.42.1.2835.json` 核对一致） |
| UU 文件来源 | 从本机已有的 Spark Wine 应用前缀 `~/.deepinwine/Spark-potplayer/.../Netease/GameViewer` 拷贝（**种子方案**，绕过 32 位官方安装器） |
| 桥接仓库 | `~/Desktop/uu-remote-ubuntu-bridge`，分支 `deepin-port` |
| VNC | TigerVNC viewer **1.15.0**（中继查看器）、x11vnc 0.9.16（抓屏） |
| 窗口管理器 | Openbox 3.6.1（跑在私有屏 :20 上） |
| 交叉编译 | `x86_64-w64-mingw32-gcc` (GCC 13-win32) |
| 用户服务 | `uu-remote-bridge.service`（systemd --user） |
| 环境变量文件 | `~/.config/uu-remote-bridge/environment` |

---

> 这张表是**本机实测值**，只作参考：脚本里**没有任何写死值依赖它们**（用户名 / UID / 主机名 / 分辨率 / 私有屏号都是运行时探测，其余可配置项见下一节）。

---

## 三·补、本机前置条件（换机 / 重装后逐条确认）

下表左列是本机实际情况，右列是"换成别的怎么办"。带 ★ 的是**必须你自己准备、脚本无法自动搞定**的。

| 项目 | 本机取值 | 能否替换 | 处理方式 |
|---|---|---|---|
| 系统 / 架构 | Deepin 25 (crimson)，x86_64，内核 6.6.155 | 需 Debian 系 + X11 | 非 Deepin 也能用，但 `01-prep.sh` 里对 deepin 源的 `sed` 要按发行版改 |
| glibc | **2.38** | 需 ≥ 2.36 | i386 运行库只有 2.36 → **必须走"种子前缀"**，别试官方 32 位安装器 |
| 桌面会话 | DDE（**X11** 会话），真实桌面 `:0` | 可换 | `DESKTOP_TARGET`（默认 `:0`）；**Wayland 会话下 `:0` 不成立，需先切 X11** |
| 用户名 / 家目录 | `fengjie` / `/home/fengjie` | 随便换 | 脚本统一用 `$(id -un)` / `$HOME`；Wine 前缀内路径是 `drive_c/users/<用户名>`，其中用户名 = **建前缀时**的 Linux 用户名（`uurb_wine_user`） |
| UID | `1000` | 随便换 | 一律 `/run/user/$(id -u)` |
| 主机名 | `fengjie-PC` | 随便换 | 只出现在 TigerVNC 窗口标题（`<主机名>:0 - TigerVNC`）；匹配窗口时**只用 `TigerVNC` 关键字**，不要按主机名匹配 |
| 桌面分辨率 | `1920x1200` | 随便换 | `RESOLUTION=auto` 时用 `xrandr` 探测；`config/environment` 里的 `UURB_RESOLUTION` 需自己同步一下 |
| 私有屏号 | `:20`（桥接自选） | 随便换 | 读 `$BR/private-display`，脚本不再写死 `:20` |
| Wine | WineHQ **Wine 11** → `/opt/wine-stable` | 需 11.x | `WINE_BIN` / `WINESERVER_BIN`（`01-prep.sh` 会装） |
| 桥接仓库位置 | `~/Desktop/uu-remote-ubuntu-bridge`（分支 `deepin-port`） | 随便换 | `REPO_DIR` |
| 指南目录位置 | `~/Desktop/uu-remote-deepin-guide` | 随便换 | 脚本按自身位置自动探测；`bin/uurec` 可用 `UURB_GUIDE_DIR` 显式指定 |
| 脚本输出目录 | 原来在 AI 会话目录 `~/WorkBuddy/Claw/uu-deepin-port` | 随便换 | 已改到 `LOG_DIR` = `~/.local/state/uu-deepin-port` |
| ★ **UU 文件（种子源）** | `~/.deepinwine/Spark-potplayer/…/Netease/GameViewer` | **必须自备** | `SEED_SRC`：需要一份 **UU 4.42.1.2835** 的 `GameViewer` 目录（版本与哈希见 `prebuilt/release-manifest.json`）。本机是从 Spark 商店版 potplayer 前缀里拿的；换机若没有现成的，就得自己搞到官方安装包再解开 |
| ★ 中继密码 | `uu123456`（示例） | 建议换掉 | `RELAY_PASS`；只是本地回环 `127.0.0.1:5922` 的口令 |
| ★ root / sudo | 有 | 必须有 | 步骤 1 装依赖 |
| ★ `systemd --user` | 可用 | 必须有 | 桥接跑在用户服务里 |

**换机自检（逐条跑一遍）**：

```bash
id -un; id -u; hostname                  # 用户名 / UID / 主机名
echo "$DISPLAY"                          # 会话显示号（DDE X11 会话通常 :0）
xrandr --current | grep '\*'             # 真实分辨率
/opt/wine-stable/bin/wine --version      # 期望 wine-11.x
ls "$SEED_SRC/bin" | wc -l               # ★ 种子源是否存在（见上表）
systemctl --user is-active uu-remote-bridge.service
cat "/run/user/$(id -u)/uu-remote-bridge/private-display"   # 私有屏号
```

> 以上凡是"可配置"的项，都在 `config/guide.env` 里有默认值，也可以用环境变量临时覆盖，例如：
> `REPO_DIR=~/src/uu-remote-ubuntu-bridge RESOLUTION=2560x1600 bash scripts/02-install.sh`

---

## 四、安装步骤（按顺序执行）

### 步骤 0 · 准备仓库与分支

```bash
cd ~/Desktop
git clone https://github.com/lachlanchen/uu-remote-ubuntu-bridge.git   # 若还没有
cd uu-remote-ubuntu-bridge
git checkout deepin-port      # 本机已存在的适配分支
```

> 如果你拿到的是**干净的上游 main**，没有 `deepin-port` 分支，则用本目录 `patches/` 里的补丁打上：
> ```bash
> cd ~/Desktop/uu-remote-ubuntu-bridge
> git checkout -b deepin-port
> git am <指南目录>/patches/*.patch        # <指南目录> = 你放这份指南的地方，例如 ~/Desktop/uu-remote-deepin-guide
> ```
> 这 6 个提交就是本机相对上游的全部改动（见文末"改动清单"）。

若是**离线/没有网络**：本机的 UU 官方安装包在 `$REPO_DIR/build/downloads/uu-4.42.1.2835.exe`（约 90 MB）；不过本指南走的是"种子前缀"方案，其实用不到它（见步骤 2）。

---

### 步骤 1 · 系统依赖（需要 root / sudo）

```bash
cd <指南目录>
sudo bash scripts/01-prep.sh              # 或 sudo bash <指南目录>/scripts/01-prep.sh
```

它做 6 件事：
1. 把 deepin 源限制为 `arch=amd64`（避免加 i386 后 404）；
2. `dpkg --add-architecture i386`；
3. 安装 WineHQ **bookworm** 源与密钥；
4. `apt-get update`；
5. 安装桥接依赖：`aria2 cmake meson ninja-build gcc gcc-mingw-w64-x86-64 freerdp3-x11 tigervnc-viewer x11vnc xauth xclip xdotool xvfb openbox python3 jq …`；
6. 安装 **WineHQ stable（Wine 11）** → `/opt/wine-stable`。

验证：
```bash
/opt/wine-stable/bin/wine --version     # 期望：wine-11.0
which vncviewer x11vnc xdotool wmctrl   # 都应存在
```

> ⚠️ **不要走 `01b-i386.sh`**。那是失败路线的记录：Deepin 的 glibc 是 2.38，而 Debian bookworm 的 i386 库是 2.36，装不上，官方 32 位安装器因此跑不起来。本指南用"种子前缀"绕过它。`01b-i386.sh` 只作留档，不要执行。

---

### 步骤 2 · 建 Wine 前缀并"种子"UU 文件（当前登录用户）

```bash
cd <指南目录>
bash scripts/03-seed-prefix.sh           # 种子源由 config/guide.env 的 SEED_SRC 指定
```

它做 4 件事：
1. 删掉并重建 `~/.local/share/wineprefixes/uu-remote`；
2. `wineboot -u` 初始化（64 位构建会报 syswow64 警告，属正常）；
3. `winecfg -v win10` 设为 Windows 10；
4. 把**已认证的 UU 4.42.1.2835** 从 `~/.deepinwine/Spark-potplayer/drive_c/Program Files/Netease/GameViewer` 拷进新前缀。

验证：
```bash
ls ~/.local/share/wineprefixes/uu-remote/drive_c/Program\ Files/Netease/GameViewer/bin | wc -l   # 应 > 0
```

> 若你机器上没有那份 Spark 前缀（没有现成 UU 文件），就得先搞到 4.42.1.2835 的原版文件放进新前缀——这一步是"绕开 32 位安装器"的关键，请务必保证版本与 `patches/uu-remote-4.42.1.2835.json` 一致。

---

### 步骤 3 · 运行桥接安装器（普通用户，**必须在本机真实桌面的终端里跑**）

脚本：`<指南目录>/scripts/02-install.sh`，核心命令是：

```bash
cd ~/Desktop/uu-remote-ubuntu-bridge
printf 'uu123456\nuu123456\n' | ./install.sh \
    --skip-packages \
    --skip-account-login \
    --desktop-relay vnc \
    --desktop-target :0 \
    --display auto \
    --resolution 1920x1200
```

各参数含义：
- `--skip-packages`：依赖已在步骤 1 装好，跳过 apt 环节；
- `--desktop-relay vnc`：**关键**，用 VNC 中继方案（而不是上游默认的 RDP/FreeRDP）；
- `--desktop-target :0`：把真实桌面 :0 作为被控目标；
- `--display auto`：私有屏从 :20 起自动选一个空闲的；
- `--resolution 1920x1200`：中继分辨率（与真实分辨率同）；
- `printf 'uu123456\nuu123456\n'`：给 VNC 中继设的密码（同一行喂两次），最终落在 `~/.config/uu-remote-bridge/relay-vnc.pass`。

安装器内部会：
1. 检测到前缀里已有 `GameViewer.exe` → **跳过下载与运行官方安装器**；
2. 用 `scripts/patch-gameviewer.py` + `patches/uu-remote-4.42.1.2835.json` 给 `GameViewerServer.exe` 打补丁；
3. 用 `scripts/build-compat.sh` 编译全部 compat 组件到 `build/compat/`，并安装到 `$WINEPREFIX/compat/`；
4. 安装 `~/.local/bin/` 下的命令、写 `~/.config/uu-remote-bridge/environment`、装 systemd user 单元；
5. 启动 `uu-remote-bridge.service`。

验证：
```bash
systemctl --user is-active uu-remote-bridge.service       # 期望 active
ls /run/user/$(id -u)/uu-remote-bridge/                   # 应有 private-display / Xauthority / x11-input.port
pgrep -x GameViewerServer.exe
ss -ltn | grep 5922                                       # x11vnc 中继端口
```

---

### 步骤 4 · 覆盖为本机验证过的配置并重启

```bash
mkdir -p ~/.config/uu-remote-bridge
cp <指南目录>/config/environment ~/.config/uu-remote-bridge/environment
systemctl --user restart uu-remote-bridge.service
```

`environment` 内容与逐项解释：

```ini
UURB_RDP_PORT=3390                 # RDP 端口（vnc 模式下不使用，保留默认）
UURB_RESOLUTION=1920x1200          # 中继分辨率
UURB_FOLLOW_DESKTOP_RESOLUTION=off # 不跟随桌面分辨率变化
UURB_DISPLAY=auto                  # 私有屏自动选择（实测选中 :20）
UURB_DESKTOP_TARGET=:0             # 被控的真实桌面
UURB_DESKTOP_RELAY=vnc             # 中继方案：vnc（我们用的）
UURB_VNC_GRAB_KEYBOARD=on          # x11vnc 抓取键盘
UURB_GRD_FD_RESTART_THRESHOLD=4096 # 原 GNOME 方案遗留参数，vnc 模式下无作用
UURB_TEXT_KEY_DELAY_MS=8           # 手机文本逐字符节奏
UURB_PHYSICAL_KEY_DELAY_MS=0       # 物理按键节奏（0 = 不额外延迟）
UURB_KEYBOARD_ROUTE=x11            # ★ 键盘走 X11 直连（不要改成 rdp）
UURB_INPUT_ROUTE=x11               # ★ 鼠标走 X11 直连（本移植新增，默认已是 x11）
UURB_PHONE_TEXT_MODE=auto          # 手机文本：能按键就按键，否则剪贴板
UURB_NETWORK_INTERFACE=all         # 网卡选择
UURB_CURSOR_GUARD=on               # ★ 光标守护：让电脑客户端能看到指针（默认 off）
UURB_CURSOR_SIZE=auto              # 光标尺寸自动
UURB_CONSOLE_VNC_PORT=5920         # 本机管理窗口用的 noVNC 旁路端口
UURB_CONSOLE_WEB_PORT=6080         # 同上（web）
```

> 打 ★ 的四项是本移植的关键配置：**少了任何一个都会复现"点不动 / 打不了字 / 看不到指针"**。

---

### 步骤 5 · 首次登录（扫二维码）

服务起来后，UU 客户端窗口在私有屏 :20 上（你会在真实桌面看到的那个 "UU Remote - TigerVNC" 窗口里）。

获取登录二维码（登录窗标题是 `GameViewer`）：

```bash
# 抓登录窗二维码（脚本会自己按登录窗的实时几何截取，不写死坐标）
bash <指南目录>/scripts/09-clickbtn.sh
# 结果在 ~/.local/state/uu-deepin-port/login.png，直接打开看就行
```

用手机 **网易UU远程 App** 扫码登录（二维码 1-2 分钟过期；过期就在窗口里点"点击刷新"再抓一次）。
登录成功后，UU 客户端主窗会变成"本机被控中"。

---

### 步骤 6 · 验收清单（逐条打勾）

```bash
# ① 服务在跑
systemctl --user status uu-remote-bridge.service --no-pager | head -5

# ② 私有屏与状态文件就绪
cat /run/user/$(id -u)/uu-remote-bridge/private-display        # 期望 :20（换机可能是别的号）
ls /run/user/$(id -u)/uu-remote-bridge/                        # Xauthority / x11-input.port / …

# ③ Wine 侧进程
pgrep -x GameViewerServer.exe ; pgrep -x gameviewer.exe    # 注意客户端进程名是小写

# ④ 中继链路
ss -ltn | grep 5922                                        # x11vnc 在听
# 真实桌面上应有一个全屏的 “TigerVNC” 窗口（手机看到的就是它）

# ⑤ 输入路由是否生效（最关键）
tail -3 ~/.local/share/wineprefixes/uu-remote/drive_c/users/$(id -un)/Temp/uu-input-broker.log
#   期望 banner： keyboard-route=x11
#   期望事件行： category=keyboard … route=x11
#              category=mouse    … route=x11-mouse

# ⑥ 光标守护是否生效
cat ~/.local/share/wineprefixes/uu-remote/drive_c/users/$(id -un)/AppData/Local/Temp/uu-cursor-guard.log
#   期望： UU cursor reader guard active (cursor 48x48)
```

然后从手机 / 电脑客户端连上去，依次验证：**画面 = 真实桌面** → **点窗口按钮** → **点任务栏** → **打字** → **看到鼠标指针**。

---

### 步骤 7 · 开机自启

```bash
systemctl --user enable uu-remote-bridge.service
```

---

## 五、日常使用

1. **连接**：手机 App / 电脑客户端登录同一 UU 账号 → 设备列表 → 连接本机；
2. **断开重连**：随时断开重连都行，服务不用重启；
3. **重启桥接服务**（会断开当前会话，需重连）：

   ```bash
   rrs          # = ~/.local/bin/rrs，最省事（内部会 export XDG_RUNTIME_DIR / DBUS 再 systemctl --user restart）
   ```

   > 注意：**在终端里手敲命令时，务必确认搜狗输入法是英文态**。中文态会把命令吞成候选词（例如 `rrs` → 弹出"仍然是/日顺/热热身"）。判定方法：输入后用截图看是否原样回显；切换方法是按一下 `Shift`（必要时先 `Esc` 取消组字）。

4. **一键排障工具**（都在 `~/.local/bin/`，你也可以直接用本目录 `bin/` 里的副本）：

   | 命令 | 作用 |
   |---|---|
   | `rrs` / `uurr` | 重启桥接服务 |
   | `rrx` | 重启服务 + 把中继窗口重新置顶 + 写报告到 `~/uu-stack.txt` |
   | `rrd` | 只 dump 私有屏 :20 的窗口堆叠顺序到 `~/uu-stack.txt` |
   | `rrp` | 抓私有屏画面（=客户端看到的画面）到 `~/uu-before.png` / `~/uu-after.png` |
   | `uurec` | 抓 :20 上的登录二维码到 `login.png` |

---

## 六、故障速查（详细版见 `TROUBLESHOOTING.md`）

> 只是「重启后怎么恢复」「登录失效怎么重登」这类日常问题，看 [`QUICKSTART.md`](QUICKSTART.md) 就够了。

| 症状 | 一句话原因 | 快速处理 |
|---|---|---|
| 手机/电脑看到一块 UU 自己的窗口，点不动也关不掉 | UU 管理窗压在 TigerVNC 中继之上 | 跑 `rrx`；长期靠已修的脚本自动置顶 |
| 能移动鼠标但**点不动** | 鼠标按键被交给 Wine（Wine 只投给自己的窗口） | 确认 `UURB_INPUT_ROUTE=x11`；DLL 已默认走 broker |
| 电脑客户端**打不了字** | 物理按键被交给 Wine | 确认 `UURB_KEYBOARD_ROUTE=x11`；DLL 已默认走 broker |
| 打了字只弹候选框 | 本机搜狗输入法是中文态 | 在 :0 上按 `Esc` 取消组字，再按 `Shift` 切英文 |
| 电脑客户端没有鼠标指针 | Wine 被控端未上报指针形状 | `UURB_CURSOR_GUARD=on` + 重启服务 |
| 看不到登录弹窗 / 黑框 | 投屏指向了已失效的窗口 | 跑 `04-open.sh` 或 `05-recover.sh` 重建投屏 |
| 服务反复起不来 | openbox 崩了 | 跑 `05-recover.sh`（内含 openbox 自愈） |
| 改了脚本没效果 | 服务跑的是 `~/.local/bin/uu-remote-bridge`（**独立拷贝**） | 必须 `cp` 覆盖到 `~/.local/bin/` 再重启服务 |

---

## 七、改动清单（相对上游 main）

分支 `deepin-port`，共 6 个提交（`patches/` 里就是这些补丁）。

> 补丁保留了**原提交的作者信息**（`fengjie <fengjie@local>`，即移植当时的本机账号），用 `git am` 打上后短哈希与上表一致、可直接核对。

| 提交 | 文件 | 内容 |
|---|---|---|
| `dbd1fc1` | `scripts/check-host.sh`、`install.sh`、`scripts/verify.sh` | 放行 Deepin 25 主机；支持**无 GNOME/grd 的 VNC 中继**；DDE 的 shell 探测 |
| `cdde48a` | `install.sh` | 容忍"拷贝种子"的前缀里没有 `drivers/devcon.exe` |
| `d5edc57` | `scripts/uu-remote-bridge`、`install.sh` | 适配 **TigerVNC 1.15** 的参数集与窗口标题 |
| `44b54cf` | `src/uu_input_bridge.c` | SendInput"假成功"（result==count 但 last-error≠0）时也走 broker 兜底 |
| `1924654` | `scripts/uu-remote-bridge`、`src/uu_input_bridge.c` | 中继窗口**无条件置顶**，压住 UU 管理窗；鼠标默认走 broker |
| `bda55a6` | `src/uu_input_bridge.c` | **物理键盘**默认走 broker（X11 直连） |

改动量（`git diff --stat main..deepin-port`）：

```
 install.sh               | 60 ++++++++++++++++-----------------
 scripts/check-host.sh    |  9 ++++++-
 scripts/uu-remote-bridge | 57 ++++++++++++++----------------------
 scripts/verify.sh        |  7 +++++-
 src/uu_input_bridge.c    | 64 ++++++++++++++++++++++++++++++++++++++--
```

### 修改源码后如何重新生效

```bash
# ① 改 src/uu_input_bridge.c 后单文件重编（也可用仓库脚本 scripts/build-compat.sh 全量重编）
cd ~/Desktop/uu-remote-ubuntu-bridge
SOURCE_DATE_EPOCH=1 x86_64-w64-mingw32-gcc -std=c11 -O2 -Wall -Wextra -Werror \
    -Wl,--no-insert-timestamp -shared -o build/compat/uu-input-bridge.dll \
    src/uu_input_bridge.c -luser32
x86_64-w64-mingw32-strip build/compat/uu-input-bridge.dll

# ② 部署到 Wine 前缀的 compat 目录
cp build/compat/uu-input-bridge.dll \
   ~/.local/share/wineprefixes/uu-remote/compat/uu-input-bridge.dll
chmod 755 ~/.local/share/wineprefixes/uu-remote/compat/uu-input-bridge.dll

# ③ 改桥接主脚本后必须覆盖到 ~/.local/bin（服务跑的是这份拷贝！）
cp scripts/uu-remote-bridge ~/.local/bin/uu-remote-bridge
chmod 755 ~/.local/bin/uu-remote-bridge

# ④ 重启服务
rrs
```

---

## 八、本目录文件说明

```
uu-remote-deepin-guide/
├── README.md                  ← 本文（总览 + 安装步骤 + 验收）
├── QUICKSTART.md              ← ★ 极简日常手册（重启后恢复 / 登录失效重登）
├── DUAL-MONITOR.md            ← 双屏扩展时远端画面异常的原因与修复
├── TROUBLESHOOTING.md         ← 每个坑的现象 / 根因 / 修复（含日志证据）
├── COMMANDS.md                ← 命令与脚本速查、日志与状态文件路径
├── scripts/                   ← 按顺序执行的移植脚本
│   ├── 01-prep.sh             ← root：系统依赖 + Wine 11
│   ├── 01b-i386.sh            ← 【失败路线留档，勿执行】i386 尝试
│   ├── 02-install.sh          ← user：调用官方 install.sh（VNC 中继参数）
│   ├── 03-seed-prefix.sh      ← user：建前缀 + 种子 UU 文件
│   ├── 04-open.sh             ← 拉起 UU 管理窗口（含 openbox/客户端自愈）
│   ├── 05-recover.sh          ← 恢复 + 输入链路诊断，写 recover.log
│   ├── 06-diag.sh             ← :20 诊断（进程/窗口/映射状态）→ diag.log
│   ├── 07-raise.sh            ← 把 UU 窗口置顶并验证 → raise.log
│   ├── 08-inputtest.sh        ← 在 :20 上对按钮做 XTEST 点击测试
│   ├── 09-clickbtn.sh         ← 抓登录二维码（登录窗）→ login.png
│   └── gameviewer-service.reg ← Wine 服务注册表项（GameViewerService）
├── bin/                       ← 日常包装命令（拷到 ~/.local/bin 即可用）
│   ├── rrs / uurr             ← 重启桥接服务
│   ├── rrx                    ← 重启 + 重排窗口 + 报告
│   ├── rrd                    ← dump 私有屏窗口堆叠
│   ├── rrp                    ← 抓 :20 画面（客户端视角）
│   └── uurec                  ← 抓登录二维码
├── config/                    ← 直接可用的配置
│   ├── guide.env              ← ★ 统一变量（路径/密码/分辨率/种子源…脚本会自动读取）
│   ├── environment            ← ~/.config/uu-remote-bridge/environment
│   └── uu-remote-bridge.service ← ~/.config/systemd/user/ 下的单元文件
├── patches/                   ← deepin-port 相对上游 main 的 6 个提交（git am 可打）
├── prebuilt/                  ← 已编译好的 compat 组件（含打好补丁的 uu-input-bridge.dll）
└── tools/                     ← 自测工具（模拟 VNC 客户端验证中继的点击/拖拽）
    ├── vnc-click-test.py
    └── vnc-drag-test.py
```
