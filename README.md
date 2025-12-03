# OpenWrt for K3s - 构建指南

[![Build and Test](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/build-and-test.yml)

本项目提供了一个最小化的 OpenWrt 配置，包含运行 K3s 1.30.11 和 Containerd 所需的所有内核依赖和系统组件。

## 快速开始

```bash
# 使用默认配置编译 x86_64 版本
make CONFIG_FILE=config-k3s build

# 查看编译产物
make show-images
```

**编译其他架构：**
```bash
# ARM 64位
make TARGET_ARCH=armvirt TARGET_SUBARCH=64 CONFIG_FILE=config-k3s build

# 树莓派 4
make TARGET_ARCH=bcm27xx TARGET_SUBARCH=bcm2711 CONFIG_FILE=config-k3s build
```

## 系统要求

- Linux 构建环境（推荐 Ubuntu 20.04+）
- 至少 10GB 可用磁盘空间
- 4GB+ RAM
- 必需的构建工具：
  ```bash
  sudo apt-get update
  sudo apt-get install build-essential clang flex bison g++ gawk \
    gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev \
    python3-distutils rsync unzip zlib1g-dev file wget
  ```

## 配置说明

### 目标平台配置

目标平台通过 Makefile 变量控制，而不是在 config-k3s 中硬编码。这样可以灵活支持多种架构：

**默认配置（x86_64）：**
```makefile
TARGET_ARCH ?= x86
TARGET_SUBARCH ?= 64
TARGET_PROFILE ?= Generic
```

**支持其他平台：**
```bash
# 编译 ARM 64位版本
make TARGET_ARCH=armvirt TARGET_SUBARCH=64 build

# 编译树莓派版本
make TARGET_ARCH=bcm27xx TARGET_SUBARCH=bcm2711 build

# 编译 x86 32位版本
make TARGET_ARCH=x86 TARGET_SUBARCH=generic build
```

### 核心内核特性

#### 1. Cgroups (控制组)

Cgroups 是容器资源隔离和限制的基础。

```
CONFIG_KERNEL_CGROUPS=y                    # 启用 cgroups 支持
CONFIG_KERNEL_BLK_CGROUP=y                 # 块设备 I/O 控制
CONFIG_KERNEL_CGROUP_CPUACCT=y             # CPU 使用统计
CONFIG_KERNEL_CGROUP_DEVICE=y              # 设备访问控制
CONFIG_KERNEL_CGROUP_FREEZER=y             # 进程冻结/恢复
CONFIG_KERNEL_CGROUP_PIDS=y                # 进程数量限制
CONFIG_KERNEL_CGROUP_SCHED=y               # CPU 调度控制
CONFIG_KERNEL_CFS_BANDWIDTH=y              # CPU 带宽限制
CONFIG_KERNEL_CPUSETS=y                    # CPU 和内存节点分配
CONFIG_KERNEL_FAIR_GROUP_SCHED=y           # 公平组调度
CONFIG_KERNEL_MEMCG=y                      # 内存控制
CONFIG_KERNEL_MM_OWNER=y                   # 内存所有者跟踪
CONFIG_KERNEL_NETPRIO_CGROUP=y             # 网络优先级控制
CONFIG_KERNEL_NET_CLS_CGROUP=y             # 网络分类控制
```

**用途**：
- 限制容器的 CPU、内存、磁盘 I/O 使用
- 统计容器资源使用情况
- 实现容器的资源配额和优先级

#### 2. Namespaces (命名空间)

Namespaces 提供容器的隔离环境。

```
CONFIG_KERNEL_NAMESPACES=y                 # 启用命名空间支持
CONFIG_KERNEL_IPC_NS=y                     # IPC 隔离（消息队列、信号量）
CONFIG_KERNEL_NET_NS=y                     # 网络栈隔离
CONFIG_KERNEL_PID_NS=y                     # 进程 ID 隔离
CONFIG_KERNEL_USER_NS=y                    # 用户和组 ID 隔离
CONFIG_KERNEL_UTS_NS=y                     # 主机名和域名隔离
```

**用途**：
- 为每个容器创建独立的进程树
- 隔离网络接口和路由表
- 提供独立的主机名和 IPC 资源

#### 3. 安全和其他特性

```
CONFIG_KERNEL_SECCOMP=y                    # 系统调用过滤
CONFIG_KERNEL_SECCOMP_FILTER=y             # BPF 系统调用过滤
CONFIG_KERNEL_KEYS=y                       # 内核密钥管理
CONFIG_KERNEL_POSIX_MQUEUE=y               # POSIX 消息队列
CONFIG_KERNEL_DEVPTS_MULTIPLE_INSTANCES=y  # 多实例 pts 支持
CONFIG_KERNEL_FREEZER=y                    # 进程冻结支持
CONFIG_KERNEL_LXC_MISC=y                   # LXC 容器支持
```

**用途**：
- Seccomp：限制容器可以执行的系统调用，增强安全性
- Keys：支持容器镜像签名验证
- POSIX MQueue：容器间通信

### 网络组件

#### 1. 基础网络工具

```
CONFIG_PACKAGE_ip-bridge=y                 # 网桥管理工具
CONFIG_PACKAGE_ip-full=y                   # 完整的 iproute2 工具集
CONFIG_PACKAGE_ipset=y                     # IP 集合管理
```

**用途**：
- 创建和管理容器网络桥接
- 配置容器网络接口和路由
- 管理网络策略的 IP 集合

#### 2. iptables 模块

```
CONFIG_IPTABLES_CONNLABEL=y                # 连接标签支持
CONFIG_IPTABLES_NFTABLES=y                 # nftables 兼容层
CONFIG_PACKAGE_iptables-mod-conntrack-extra=y  # 扩展连接跟踪
CONFIG_PACKAGE_iptables-mod-extra=y        # 额外的 iptables 模块
CONFIG_PACKAGE_iptables-mod-ipopt=y        # IP 选项匹配
```

**用途**：
- K3s 服务负载均衡（kube-proxy）
- 容器网络地址转换（NAT）
- 网络策略实施

#### 3. 内核网络模块

```
CONFIG_PACKAGE_kmod-br-netfilter=y         # 网桥 netfilter 支持
CONFIG_PACKAGE_kmod-veth=y                 # 虚拟以太网对
CONFIG_PACKAGE_kmod-vxlan=y                # VXLAN 隧道（overlay 网络）
CONFIG_PACKAGE_kmod-dummy=y                # 虚拟网络接口
CONFIG_PACKAGE_kmod-tun=y                  # TUN/TAP 设备
CONFIG_PACKAGE_kmod-iptunnel=y             # IP 隧道支持
CONFIG_PACKAGE_kmod-udptunnel4=y           # UDP IPv4 隧道
CONFIG_PACKAGE_kmod-udptunnel6=y           # UDP IPv6 隧道
```

**用途**：
- veth：连接容器和主机网络
- vxlan：跨主机容器网络（Flannel、Calico）
- br-netfilter：允许 iptables 规则应用于桥接流量

#### 4. Netfilter 模块

```
CONFIG_PACKAGE_kmod-ipt-conntrack=y        # 连接跟踪
CONFIG_PACKAGE_kmod-ipt-conntrack-extra=y  # 扩展连接跟踪
CONFIG_PACKAGE_kmod-ipt-extra=y            # 额外的匹配模块
CONFIG_PACKAGE_kmod-ipt-ipopt=y            # IP 选项匹配
CONFIG_PACKAGE_kmod-ipt-ipset=y            # ipset 匹配
CONFIG_PACKAGE_kmod-ipt-raw=y              # raw 表支持
CONFIG_PACKAGE_kmod-ipt-nat=y              # IPv4 NAT
CONFIG_PACKAGE_kmod-ipt-nat6=y             # IPv6 NAT
CONFIG_PACKAGE_kmod-nf-conntrack-netlink=y # 连接跟踪 netlink 接口
CONFIG_PACKAGE_kmod-nf-ipvs=y              # IPVS 负载均衡
CONFIG_PACKAGE_kmod-nf-nat=y               # NAT 核心
CONFIG_PACKAGE_kmod-nf-nat6=y              # IPv6 NAT 核心
CONFIG_PACKAGE_kmod-nfnetlink=y            # Netfilter netlink 接口
```

**用途**：
- 实现 Kubernetes Service 的负载均衡
- 容器端口映射和网络地址转换
- 网络策略和防火墙规则

### 文件系统

```
CONFIG_PACKAGE_kmod-fs-overlay=y           # OverlayFS 支持
CONFIG_PACKAGE_kmod-fuse=y                 # FUSE 文件系统
CONFIG_PACKAGE_block-mount=y               # 块设备挂载工具
```

**用途**：
- OverlayFS：容器镜像分层存储的基础
- FUSE：支持某些容器存储驱动
- block-mount：管理持久化存储卷

### 加密模块

```
CONFIG_PACKAGE_kmod-crypto-hash=y          # 哈希算法支持
CONFIG_PACKAGE_kmod-crypto-manager=y       # 加密算法管理
CONFIG_PACKAGE_kmod-crypto-sha1=y          # SHA1 算法
CONFIG_PACKAGE_kmod-crypto-sha256=y        # SHA256 算法
CONFIG_PACKAGE_kmod-crypto-crc32c=y        # CRC32C 校验
CONFIG_PACKAGE_kmod-lib-crc32c=y           # CRC32C 库
```

**用途**：
- 容器镜像完整性验证
- 镜像层的哈希计算
- 文件系统数据校验

### 依赖库

```
CONFIG_PACKAGE_libipset=y                  # ipset 库
CONFIG_PACKAGE_libmnl=y                    # Netlink 库
CONFIG_PACKAGE_libnetfilter-conntrack=y    # 连接跟踪库
CONFIG_PACKAGE_libnfnetlink=y              # Netfilter netlink 库
CONFIG_PACKAGE_libnftnl=y                  # nftables 库
```

### 存储配置

```
CONFIG_TARGET_ROOTFS_PARTSIZE=2048         # 根文件系统分区大小：2GB
```

**说明**：K3s 和容器镜像需要足够的存储空间，建议至少 2GB。

## Makefile 使用

### 可配置变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `OPENWRT_VERSION` | 24.10.0 | OpenWrt 版本号 |
| `TARGET_ARCH` | x86 | 目标架构（x86, armvirt, bcm27xx 等） |
| `TARGET_SUBARCH` | 64 | 子架构（64, generic, bcm2711 等） |
| `TARGET_PROFILE` | Generic | 目标配置文件 |
| `CONFIG_FILE` | config | 配置文件名（默认使用 config-k3s） |
| `JOBS` | $(nproc) | 并行编译任务数 |

### 常用命令

```bash
# 显示帮助信息
make help

# 显示当前配置
make info

# 使用默认配置编译（x86_64）
make CONFIG_FILE=config-k3s build

# 编译 ARM 64位版本
make TARGET_ARCH=armvirt TARGET_SUBARCH=64 CONFIG_FILE=config-k3s build

# 编译树莓派 4 版本
make TARGET_ARCH=bcm27xx TARGET_SUBARCH=bcm2711 CONFIG_FILE=config-k3s build

# 下载指定版本的 OpenWrt
make OPENWRT_VERSION=23.05.2 download

# 指定并行任务数
make JOBS=8 build

# 打开配置菜单（高级用户）
make menuconfig

# 清理并重新编译
make rebuild

# 完全清理（删除源码）
make distclean
```

## 编译流程详解

### 1. 下载源码
```bash
make download
```
从 GitHub 克隆 OpenWrt 官方仓库的指定版本。

### 2. 更新 Feeds
```bash
make feeds
```
Feeds 是 OpenWrt 的软件包仓库，包含数千个可选软件包。

### 3. 应用配置
```bash
make config
```
将 `config-k3s` 文件复制到构建目录并生成完整配置。

### 4. 编译
```bash
make build
```
编译过程包括：
- 下载所有依赖的源码包
- 编译工具链
- 编译内核
- 编译软件包
- 生成固件镜像

编译时间取决于硬件性能，通常需要 30 分钟到 2 小时。

### 5. 查看产物
```bash
make show-images
```
编译产物位于 `openwrt/bin/targets/x86/64/` 目录：
- `openwrt-x86-64-generic-ext4-combined.img.gz` - 完整镜像
- `openwrt-x86-64-generic-squashfs-combined.img.gz` - SquashFS 镜像

## 安装和部署

### 1. 写入镜像

```bash
# 解压镜像
gunzip openwrt/bin/targets/x86/64/openwrt-*-combined.img.gz

# 写入 U 盘或硬盘（替换 /dev/sdX 为实际设备）
sudo dd if=openwrt-*-combined.img of=/dev/sdX bs=4M status=progress
sync
```

### 2. 首次启动

1. 从安装介质启动设备
2. 默认 IP：`192.168.1.1`
3. 默认无密码，首次登录后设置 root 密码

### 3. 安装 K3s

```bash
# SSH 登录到 OpenWrt
ssh root@192.168.1.1

# 安装必要的运行时依赖
opkg update
opkg install ca-certificates curl

# 下载并安装 K3s
curl -sfL https://get.k3s.io | sh -

# 检查 K3s 状态
k3s kubectl get nodes
```

## 验证内核特性

登录到 OpenWrt 后，可以验证容器所需的内核特性：

```bash
# 检查 cgroups
mount | grep cgroup

# 检查命名空间支持
ls -la /proc/self/ns/

# 检查网络模块
lsmod | grep -E "veth|vxlan|br_netfilter"

# 检查 OverlayFS
cat /proc/filesystems | grep overlay
```

## 故障排除

### 编译失败

1. **磁盘空间不足**
   ```bash
   df -h  # 检查可用空间
   ```

2. **依赖缺失**
   ```bash
   # 重新安装构建依赖
   sudo apt-get install --reinstall build-essential
   ```

3. **网络问题**
   ```bash
   # 使用代理或镜像源
   export http_proxy=http://proxy:port
   ```

### K3s 启动失败

1. **检查内核特性**
   ```bash
   k3s check-config
   ```

2. **查看日志**
   ```bash
   logread | grep k3s
   ```

3. **内存不足**
   - K3s 至少需要 512MB RAM
   - 建议 1GB+ 用于生产环境

## 多架构支持

config-k3s 配置文件专注于 K3s 所需的内核特性和软件包，不包含特定平台配置。这使得同一个配置文件可以用于多种硬件架构。

### 常见架构配置

**x86_64（默认）：**
```bash
make TARGET_ARCH=x86 TARGET_SUBARCH=64 CONFIG_FILE=config-k3s build
```

**ARM 64位虚拟化平台：**
```bash
make TARGET_ARCH=armvirt TARGET_SUBARCH=64 CONFIG_FILE=config-k3s build
```

**树莓派系列：**
```bash
# 树莓派 4/400/CM4
make TARGET_ARCH=bcm27xx TARGET_SUBARCH=bcm2711 CONFIG_FILE=config-k3s build

# 树莓派 3
make TARGET_ARCH=bcm27xx TARGET_SUBARCH=bcm2710 CONFIG_FILE=config-k3s build
```

**其他 ARM 设备：**
```bash
# Rockchip (如 NanoPi R4S)
make TARGET_ARCH=rockchip TARGET_SUBARCH=armv8 CONFIG_FILE=config-k3s build

# MediaTek (如 GL.iNet)
make TARGET_ARCH=mediatek TARGET_SUBARCH=mt7622 CONFIG_FILE=config-k3s build
```

### 查找可用架构

```bash
# 下载源码后，查看支持的架构
ls openwrt/target/linux/

# 查看特定架构的子架构
ls openwrt/target/linux/bcm27xx/
```

## 自定义配置

如需添加额外的软件包或修改配置：

```bash
# 1. 设置目标架构并进入配置菜单
make TARGET_ARCH=x86 TARGET_SUBARCH=64 menuconfig

# 2. 使用方向键和空格键选择/取消选择包
#    <*> 表示编译进固件
#    <M> 表示编译为模块
#    < > 表示不编译

# 3. 保存配置（会自动更新 config-k3s 文件）
# 4. 重新编译
make build
```

## 性能优化建议

1. **增加根分区大小**（如果需要存储大量镜像）
   ```
   CONFIG_TARGET_ROOTFS_PARTSIZE=4096  # 4GB
   ```

2. **启用 SSD TRIM 支持**
   ```
   CONFIG_PACKAGE_block-mount=y
   CONFIG_PACKAGE_fstrim=y
   ```

3. **调整并行编译数**
   ```bash
   make JOBS=16 build  # 根据 CPU 核心数调整
   ```

## 许可证

本项目配置文件采用 MIT 许可证。OpenWrt 本身采用 GPL 许可证。

## 参考资源

- [OpenWrt 官方文档](https://openwrt.org/docs/start)
- [K3s 官方文档](https://docs.k3s.io/)
- [Containerd 文档](https://containerd.io/docs/)
- [Linux 容器技术](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v1/cgroups.html)

## CI/CD 自动化

本项目使用 GitHub Actions 进行自动化构建和测试。

### 工作流程

每次推送代码到主分支时，会自动执行以下步骤：

1. **构建 OpenWrt 镜像**
   - 下载 OpenWrt 源码
   - 应用 config-k3s 配置
   - 编译 x86_64 镜像

2. **虚拟机测试**
   - 使用 QEMU 启动 OpenWrt 虚拟机
   - 验证内核特性（Cgroups、Namespaces、OverlayFS 等）
   - 配置网络和系统

3. **K3s 集群部署**
   - 安装 K3s 和 Containerd
   - 验证集群节点状态
   - 检查系统 Pods 运行状态

4. **功能测试**
   - 创建测试部署（Nginx）
   - 验证容器运行时
   - 清理测试资源

5. **产物上传**
   - 上传构建的 OpenWrt 镜像（保留 30 天）
   - 上传测试日志（保留 7 天）

### 查看构建结果

- 访问 GitHub Actions 页面查看构建状态
- 下载构建产物中的 OpenWrt 镜像
- 查看详细的测试日志

### 本地复现 CI 测试

如果需要在本地复现 CI 测试流程：

```bash
# 1. 构建镜像
make CONFIG_FILE=config-k3s build

# 2. 准备虚拟机镜像
gunzip -c openwrt/bin/targets/x86/64/*-combined-ext4.img.gz > openwrt.img
qemu-img resize openwrt.img 8G
qemu-img convert -f raw -O qcow2 openwrt.img openwrt.qcow2

# 3. 启动虚拟机
qemu-system-x86_64 \
  -machine q35 \
  -cpu host \
  -enable-kvm \
  -smp 2 \
  -m 2048 \
  -drive file=openwrt.qcow2,if=virtio,format=qcow2 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=net0 \
  -nographic

# 4. 在虚拟机中安装 K3s
# （登录后执行）
opkg update
opkg install ca-certificates curl
curl -sfL https://get.k3s.io | sh -

# 5. 验证集群
k3s kubectl get nodes
k3s kubectl get pods -A
```

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这个配置。

## 更新日志

- **2024-12**: 初始版本，支持 K3s 1.30.11 和 OpenWrt 24.10.0
