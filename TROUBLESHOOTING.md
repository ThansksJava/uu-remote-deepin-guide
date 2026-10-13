# 排障手册 —— 每一个坑：现象 / 根因 / 修复 / 验证

> 日常小问题（重启后恢复、重新登录）先看 [`QUICKSTART.md`](QUICKSTART.md)。
> 双屏 / 多显示器相关的问题（远端画面被裁、像两屏叠在一起）见 [`DUAL-MONITOR.md`](DUAL-MONITOR.md)。

> 按遇到的先后顺序记录。**每条都附了当时的判断依据与验证命令**，方便以后再遇到同类问题时快速定位。
> 相关日志路径见 `COMMANDS.md`。
>
> 下面所有命令都用这几个变量（**没有任何写死的用户名 / UID / 主机名 / 分辨率**）：
> ```bash
> P=~/.local/share/wineprefixes/uu-remote        # Wine 前缀
> U="$(id -un)"                                  # 前缀内的用户名 = 建前缀时的 Linux 用户名
> BR="/run/user/$(id -u)/uu-remote-bridge"       # 桥接运行时目录
> DISP="$(cat "$BR/private-display" 2>/dev/null || echo :20)"   # 私有屏号（桥接自动选，常见 :20）
> RES="$(DISPLAY="$DISP" XAUTHORITY="$BR/Xauthority" xdpyinfo 2>/dev/null \
>        | awk '/dimensions:/{print $2; exit}')"  # 该屏分辨率（本机为 1920x1200）
> ```

---

## 0. 一条总原则（记住它，能省掉一半排查时间）

> **私有屏（默认 :20）上那个中继窗口是 Linux 程序（TigerVNC），Wine 看不见它。**
> 所以**任何交给 Wine `SendInput` 去投递的输入都会"假成功真丢失"**（返回 `result=count`、`error=0`，但根本没送出去）。
> 一切输入必须走 `broker → uu-x11-input → XTEST → 真实桌面 :0`。

**排查任何"输入没反应"的第一步**，都是看这两个日志：

```bash
P=~/.local/share/wineprefixes/uu-remote
U="$(id -un)"
# ① 桥接 DLL 侧：这一步走了哪条路（route=broker / direct）
tail -5 $P/drive_c/users/$U/AppData/Local/Temp/uu-input-bridge.log
# ② broker 侧：真正注入到哪个 X 通道（route=x11 / x11-mouse / rdp）
tail -5 $P/drive_c/users/$U/Temp/uu-input-broker.log
grep -c 'category=keyboard' $P/drive_c/users/$U/Temp/uu-input-broker.log
```

- `route=direct` 且 `error=0` → 就是"假成功真丢失"，事件被 Wine 吞了；
- `route=x11*` → 走的是直连通道（正确）。

---

## 1. Deepin 装不了官方 32 位安装器（i386 死路）

- **现象**：官方 `install.sh` 在 Ubuntu 上会跑 UU 的 32 位安装器；在 Deepin 25 上前缀建不起来。
- **根因**：Deepin 25 的 glibc 是 **2.38**，而 Debian bookworm 提供的 i386 运行库是 **2.36**，`dpkg --add-architecture i386` 后即使装上也会因版本不匹配跑不起来（`01b-i386.sh` 就是这条失败路线的留档）。
- **修复**：改用**种子前缀**方案——用 WineHQ Wine 11 建一个全新 64 位前缀（`wineboot -u` + `winecfg -v win10`），然后把一份**已认证的 UU 4.42.1.2835 文件**整个拷进去。
  本机这份文件来自 `~/.deepinwine/Spark-potplayer/…/Netease/GameViewer`（Spark 商店版 potplayer 前缀），
  已抽成配置项 `SEED_SRC`（见 `config/guide.env`）——**换机时这是最需要确认的一条前置条件**。
  版本必须与 `prebuilt/release-manifest.json` 一致（安装器会校验哈希并给 `GameViewerServer.exe` 打补丁）。
- **验证**：
  ```bash
  sha256sum "$P/drive_c/Program Files/Netease/GameViewer/GameViewerServer.exe"  # 与 manifest 对比
  ls "$P/drive_c/Program Files/Netease/GameViewer/bin" | wc -l
  ```

