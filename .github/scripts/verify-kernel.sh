#!/bin/bash
# 验证 OpenWrt 内核特性

set -e

echo "=== 验证内核特性 ==="

# 使用 SSH 执行命令
SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost"

echo "检查 Cgroups..."
$SSH_CMD "mount | grep cgroup" || echo "警告: Cgroups 未挂载"

echo "检查 Namespaces..."
$SSH_CMD "ls -la /proc/self/ns/" || echo "警告: Namespaces 不可用"

echo "检查网络模块..."
$SSH_CMD "lsmod | grep -E 'veth|vxlan|br_netfilter' || true"

echo "检查 OverlayFS..."
$SSH_CMD "cat /proc/filesystems | grep overlay" || echo "警告: OverlayFS 不可用"

echo "系统信息..."
$SSH_CMD "uname -a"
$SSH_CMD "free -m"
$SSH_CMD "df -h"

echo "✅ 内核特性验证完成"
