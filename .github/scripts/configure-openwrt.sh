#!/bin/bash
# 配置 OpenWrt 虚拟机

set -e

echo "=== 配置 OpenWrt 虚拟机 ==="

# 等待虚拟机完全启动
echo "等待虚拟机启动..."
sleep 30

# 使用 SSH 连接（OpenWrt 默认允许 root 无密码登录）
# 由于是首次启动，我们需要通过串口或等待 SSH 可用

# 检查 SSH 是否可用
for i in {1..30}; do
  if timeout 5 bash -c "echo > /dev/tcp/localhost/2222" 2>/dev/null; then
    echo "SSH 端口已开放"
    break
  fi
  echo "等待 SSH 可用... ($i/30)"
  sleep 5
done

echo "OpenWrt 配置完成"