---

## 2. 执行环境（自动化沙箱）看不到宿主：只能"借用户终端"

- **现象**：AI 侧执行 `systemctl --user`、看 `/run/user/$(id -u)`、访问私有屏全部失败（`Failed to connect to bus`、`没有那个文件或目录`），`/tmp` 也是私有的（**每次调用还会重建，后台进程活不过一轮**），`sudo/su/setpriv/crontab` 都不可用。
- **根因**：自动化工具的命令跑在受限命名空间里，与真实会话隔离。
- **对策**：通过 `xdotool` 往**用户桌面上已打开的终端窗口**里逐字键入命令（XTEST 真实按键），再截图确认。
  ```bash
  export DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority
  W=$(xdotool search --name "$(whoami)@$(hostname)" | head -1)   # 主机名不再写死
  xdotool windowactivate --sync $W; xdotool mousemove --window $W 500 300 click 1
  xdotool key ctrl+u                       # 清空当前行
  xdotool type --delay 50 -- 'rrs'; xdotool key Return
  ```
- **坑中坑**：终端输入会被**搜狗输入法**截走（见第 12 条）。另外 `xdotool key --window` 发的合成事件会被终端忽略，要用不带 `--window` 的 XTEST 方式。

---

## 3. 屏幕锁定 / 首次登录：需要解锁与扫码

- 锁屏状态下无法注入按键，需要先在本地解锁（密码由用户提供，**不要写进任何日志/脚本**）。
- 首次登录要在 UU 客户端窗口里扫码：`scripts/09-clickbtn.sh` 会**按登录窗的实际几何**截取二维码到 `~/.local/state/uu-deepin-port/login.png`（旧实现写死 808x608 @ 556,328，换机后位置一变就抓空）；
  二维码 1-2 分钟过期，过期就在窗口里点"点击刷新"再抓。

---

## 4. TigerVNC 1.15 参数不兼容 → 中继窗口起不来

- **现象**：`vncviewer-relay.log` 报参数不支持；中继窗口一直不出现。
- **根因**：上游脚本用的是 **RealVNC** 的参数集（`-AllowMainClose` 等），Deepin 装的是 **TigerVNC 1.15**。
- **修复**（`scripts/uu-remote-bridge`）：
  ```bash
  /usr/bin/env DBUS_SESSION_BUS_ADDRESS=unix:path=/dev/null \
      /usr/bin/vncviewer -FullScreen=1 -Shared=1 -SendPrimary=0 -MenuKey=f8 \
      "127.0.0.1:$desktop_vnc_display"
  ```
  并把窗口查找条件由 `--name '^TigerVNC viewer$'` 改为 `--name 'TigerVNC'`
  （**原因**：TigerVNC 连上后标题会变成 `<主机名>:0 - TigerVNC`，旧名字永远匹配不到；**别按主机名去匹配**）。

---

## 5. openbox 崩溃 → UU 窗口没有 WM_STATE → 全链路找不到窗口

- **现象**：`xprop -id <UU窗口> WM_STATE` 为空，脚本 `find_client_window` 失败。
- **根因**：私有屏上的 Openbox 崩过（例如某窗口没有 WM_STATE 属性时）。
- **修复**：`04-open.sh` / `05-recover.sh` 里已内置自愈——检测不到 `openbox` 进程就重新拉起：
  ```bash
  setsid env DISPLAY="$DISP" XAUTHORITY=$BR/Xauthority nohup /usr/bin/openbox >> openbox-restart.log 2>&1 &
  ```

---

## 6. 跑脚本后"没有登录弹窗" / 重启后"弹出黑框什么都看不见"

- **现象 A**：运行后看不到登录窗。
- **现象 B**：关掉重跑，弹出一个黑框，里面什么都没有。
- **根因**：
  - 桥接只在**服务启动那一刻**拉起一次客户端；客户端掉了不会自动重启 → 现象 A；
  - 投屏用的 `x11vnc -id <窗口>` 指向了**已经失效的窗口**，屏幕上就只剩一个黑框 → 现象 B。
