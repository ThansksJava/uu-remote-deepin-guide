#!/usr/bin/env bash
# deepin-port 环境准备（需 root）：i386 架构、WineHQ bookworm 源、桥接依赖、Wine 11
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "== deepin-port prep start: $(date) =="
echo "user: $(id)"

echo "-- [1/6] 限制 deepin 源为 amd64（为 i386 架构让路，避免 404）"
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*; do
    [ -f "$f" ] || continue
    sed -i \
        -e 's|^deb https://community-packages\.deepin\.com|deb [arch=amd64] https://community-packages.deepin.com|' \
        -e 's|^deb https://com-store-packages\.uniontech\.com|deb [arch=amd64] https://com-store-packages.uniontech.com|' \
        "$f" || true
done
grep -h '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null || true

echo "-- [2/6] 添加 i386 架构"
dpkg --add-architecture i386

echo "-- [3/6] 安装 WineHQ bookworm 源"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
    -o /etc/apt/keyrings/winehq-archive.key
curl -fsSL https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources \
    -o /etc/apt/sources.list.d/winehq-bookworm.sources

echo "-- [4/6] apt-get update"
apt-get update

echo "-- [5/6] 安装桥接依赖"
apt-get install -y \
    acl aria2 binutils ca-certificates cmake crudini curl freerdp3-x11 \
    gcc gcc-mingw-w64-x86-64 git iproute2 jq libsecret-tools libx11-6 \
    libxml2-utils libxtst6 meson ninja-build openbox openssl p7zip-full patch \
    python3 python3-attr python3-gi python3-jinja2 tar tigervnc-viewer \
    x11-utils x11vnc xauth xclip xdotool xvfb zstd

echo "-- [6/6] 安装 WineHQ stable（Wine 11 → /opt/wine-stable）"
apt-get install -y --install-recommends winehq-stable

# 把当前登录用户的 ~/.Xauthority 属主纠正过来（原实现写死了用户名/家目录）
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "$USER")}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [ -n "$TARGET_HOME" ] && [ -e "$TARGET_HOME/.Xauthority" ]; then
    chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$TARGET_HOME/.Xauthority" 2>/dev/null || true
    echo "-- ~/.Xauthority 属主 -> $TARGET_USER ($TARGET_HOME)"
fi

echo "== prep done: $(date) =="
echo "target user: ${TARGET_USER} (home ${TARGET_HOME:-未知})"
echo "wine: $(/opt/wine-stable/bin/wine --version 2>&1 || echo 'wine 不可用')"
