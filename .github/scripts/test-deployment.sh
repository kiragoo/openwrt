#!/bin/bash
# 测试 K3s 部署功能

set -e

echo "=== 测试 K3s 部署 ==="

SSH_CMD="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost"

echo "创建测试部署..."
$SSH_CMD "k3s kubectl create deployment nginx --image=nginx:alpine"

echo "等待部署就绪..."
$SSH_CMD "k3s kubectl wait --for=condition=available --timeout=120s deployment/nginx" || {
  echo "部署超时，查看状态..."
  $SSH_CMD "k3s kubectl get deployment nginx"
  $SSH_CMD "k3s kubectl get pods -l app=nginx"
  $SSH_CMD "k3s kubectl describe pods -l app=nginx"
  exit 1
}

echo "查看部署状态..."
$SSH_CMD "k3s kubectl get deployment nginx"

echo "查看 Pod 状态..."
$SSH_CMD "k3s kubectl get pods -l app=nginx"

echo "查看容器列表..."
$SSH_CMD "k3s crictl ps"

echo "清理测试部署..."
$SSH_CMD "k3s kubectl delete deployment nginx"

echo "✅ 部署测试成功"