- **修复**：
  1. `05-recover.sh` 会先清掉残留投屏单元、补起 `gameviewer.exe`（注意进程名是**小写**，见第 7 条）、补 openbox，再重建投屏；
  2. 重建投屏后必须把中继窗口抬到最上层（见第 9/10 条）。
- **验证**：`DISPLAY="$DISP" XAUTHORITY=$BR/Xauthority ffmpeg -f x11grab -video_size "$RES" -i "$DISP.0" -frames:v 1 shot.png` 看画面是否是桌面。

---

## 7. 进程名是小写 `gameviewer.exe`（踩了很多次）

- **现象**：`pgrep -x GameViewer.exe` 永远匹配不到，误判"客户端没起来"；同时旧的**冻结 GUI**（早先的僵尸进程）一直占着屏幕。
- **根因**：Wine 里客户端进程名是 **`gameviewer.exe`（小写）**，服务端才是 `GameViewerServer.exe`。
- **修复/用法**：
  ```bash
  pgrep -x gameviewer.exe     # 客户端（小写！）
  pgrep -x GameViewerServer.exe
  ```
  必要时 `kill <旧PID>` 后由 `05-recover.sh` 拉起一个干净的新实例。

---

## 8. 鼠标"能移动、但点不动"（第一个大坑）

- **现象**：指针能跟着动，hover 有高亮，但**点击无任何反应**（窗口按钮、任务栏都不行）。
- **日志证据**：`uu-input-bridge.log` 里鼠标**移动**全部成功，但**左键按下**（`flags=0xc002`）从某次调用起全部返回 `error=1400`（`ERROR_INVALID_WINDOW_HANDLE`）。
- **根因（两层）**：
  1. `uu_input_bridge.c` 里 `find_relay_window()` 硬编码 `FindWindowW(NULL, L"Ubuntu-Desktop-Relay")` —— 那是**官方 Ubuntu 方案**里 SDL FreeRDP 中继窗口的标题。我们换成 **Linux 版 TigerVNC** 后，Wine 的 `FindWindowW` **永远看不到这个窗口**，`SetForegroundWindow` 修复路径直接失效；
  2. 登录窗（`GameViewer`）关闭后 Wine 的前台句柄失效，之后 `SendInput` 就"假成功真失败"：返回 `result=count` 但 last-error=1400，把**按键事件静默丢弃**（移动不受前台影响，所以只有"点"坏）。
- **修复（两处一起做）**：
  1. **DLL 补丁**：`result != count || error != ERROR_SUCCESS` 时也走 broker 兜底（提交 `44b54cf`）；
  2. **鼠标默认走 broker**：`mouse_uses_broker()` 默认 true，只有 `UURB_INPUT_ROUTE=direct` 才退回 Wine 队列（提交 `1924654`）。
- **验证**：
  ```bash
  grep 'category=mouse' $P/drive_c/users/$U/Temp/uu-input-broker.log | tail -3
  # 期望：route=x11-mouse，result=1 error=0
  ```
  还可以用 `tools/vnc-click-test.py` / `tools/vnc-drag-test.py` **绕过手机/客户端**，直接模拟一个 VNC 客户端连中继端口发点击/拖拽，用来判断"是本机链路坏还是上游客户端的问题"（本机链路当时是好的）。

---

## 9. "点击明明成功了，却还是点不动" + UU 自己的窗口挡屏关不掉

- **现象**：手机上/客户端上看到一块 **"本机被控中"（网易UU远程）窗口**，点不动也关不掉（截图证据：260x55 的小提示窗 + 920x680 的主窗）。
- **根因（架构事实，不是 bug）**：
  - 那个窗口是 **UU 客户端自己**（`GameViewer.exe`），跑在 **Wine 的私有屏**上；
  - 而我们注入输入的目标是**真实桌面 :0**；
  - 私有屏和 :0 是两个不同的 X 服务器 → 那个窗口**天生点不到**，它等于"贴在摄像头前的一块挡板"。
  - 日志反证：`uu-input-bridge.log` 里 22 次左键按下/抬起全部 `route=broker result=1 error=0`；`uu-input-broker.log` 全部 `route=x11-mouse` —— **点击其实成功了，只是打在了看不见的 :0 上**。
