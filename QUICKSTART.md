# UU 远程 · 重启后快速恢复 & 重新登录

> 适用本机（Deepin 25 + Wine 里的 UU）。
> 下面命令都在**普通终端**里跑，不需要 root、也不需要 sudo。
> 下称 `$G` = 指南目录 = `~/Desktop/uu-remote-deepin-guide`

---

## 一、重启电脑后怎么恢复

### 正常情况下：什么都不用做

桥接服务 `uu-remote-bridge.service` 是 systemd **用户级**服务，已设置开机自启（关掉见下方速查表「停用远程」两行）。你登录图形桌面后它会自动：起私有屏 → 起 openbox → 拉起 UU 客户端 → 接管真实桌面 `:0`。

等 30～60 秒，手机 App / 另一台电脑用同一 UU 账号连本机，通常直接就能控。

> 只在**登录桌面之后**才启动；停在登录界面时连不上是正常的。

### 想在本机看到 UU 管理窗口时（要扫码、看设备列表）

```bash
bash ~/Desktop/uu-remote-deepin-guide/scripts/04-open.sh
```

或者直接双击桌面上的 **UU Remote** 图标（等 20～30 秒）。它只适合**看状态**（是否「本机被控中」、连着哪些设备），在这个窗口里点击基本无效；要登录用下面的 `uuqr`。

> 桌面上若还有一个叫 **UU远程**（不是 UU Remote）的图标，那是取种子时临时安装器留下的，指向另一份 UU，双击会抢账号——删掉它（`scripts/fetch-seed.sh` 现在会自动清理）。

这条是"一键自愈"：服务没起就起服务、openbox 掉了就补、客户端掉了就补、最后把管理窗口投到桌面。全程约 1 分钟，看到 `✅ UU 窗口已显示在桌面上` 就成了。

### 确认状态

```bash
uu-remote status        # 桥接服务状态，看到 active (running) 即正常
rrx                     # 重启服务 + 重排窗口 + 出报告（写到 ~/uu-stack.txt）
```

---

## 二、登录失效了怎么重新登录

**怎么判断**：UU 窗口里出现登录界面/二维码，或手机端设备列表里本机显示离线、点了没反应。

### 方式 1 · `uuqr` 一键出码（推荐）

```bash
uuqr            # 出二维码并在桌面打开
# 手机扫码登录成功后：
uuqr --done     # ★ 必做：恢复中继窗口
```

它会：临时隐藏私有屏上挡住点击的中继窗口 → 没有登录窗就点「立即登录」→ 点「点击刷新」→
把登录窗截成 `~/.local/state/uu-deepin-port/login.png` 并在桌面打开。

1. 手机 **网易UU远程 App** → 扫一扫 → 扫屏幕上的这张图
2. 二维码 **1～2 分钟就过期**，过期了再跑一次 `uuqr`
3. 登录成功后**一定要跑 `uuqr --done`**——不恢复中继，手机连上只能看到 UU 自己的窗口（黑底 + 「本机被控中」），看不到真实桌面

> 为什么不能直接在桌面的 UU 窗口里点：投屏窗口只抓 UU 主窗口，登录框是另一个窗口，投屏里看不到；
> 而且私有屏最上层是全屏中继，点击会被它转到真实桌面上（见 TROUBLESHOOTING 第 22 条）。

### 方式 2 · `uurec` 只抓不点

```bash
uurec
```

登录窗已经开着时，只把它截成 `login.png`。登录窗被中继压着时截到的可能不是二维码，这时用方式 1。

### ~~方式 3 · `uu-remote login`~~（本机不可用）

上游的 `uu-remote login` 在这里会**秒退**：它运行的顶层 `GameViewer.exe` 只是启动器，启动器一退出脚本就把 Wine 停了；
直接运行 `bin/GameViewer.exe` 客户端也会静默退出（见 TROUBLESHOOTING 第 23 条）。别用它，它还会停掉桥接。

---

## 三、出问题时的三步速查

1. `uu-remote status` —— 不是 active 就跑 `rrs`（重启服务，等 30 秒）
2. 还不行 → `bash $G/scripts/04-open.sh`（一键自愈）
3. 还不行 → 看日志：

```bash
~/.local/state/uu-deepin-port/window-open.log     # 管理窗口投屏
~/.local/state/uu-deepin-port/recover.log         # 自愈脚本
journalctl --user -u uu-remote-bridge -n 80 --no-pager
# 输入（点击/键盘）相关：
~/.local/share/wineprefixes/uu-remote/drive_c/users/$(id -un)/Temp/uu-input-broker.log
```

4. **远端画面不对**（双屏时像两屏叠在一起、或想只看笔记本屏）→ 中继现在**只送主屏**：

```bash
grep UURB_RELAY_CLIP ~/.config/uu-remote-bridge/environment   # 期望 auto
DISPLAY=:0 xrandr --listmonitors        # 带 * 的那块 = 主屏 = 远端能看到的屏
# 中继声明的帧尺寸应等于主屏尺寸（本机 1920x1200），而不是桌面总尺寸 1922x2280
grep rfbEncodingExtDesktopSize ~/.local/state/uu-remote-bridge/desktop-x11vnc.log | tail -1
```

改回"送整块桌面"：把 `UURB_RELAY_CLIP` 设成 `off` 再 `rrs`。原理与历史方案见 `DUAL-MONITOR.md`。

---

## 四、命令 / 路径速查

| 用途 | 命令 或 路径 |
|---|---|
| 打开 UU 管理窗口 | 桌面 `UU Remote` 图标，或 `uu-remote open` |
| 一键自愈（推荐） | `bash ~/Desktop/uu-remote-deepin-guide/scripts/04-open.sh` |
| 看服务状态 | `uu-remote status` |
| 重启桥接服务 | `rrs`（同 `uurr`） |
| 停用远程（立即） | `systemctl --user stop uu-remote-bridge` |
| 关开机自启 / 恢复 | `systemctl --user disable uu-remote-bridge` / `enable` |
| 重启 + 重排窗口 + 报告 | `rrx` → `~/uu-stack.txt` |
| 出登录二维码（推荐） | `uuqr` → 扫码 → `uuqr --done` |
| 只抓登录窗 | `uurec` → `~/.local/state/uu-deepin-port/login.png` |
| 看私有屏窗口层级 | `rrd` → `~/uu-stack.txt` |
| 截私有屏图 | `rrp` → `~/uu-before.png`、`~/uu-after.png` |
| 服务单元文件 | `~/.config/systemd/user/uu-remote-bridge.service` |
| 环境开关（路由/光标等） | `~/.config/uu-remote-bridge/environment` |
| 指南目录 | `~/Desktop/uu-remote-deepin-guide` |
| 详细文档 | `$G/README.md`、`$G/TROUBLESHOOTING.md`、`$G/COMMANDS.md` |

> 提醒：改指南目录里的脚本**不影响**正在跑的服务——服务用的是 `~/.local/bin/` 下那份独立拷贝，要生效得替换那份并重启服务。
