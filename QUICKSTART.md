# UU 远程 · 重启后快速恢复 & 重新登录

> 适用本机（Deepin 25 + Wine 里的 UU）。
> 下面命令都在**普通终端**里跑，不需要 root、也不需要 sudo。
> 下称 `$G` = 指南目录 = `~/Desktop/uu-remote-deepin-guide`

---

## 一、重启电脑后怎么恢复

### 正常情况下：什么都不用做

桥接服务 `uu-remote-bridge.service` 是 systemd **用户级**服务，已设置开机自启。你登录图形桌面后它会自动：起私有屏 → 起 openbox → 拉起 UU 客户端 → 接管真实桌面 `:0`。

等 30～60 秒，手机 App / 另一台电脑用同一 UU 账号连本机，通常直接就能控。

> 只在**登录桌面之后**才启动；停在登录界面时连不上是正常的。

### 想在本机看到 UU 管理窗口时（要扫码、看设备列表）

```bash
bash ~/Desktop/uu-remote-deepin-guide/scripts/04-open.sh
```

或者直接双击桌面上的 **UU Remote** 图标（等 20～30 秒）。

这条是"一键自愈"：服务没起就起服务、openbox 掉了就补、客户端掉了就补、最后把管理窗口投到桌面。全程约 1 分钟，看到 `✅ UU 窗口已显示在桌面上` 就成了。

### 确认状态

```bash
uu-remote status        # 桥接服务状态，看到 active (running) 即正常
rrx                     # 重启服务 + 重排窗口 + 出报告（写到 ~/uu-stack.txt）
```

---

## 二、登录失效了怎么重新登录

**怎么判断**：UU 窗口里出现登录界面/二维码，或手机端设备列表里本机显示离线、点了没反应。

### 方式 1 · 抓二维码扫码（推荐，一直用的这个）

```bash
uurec
```

它把登录二维码抓成图片：`~/.local/state/uu-deepin-port/login.png`

1. 打开这张图（双击，用看图的软件）
2. 手机 **网易UU远程 App** → 扫一扫 → 扫屏幕上的这张二维码
3. 二维码 **1～2 分钟就过期**。过期了先在 UU 窗口里点一下"点击刷新"，再 `uurec` 抓一次
4. 登录成功后，UU 窗口会变成"本机被控中"

### 方式 2 · 直接扫屏幕

先 `bash $G/scripts/04-open.sh` 把管理窗口投到桌面；如果二维码就在那个窗口里，直接用手机扫**显示器**就行。

### 方式 3 · 在真实桌面上直接登录

```bash
uu-remote login
```

会在真实桌面上直接开一个 UU 登录窗，鼠标键盘都正常可用；登录完把那个窗口关掉，会自动重启桥接。

> ⚠️ 它会先**停掉桥接**，正在远控的客户端会断开，登录后重连即可。

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
~/.local/share/wineprefixes/uu-remote/drive_c/users/fengjie/Temp/uu-input-broker.log
```

---

## 四、命令 / 路径速查

| 用途 | 命令 或 路径 |
|---|---|
| 打开 UU 管理窗口 | 桌面 `UU Remote` 图标，或 `uu-remote open` |
| 一键自愈（推荐） | `bash ~/Desktop/uu-remote-deepin-guide/scripts/04-open.sh` |
| 看服务状态 | `uu-remote status` |
| 重启桥接服务 | `rrs`（同 `uurr`） |
| 重启 + 重排窗口 + 报告 | `rrx` → `~/uu-stack.txt` |
| 抓登录二维码 | `uurec` → `~/.local/state/uu-deepin-port/login.png` |
| 看私有屏窗口层级 | `rrd` → `~/uu-stack.txt` |
| 截私有屏图 | `rrp` → `~/uu-before.png`、`~/uu-after.png` |
| 服务单元文件 | `~/.config/systemd/user/uu-remote-bridge.service` |
| 环境开关（路由/光标等） | `~/.config/uu-remote-bridge/environment` |
| 指南目录 | `~/Desktop/uu-remote-deepin-guide` |
| 详细文档 | `$G/README.md`、`$G/TROUBLESHOOTING.md`、`$G/COMMANDS.md` |

> 提醒：改指南目录里的脚本**不影响**正在跑的服务——服务用的是 `~/.local/bin/` 下那份独立拷贝，要生效得替换那份并重启服务。