- **修复思路**：不是去"修点击"，而是**让那块挡板永远沉到最下面**：
  1. 在 `scripts/uu-remote-bridge` 的聚焦监督逻辑里，把中继窗口**无条件** `xdotool windowraise`；
  2. 原来的判断有两个致命点：用旧标题 `'^TigerVNC viewer$'` 找窗口（找不到）；抬升条件要求 `getactivewindow` 非空——而私有屏上的 Openbox **不设焦点**，`getactivewindow` 恒为空 → **永远不抬**。
- **补充事实**：`网易UU远程` 主窗**不在 EWMH 窗口列表里**（`xprop -root _NET_CLIENT_LIST_STACKING` 看不到它），所以 `wmctrl -i -r <id> -b add,below` 对它无效，只能用 X 级的 `xdotool windowraise` 把中继压上去。
- **验证**：
  ```bash
  rrp     # 抓私有屏画面（=客户端看到的画面），应是干净的实时桌面
  rrd     # 看堆叠顺序，TigerVNC 应在最上层
  ```

---

## 10. 遮挡复发：**改了仓库脚本但没装到运行位置**

- **现象**：第 9 条修完之后，过一阵遮挡又出现了。
- **根因**：服务的 `ExecStart=%h/.local/bin/uu-remote-bridge`，而 `~/.local/bin/uu-remote-bridge` 是**独立拷贝**（不是指向 `<仓库>/scripts/` 的软链）。只改仓库那份 → 运行中的仍是旧逻辑。
- **修复/习惯**：
  ```bash
  cd "$REPO_DIR"                               # 默认 ~/Desktop/uu-remote-ubuntu-bridge
  bash -n scripts/uu-remote-bridge             # 先语法检查
  cp scripts/uu-remote-bridge ~/.local/bin/uu-remote-bridge && chmod 755 ~/.local/bin/uu-remote-bridge
  rrs                                          # 重启服务才生效
  ```
  （`cp` 成新文件再 `mv` 覆盖更安全：bash 按 fd 读脚本，替换文件不影响正在跑的实例。）
- **一句话**：**改仓库 ≠ 生效**。

---

## 11. 电脑客户端**打不了字**（第二个大坑）

- **现象**：手机端正常，电脑客户端连上后打字毫无反应。
- **日志证据**：`uu-input-bridge.log` 里 388 条 `category=keyboard` **全部 `route=direct`**（`result=1 error=0`，典型"假成功"），而 `uu-input-broker.log` 里 **0 条** keyboard。
- **根因**：`uu_input_bridge.c` 的桥接条件当时只有
  ```c
  if (unicode_keyboard || (mouse_input && mouse_uses_broker())) { … 走 broker … }
  ```
  **物理按键**（`type=1, flags=0/0x2`）不在其中 → 无条件走 `original_send_input` → 交 Wine 队列 → Wine 只投给自己的窗口 → 永远到不了 :0。
  （手机端之所以没暴露问题，是因为它发的是 **Unicode/剪贴板文本通道**，本来就走 broker。）
- **修复**：新增 `keyboard_uses_broker()`，**物理按键默认走 broker**（`UURB_KEYBOARD_ROUTE=direct` 才退回），提交 `bda55a6`。
- **验证**：
  ```bash
  grep 'category=keyboard' $P/drive_c/users/$U/AppData/Local/Temp/uu-input-bridge.log | tail -3   # 期望 route=broker
  grep 'category=keyboard' $P/drive_c/users/$U/Temp/uu-input-broker.log | sed 's/.*route=\([a-z0-9-]*\).*/\1/' | sort | uniq -c
  # 期望： 107 x11
  ```

---

## 12. "键盘通了但看起来还是打不了字"：宿主输入法把字母吃了

