#!/usr/bin/env bash
# deepin-port 补充：为 wine-stable 提供缺失的 i386 侧（Deepin 源无 i386 库）
# 从清华 Debian bookworm 镜像拉取 i386 运行库，仅此用途
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

KEY=/usr/share/keyrings/debian-archive-keyring.gpg
if [ -f "$KEY" ]; then
    SIGNED="signed-by=$KEY"
else
    SIGNED="trusted=yes"
    echo "WARN: 找不到 debian-archive-keyring，退回 trusted=yes"
fi

echo "deb [arch=i386 ${SIGNED}] https://mirrors.tuna.tsinghua.edu.cn/debian bookworm main" \
    > /etc/apt/sources.list.d/debian-i386.list
cat /etc/apt/sources.list.d/debian-i386.list

echo "-- apt-get update"
apt-get update

echo "-- 安装 wine-stable-i386（连带 i386 运行库）"
apt-get install -y wine-stable-i386:i386

echo "== i386 wine 侧就绪 =="
ls /opt/wine-stable/lib/wine/
/opt/wine-stable/bin/wine --version
