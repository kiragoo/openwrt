# user-ns-pkgs IPK 包集成说明

## 概述

本方案将 `user-ns-pkgs` 目录中的 ipk 包集成到 OpenWrt 编译镜像中，并在系统首次启动时自动安装这些包，同时启用相关服务。

## 工作原理

### 1. 编译阶段集成

在 `Makefile` 的 `config` 目标中，会自动执行以下操作：

1. **复制 IPK 包到镜像**：将 `user-ns-pkgs/` 目录中的所有 `.ipk` 文件复制到 `openwrt/files/usr/lib/opkg/packages/` 目录
2. **创建安装脚本**：将 `scripts/install-user-packages.sh` 复制到 `openwrt/files/etc/uci-defaults/99_install_user_packages`

这些文件会被 OpenWrt 构建系统自动包含到最终的 rootfs 镜像中。

### 2. 首次启动自动安装

OpenWrt 的启动流程会在 `/etc/init.d/boot` 中调用 `uci_apply_defaults` 函数，该函数会：

1. 扫描 `/etc/uci-defaults/` 目录中的所有脚本
2. 按文件名顺序执行这些脚本
3. 执行成功后删除脚本文件（确保只执行一次）

我们的安装脚本 `99_install_user_packages` 会：

1. 检查是否已经安装过（通过 `/etc/.user_packages_installed` 标志文件）
2. 等待 opkg 系统就绪
3. 安装 `/usr/lib/opkg/packages/` 目录中的所有 ipk 包
4. 启用并启动相关服务（vsftpd, sshd, uhttpd, rpcd）
5. 创建安装标志文件，防止重复安装

## 文件结构

```
openwrt/
├── files/                          # OpenWrt 构建系统会自动将此目录内容复制到 rootfs
│   ├── usr/lib/opkg/packages/      # IPK 包存放目录
│   │   └── *.ipk                   # 所有 ipk 包文件
│   └── etc/uci-defaults/           # 首次启动脚本目录
│       └── 99_install_user_packages # 自动安装脚本
└── ...

user-ns-pkgs/                       # 源 IPK 包目录
└── *.ipk                           # 所有需要集成的 ipk 包

scripts/
└── install-user-packages.sh        # 安装脚本源文件
```

## 使用方法

### 准备 IPK 包

确保 `user-ns-pkgs/` 目录中包含所有需要集成的 `.ipk` 文件：

```bash
ls -lh user-ns-pkgs/*.ipk
```

### 编译 OpenWrt

正常执行编译流程，集成过程会自动完成：

```bash
make config    # 会自动复制 ipk 包和创建安装脚本
make build     # 编译镜像（包含集成的包和脚本）
```

### 验证集成

编译完成后，可以检查镜像中是否包含相关文件：

```bash
# 检查镜像中的包文件（需要挂载或解压镜像）
ls -lh openwrt/files/usr/lib/opkg/packages/*.ipk

# 检查安装脚本
cat openwrt/files/etc/uci-defaults/99_install_user_packages
```

### 首次启动

系统首次启动时，会自动执行安装脚本。可以通过日志查看安装过程：

```bash
# 在 OpenWrt 系统上查看安装日志
logread | grep user-packages
```

## 服务自启动

安装脚本会自动启用并启动以下服务（如果已安装）：

- **vsftpd**: FTP 服务器
- **sshd**: OpenSSH 服务器
- **uhttpd**: Web 服务器（LuCI）
- **rpcd**: RPC 守护进程（LuCI 需要）

## 故障排除

### 包未安装

1. 检查日志：`logread | grep user-packages`
2. 检查标志文件：`ls -l /etc/.user_packages_installed`
3. 手动执行安装脚本：`/etc/uci-defaults/99_install_user_packages`（如果文件还存在）

### 服务未启动

1. 检查服务是否存在：`ls -l /etc/init.d/vsftpd /etc/init.d/sshd`
2. 手动启用服务：`/etc/init.d/vsftpd enable && /etc/init.d/vsftpd start`
3. 检查服务状态：`/etc/init.d/vsftpd status`

### 依赖问题

如果遇到依赖问题，安装脚本使用了 `--force-depends` 和 `--force-overwrite` 选项。如果仍有问题：

1. 检查包的依赖关系
2. 确保所有依赖包都在 `user-ns-pkgs/` 目录中
3. 查看详细错误日志：`logread | grep -A 10 user-packages`

## 注意事项

1. **只执行一次**：安装脚本通过标志文件确保只执行一次，即使系统重启也不会重复安装
2. **包顺序**：opkg 会自动处理依赖关系，但建议确保所有依赖包都在 `user-ns-pkgs/` 目录中
3. **磁盘空间**：确保 rootfs 有足够的空间安装所有包
4. **架构匹配**：确保 ipk 包的架构与目标系统匹配（当前为 x86_64）

## 自定义

### 修改安装脚本

编辑 `scripts/install-user-packages.sh`，然后重新执行 `make config`。

### 添加其他服务

在 `scripts/install-user-packages.sh` 的服务启动部分添加：

```bash
if [ -x /etc/init.d/your-service ]; then
	/etc/init.d/your-service enable
	/etc/init.d/your-service start
fi
```

### 禁用自动安装

如果不想自动安装，可以：

1. 删除或重命名 `user-ns-pkgs/` 目录
2. 或者修改 `Makefile` 中的集成逻辑

## 技术细节

### uci-defaults 机制

OpenWrt 使用 `uci-defaults` 机制在首次启动时执行配置脚本。这些脚本：

- 位于 `/etc/uci-defaults/` 目录
- 按文件名排序执行
- 执行成功后自动删除
- 如果脚本返回非零退出码，不会删除（可以重试）

### rootfs-overlay

OpenWrt 构建系统会在 `prepare_rootfs` 阶段将 `$(TOPDIR)/files` 目录的内容复制到 rootfs 中，这允许我们在编译时预置文件。

### opkg 安装选项

- `--force-depends`: 强制安装，即使依赖不满足
- `--force-overwrite`: 强制覆盖已安装的包

这些选项用于处理可能的依赖和版本冲突问题。