- **现象**：日志显示按键已经注入到 :0，但屏幕上只弹出候选框（例：远程敲 `qwerty`，终端出现 `qwertyyyyy` + 搜狗候选词），用户以为"键盘还是坏的"。
- **根因**：**宿主端 IME 状态会影响远程键入**。被控机搜狗处于**中文态**时，注入的字母会被当成拼音进组字，不落到程序里。
- **处理**：
  1. 在 :0 上按 `Esc`（取消组字）+ `Shift`（切英文）；
  2. 判定当前是否英文态最可靠的办法：**输入 `qwerty` 看是否原样回显**（托盘图标太小看不清）。
- **给使用者的提示**：远程打字前，先按一下（远端键盘的）`Shift` 把被控机切到英文；中文输入走手机端的文本通道最稳。

---

## 13. 电脑客户端画面里**没有鼠标指针**

- **现象**：手机 App 里正常，另一台电脑的 UU 客户端连上后，远端画面完全没有鼠标指针。
- **根因**：指针**形状**由被控端单独上报。Wine 里的 UU 服务读取指针形状时拿不到有效句柄 → 上报"没有指针"。手机 App 自己叠了一个触摸指针所以看不出来；电脑客户端老实等上报，就什么都不画。
- **修复**：桥接自带"光标守护"，默认关闭，打开即可：
  ```bash
  # ~/.config/uu-remote-bridge/environment
  UURB_CURSOR_GUARD=on
  systemctl --user restart uu-remote-bridge.service
  ```
  它会往 `GameViewerServer.exe` 注入 `uu-cursor-guard.dll`（钩 `GetCursorInfo/GetIconInfo`），兜底返回 `CURSOR_SHOWING` + 48x48 标准箭头。
  **注意**：VNC 模式下只注入 reader guard，不会去碰 `sdl-freerdp`（那条只在 RDP 分支），所以不会因为缺 FreeRDP 而启动失败。
- **代价**：极少数应用主动隐藏鼠标时，客户端也会画出一个箭头（对远控来说通常反而更好）。
- **验证**：
  ```bash
  cat $P/drive_c/users/$U/AppData/Local/Temp/uu-cursor-guard.log
  # 期望： UU cursor reader guard active (cursor 48x48)
  ```

---

## 14. 重启服务的方式（沙箱受限时的通用套路）

- 正常：`systemctl --user restart uu-remote-bridge.service`，或直接敲 `rrs`。
- 沙箱看不到用户总线时：往**用户已打开的终端**里注入命令（见第 2 条）。
- 记住两点：
  1. 敲命令前确认**英文输入法**；
  2. 重启会**断掉所有在连的会话**，需要客户端重连。

---

## 15. 双屏「扩展」时，远端画面像两个屏幕叠在一起

> ⚠️ **本条给出的「跟随桌面总尺寸」修复已于 2026-10-12 14:09 回退**：把整块桌面当画布后，客户端只能在窗口里等比缩小显示，画面与字体过小；拔掉扩展屏时也不能马上自适应。
> **现在的解法是第 16 条：把中继裁剪到单块显示器（默认主屏）**。完整记录见 [`DUAL-MONITOR.md`](DUAL-MONITOR.md)。

**现象**：笔记本外接一块屏、设为"扩展"后，远端客户端看到的画面里，
外接屏的内容和笔记本屏的内容糊在同一幅画里（其实是上下两块屏被裁到一张图上）。

**根因**：中继 x11vnc 抓的是**整个 root window**（两块屏合起来 1922×2280），
但私有屏 `:20` 的 Xvfb 画布是**安装当天按单屏写死的**（`UURB_RESOLUTION=1920x1200`）。
尺寸不一致时 TigerVNC **不缩放、只显示左上角** → 裁切。

**关键坑**：`xdotool getdisplaygeometry` 在多屏 Xinerama 下**只返回主屏尺寸**，
不是桌面总尺寸：

```bash
DISPLAY=:0 xdotool getdisplaygeometry      # → 1920 1200  ← 只报主屏
DISPLAY=:0 xdpyinfo | grep dimensions      # → 1922x2280  ← 真正的桌面总尺寸
```

所以**光打开 `UURB_FOLLOW_DESKTOP_RESOLUTION=on` 不会生效**（算出来和旧画布一样，
函数认为"无需改动"）。必须先把探测改成 `xdpyinfo`（见下面补丁），再打开开关。

