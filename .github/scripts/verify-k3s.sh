#!/bin/bash
# 验证 K3s 集群状态

set -e

echo "=== 验证 K3s 集群 ==="

SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost"

echo "检查 K3s 版本..."
$SSH_CMD "k3s --version"

echo "检查 K3s 服务状态..."
$SSH_CMD "/etc/init.d/k3s status" || echo "K3s 服务状态检查失败"

echo "等待节点就绪..."
for i in {1..30}; do
  if $SSH_CMD "k3s kubectl get nodes 2>/dev/null | grep -q Ready"; then
    echo "✅ 节点已就绪"
    break
  fi
  echo "等待节点就绪... ($i/30)"
  sleep 10
done

echo "节点信息..."
$SSH_CMD "k3s kubectl get nodes -o wide"

echo "系统 Pods..."
$SSH_CMD "k3s kubectl get pods -A"

echo "Containerd 版本..."
$SSH_CMD "k3s crictl version"

echo "容器运行时信息..."
$SSH_CMD "k3s crictl info | head -20"

# 检查节点是否就绪
if $SSH_CMD "k3s kubectl get nodes | grep -q Ready"; then
  echo "✅ K3s 集群验证成功"
else
  echo "❌ K3s 节点未就绪"
  echo "查看 K3s 日志..."
  $SSH_CMD "logread | grep k3s | tail -50"
  exit 1
fi
