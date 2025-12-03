#!/bin/bash
# 在 OpenWrt 中安装 K3s

set -e

echo "=== 安装 K3s ==="

SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost"

echo "更新软件包列表..."
$SSH_CMD "opkg update"

echo "安装依赖..."
$SSH_CMD "opkg install ca-certificates curl"

echo "下载 K3s 安装脚本..."
$SSH_CMD "curl -sfL https://get.k3s.io -o /tmp/install-k3s.sh"
$SSH_CMD "chmod +x /tmp/install-k3s.sh"

echo "安装 K3s..."
$SSH_CMD "INSTALL_K3S_EXEC='--container-runtime-endpoint unix:///run/containerd/containerd.sock' sh /tmp/install-k3s.sh" || {
  echo "K3s 安装失败，查看日志..."
  $SSH_CMD "logread | tail -50"
  exit 1
}

echo "等待 K3s 启动..."
sleep 30

echo "✅ K3s 安装完成"