**当时的修复（⚠️ 已于 2026-10-12 14:09 回退，仅作记录；原因与重新启用方法见 [`DUAL-MONITOR.md`](DUAL-MONITOR.md)）**：

```bash
# 1) 打补丁：scripts/uu-remote-bridge 的 desktop_geometry() 改用 xdpyinfo 读 root window
#    （该函数只在 UURB_FOLLOW_DESKTOP_RESOLUTION=on 时才会被用到）
cp -f ~/Desktop/uu-remote-ubuntu-bridge/scripts/uu-remote-bridge ~/.local/bin/uu-remote-bridge
bash -n ~/.local/bin/uu-remote-bridge && echo OK

# 2) 配置：跟随开 + 本次立即生效的尺寸（把画布改成桌面总尺寸）
#    UURB_RESOLUTION=<桌面总尺寸，如 1922x2280>
#    UURB_FOLLOW_DESKTOP_RESOLUTION=on

# 3) 重启
rrs
```

> 回退后这两行恢复为 `UURB_RESOLUTION=1920x1200` + `UURB_FOLLOW_DESKTOP_RESOLUTION=off`。

**验证**：

```bash
# ① GameViewer 自己上报的屏尺寸（最直接）
grep -E 'width|height' ~/.local/share/wineprefixes/uu-remote/drive_c/ProgramData/Netease/GameViewer/cache_setting.ini
#   → width=1922 / height=2280

# ② 中继声明的桌面尺寸
grep rfbEncodingExtDesktopSize ~/.local/state/uu-remote-bridge/desktop-x11vnc.log | tail -1
#   → Sending rfbEncodingExtDesktopSize for size (1922x2280)
```

以后插拔屏/改排列**不用再手动改**：守护逻辑发现尺寸连续 3 次稳定变化后会自己重启对齐（约 15 秒）。
只想远控单屏的话，桥接目前不支持 `-clip`，最省事是在 DDE 里把另一块屏关掉。

> 本机实测：修复前后各做了一次逐像素复现，
> 裁切假设 PSNR 41.1 dB、完整桌面假设 PSNR 39.8 dB —— 结论确凿。证据见
> `~/uu-双屏诊断/诊断说明.md`。

---

## 16. 双屏扩展时，远端想"只看笔记本屏"（主屏）

**现象 / 需求**：外接屏设为扩展后，远端画面里主屏被挤到看不见的位置，
想在内屏上用控制中心关掉外接屏却点不到 —— 等于没法用。

**根因**：中继送的是整块 root window（两块屏 1922×2280），而画布只有单屏大小，
TigerVNC 只显示左上角，露出来的恰好是**外接屏**（它排在 `+2+0`）。

**解法**：把中继裁剪到**主屏**（`xrandr --listmonitors` 里带 `*` 的那块）。

```bash
# ~/.config/uu-remote-bridge/environment
UURB_RELAY_CLIP=auto            # off | auto | WxH+X+Y
rrs                             # 重启桥接
```

桥接会把同一几何同时交给 x11vnc（`-clip`）和注入助手（`uu-x11-input --clip`），
所以**画面和点击位置都对**；主屏几何变化（比如你在远控里把扩展屏关掉）时，
守护逻辑连续 3 次检测到稳定变化就会重启桥接自动重新对齐。

**验证**：

```bash
# 中继声明的帧尺寸 = 主屏尺寸（本机 1920x1200），不是 1922x2280
grep rfbEncodingExtDesktopSize ~/.local/state/uu-remote-bridge/desktop-x11vnc.log | tail -1
DISPLAY=:0 xrandr --listmonitors
# 坐标映射验收测试（需要 gcc / xvfb / xdotool）
bash ~/Desktop/uu-remote-ubuntu-bridge/scripts/test-x11-input-clip.sh
```

**注意**：

- 想恢复"整块桌面都送"就把 `UURB_RELAY_CLIP` 改回 `off`（会回到裁切左上角的表现）；
- 想固定送某一块屏，可以直接写 `UURB_RELAY_CLIP=1920x1080+2+0`；
- UU 客户端自带的"屏幕页签"在本架构下用不了（被控端是 Linux/Wine，见 `DUAL-MONITOR.md` 第七节）。

