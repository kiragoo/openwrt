# GitHub Actions 测试脚本

这些脚本用于在 GitHub Actions 中自动化测试 OpenWrt K3s 镜像。

## 脚本说明

### configure-openwrt.sh
配置 OpenWrt 虚拟机，等待系统完全启动并确保 SSH 可用。

**功能：**
- 等待虚拟机启动
- 检查 SSH 端口是否开放
- 确保系统就绪

### verify-kernel.sh
验证 OpenWrt 内核是否包含运行 K3s 所需的特性。

**检查项：**
- Cgroups 挂载状态
- Namespaces 支持
- 网络模块（veth、vxlan、br_netfilter）
- OverlayFS 文件系统
- 系统基本信息

### install-k3s.sh
在 OpenWrt 虚拟机中安装 K3s。

**步骤：**
1. 更新软件包列表
2. 安装依赖（ca-certificates、curl）
3. 下载 K3s 安装脚本
4. 执行安装（配置使用 Containerd）
5. 等待 K3s 启动

### verify-k3s.sh
验证 K3s 集群是否正常运行。

**检查项：**
- K3s 版本
- K3s 服务状态
- 节点就绪状态
- 系统 Pods 运行状态
- Containerd 运行时信息

**成功标准：**
- 节点状态为 Ready
- 系统 Pods 正常运行

### test-deployment.sh
测试 K3s 的部署功能。

**测试步骤：**
1. 创建 Nginx 测试部署
2. 等待部署就绪
3. 验证 Pod 状态
4. 检查容器运行
5. 清理测试资源

## 使用方式

### 在 GitHub Actions 中使用

这些脚本由 `.github/workflows/build-and-test.yml` 自动调用：

```yaml
- name: Verify kernel features
  run: |
    chmod +x .github/scripts/*.sh
    .github/scripts/verify-kernel.sh | tee verify-kernel.log
```

### 本地使用

如果你在本地运行 OpenWrt 虚拟机进行测试：

```bash
# 1. 启动虚拟机（确保 SSH 端口转发到 2222）
qemu-system-x86_64 \
  -machine q35 \
  -cpu host \
  -enable-kvm \
  -smp 2 \
  -m 2048 \
  -drive file=openwrt.qcow2,if=virtio,format=qcow2 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -nographic \
  -daemonize

# 2. 运行测试脚本
chmod +x .github/scripts/*.sh
.github/scripts/configure-openwrt.sh
.github/scripts/verify-kernel.sh
.github/scripts/install-k3s.sh
.github/scripts/verify-k3s.sh
.github/scripts/test-deployment.sh
```

## SSH 连接

所有脚本使用以下 SSH 命令连接到虚拟机：

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 root@localhost
```

**参数说明：**
- `-o StrictHostKeyChecking=no` - 跳过主机密钥验证
- `-o UserKnownHostsFile=/dev/null` - 不保存主机密钥
- `-p 2222` - 使用端口 2222（QEMU 端口转发）
- `root@localhost` - 以 root 用户连接

## 故障排查

### SSH 连接失败

```bash
# 检查虚拟机是否运行
ps aux | grep qemu

# 检查端口是否开放
nc -zv localhost 2222

# 手动测试 SSH 连接
ssh -p 2222 root@localhost
```

### K3s 安装失败

```bash
# 查看系统日志
ssh -p 2222 root@localhost "logread | grep k3s"

# 检查磁盘空间
ssh -p 2222 root@localhost "df -h"

# 检查内存
ssh -p 2222 root@localhost "free -m"
```

### 节点未就绪

```bash
# 查看节点详细信息
ssh -p 2222 root@localhost "k3s kubectl describe node"

# 查看 K3s 日志
ssh -p 2222 root@localhost "logread | grep k3s | tail -100"

# 检查容器运行时
ssh -p 2222 root@localhost "k3s crictl info"
```

## 修改脚本

如果需要修改测试流程：

1. 编辑相应的脚本文件
2. 确保脚本有执行权限
3. 在本地测试验证
4. 提交到仓库触发 GitHub Actions

## 注意事项

- 所有脚本使用 `set -e`，任何命令失败都会导致脚本退出
- SSH 连接使用无密码的 root 用户（OpenWrt 默认配置）
- 脚本输出会被 `tee` 命令同时显示和保存到日志文件
- 超时设置确保不会无限等待