---

## 17. 被控端麦克风被 UU 常开（想关掉）

**现象**：被控端（装 UU 的那台）的麦克风被持续占用 / 指示灯常亮。

**根因**：UU 每次被连接都会开一路**麦克风采集**（WebRTC 的 `startAudioCapture`）。
该前缀的 Wine 走 `winepulse.drv`，所以能直接打到物理麦克风。

判定证据（本机实测）：

```bash
# WirePlumber 的流记忆里能看到 UU 建过的采集流
grep -E 'Input/Audio:.*(GameViewerServer|网易UU远程服务)' \
    ~/.local/state/wireplumber/stream-properties
# 前缀里确实注册了 winepulse 设备
grep -a 'winepulse.drv\\\\devices' ~/.local/share/wineprefixes/uu-remote/user.reg | head
```

**解法**：上游已内置开关 `UURB_UU_AUDIO=off` —— 只在 UU 专用 Wine 前缀里屏蔽 `winepulse.drv`，
不碰系统 / 浏览器 / 其它 Wine 前缀。**但不能单用**：单用会让控制端永远等不到媒体
（卡在 `AudioDeviceModuleImpl::InitPlayout`），必须配"前缀私有静默 ALSA 后端"。

```bash
# 1) 静默 ALSA 命名空间（仓库自带模板）
install -m 0600 ~/Desktop/uu-remote-ubuntu-bridge/config/alsa-null.conf \
    ~/.config/uu-remote-bridge/alsa-null.conf

# 2) 该前缀的 Wine 音频驱动改 ALSA
WINEPREFIX=~/.local/share/wineprefixes/uu-remote WINEDEBUG=-all DISPLAY=:0 \
  /opt/wine-stable/bin/wine reg add 'HKCU\Software\Wine\Drivers' /v Audio /t REG_SZ /d alsa /f

# 3) 放进 systemd drop-in（别只改 environment，见「注意」）
install -d ~/.config/systemd/user/uu-remote-bridge.service.d
cat > ~/.config/systemd/user/uu-remote-bridge.service.d/20-audio-isolation.conf <<'EOF'
[Service]
Environment="UURB_UU_AUDIO=off"
Environment="ALSA_CONFIG_PATH=/home/fengjie/.config/uu-remote-bridge/alsa-null.conf"
EOF

systemctl --user daemon-reload && systemctl --user restart uu-remote-bridge.service
```

**验证**（重启后）：

```bash
systemctl --user show -p Environment -p DropInPaths uu-remote-bridge.service
P=$(pgrep -u "$UID" -f GameViewerServer.exe | head -1)
tr '\0' '\n' < /proc/$P/environ | grep -E 'UURB_UU_AUDIO|ALSA_CONFIG_PATH|WINEDLLOVERRIDES'   # 应见 winepulse.drv=d
grep -c winealsa /proc/$P/maps            # >0：Wine 已走 ALSA（有后端，媒体协商不卡）
ls -l /proc/$P/fd | grep -cE 'snd|pulse|pipewire'   # 期望 0
pw-dump | grep -icE 'GameViewer|网易UU'             # 期望 0
cat /proc/asound/card*/pcm*/sub*/status            # 期望全 closed
uu-agent snapshot /tmp/canvas.png && file /tmp/canvas.png   # 画面不受影响：1920x1200 有内容
```

**注意**：

- **放 drop-in，别只改 `environment`**：`install.sh` 会整体重写 `~/.config/uu-remote-bridge/environment`，
  升级成功后**不恢复**自定义项 → 手加的 `UURB_UU_AUDIO`、`UURB_RELAY_CLIP` 会被抹掉；drop-in 才长期生效。
- **代价**：Wine 音频驱动是单一开关，`off` 会关掉 UU 的**全部**音频 —— 麦克风不再上传，
  控制端也**听不到被控端声音**。只想关麦克风、保留"听被控端声音"需要另走 WirePlumber 侧（本指南未实现）。
- **回退**：删掉 drop-in（或改 `UURB_UU_AUDIO=system`）+
  `wine reg delete 'HKCU\Software\Wine\Drivers' /v Audio /f` + 重启服务。

### 17.1 想"麦克风不开 + 还能听到被控端的声音"

先说清一个前提：**桥接（x11vnc 中继）不转发桌面声音**（`/audio-mode:2` 只在 rdp 中继分支）。
能被听到的声音只可能来自 **UU 自己的音频通道**，而它和麦克风共用上面那个开关 —— 所以 `off` 会让两者一起没。

办法是让 UU 继续用音频，但把它的**采集对象**从"物理麦克风"换成"桌面监听口（monitor）"：
UU 采集到什么就往外送什么，于是客户端听到的是电脑的声音，而物理麦克风永远不被打开。

```bash
# 1) 恢复 UU 音频：删掉 20-audio-isolation.conf（或改成 UURB_UU_AUDIO=system），
#    并撤掉该前缀的音频驱动覆盖：
WINEPREFIX=~/.local/share/wineprefixes/uu-remote \
  /opt/wine-stable/bin/wine reg delete 'HKCU\Software\Wine\Drivers' /v Audio /f
# 2) 把默认输入指向内置声卡的监听口（名字以 wpctl status / pactl list short sources 为准）
wpctl set-default alsa_output.pci-0000_00_1f.3.analog-stereo.monitor
systemctl --user daemon-reload && systemctl --user restart uu-remote-bridge.service
```

注意：

- 动 UU 音频通路有**小概率**让控制端连不上（上游文档记过卡在 `InitPlayout`）；这台机器是远程用的，
  **别在没人在场确认重连的时候改**。
- 监听口取的是"过了音量之后"的声音：**被控端声卡静音或音量为 0 时，客户端同样听不到** —— 要听到得把被控端音量打开。
- 上游 README 警告过把 `PULSE_SOURCE`/`PULSE_SINK` 设成**重复端点名**会让 Wine 枚举 CoreAudio 卡死；
  本机没有 XRDP 重复端点，风险偏低但仍在，所以优先用 `wpctl set-default`（等价于在声音设置里换设备）。

---

## 附：改动正确性自检（每次改完跑一遍）

```bash
REPO_DIR="${REPO_DIR:-$HOME/Desktop/uu-remote-ubuntu-bridge}"
P=~/.local/share/wineprefixes/uu-remote
U="$(id -un)"

# 1) 脚本语法
bash -n ~/.local/bin/uu-remote-bridge && echo OK

# 2) DLL 哈希：仓库构建产物 == 前缀里部署的
sha256sum "$REPO_DIR/build/compat/uu-input-bridge.dll" \
          "$P/compat/uu-input-bridge.dll"

# 3) 服务 + 路由
systemctl --user is-active uu-remote-bridge.service
tail -1 "$P/drive_c/users/$U/Temp/uu-input-broker.log"
#   期望 banner 里 keyboard-route=x11

# 4) 画面（客户端视角）
rrp && ls -l ~/uu-after.png

# 5) 画布尺寸（多屏时必看）
grep UURB_RESOLUTION ~/.config/uu-remote-bridge/environment
DISPLAY=:0 xdpyinfo | grep dimensions
#   当前约定：中继裁剪到主屏（UURB_RELAY_CLIP=auto），画布等于主屏尺寸（1920x1200），
#   与桌面总尺寸不一致是【正常】的。
grep UURB_RELAY_CLIP ~/.config/uu-remote-bridge/environment
DISPLAY=:0 xrandr --listmonitors        # 带 * 的那块 = 主屏 = 远端能看到的屏
#   判断桌面尺寸别用 xdotool getdisplaygeometry，它只报主屏！

# 6) 音频隔离（若已关掉 UU 麦克风采集）
systemctl --user show -p Environment uu-remote-bridge.service | grep -o 'UURB_UU_AUDIO=[a-z]*'
AP=$(pgrep -u "$U" -f GameViewerServer.exe | head -1)
ls -l /proc/$AP/fd 2>/dev/null | grep -cE 'snd|pulse|pipewire'   # 期望 0（UU 没碰任何音频设备）
```
