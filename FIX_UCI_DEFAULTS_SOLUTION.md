# uci-defaults 脚本未执行问题 - 解决方案

## 问题总结

通过制作好的 img 镜像安装 OpenWrt 系统时，`/etc/uci-defaults/99_install_user_packages` 脚本没有被执行，相关的包都没有被安装。

## 根本原因

### 1. 脚本版本不一致
- 镜像中的脚本是旧版本，缺少系统初始化等待机制
- 缺少配置文件保护机制

### 2. 脚本提前退出
- **关键问题**：脚本在第13行检查包目录是否存在：`[ ! -d "$PKG_DIR" ] && exit 0`
- 在 uci-defaults 执行时，文件系统可能还没有完全挂载，导致目录检查失败
- 脚本静默退出（exit 0），会被 `uci_apply_defaults` 删除，无法重试

### 3. 执行时机问题
- uci-defaults 在 `/etc/init.d/boot` 的 `boot()` 函数中执行
- 执行时机可能在文件系统完全挂载之前
- `/usr/lib/opkg/packages` 目录可能还没有被创建

## 解决方案

### 1. 增强脚本的健壮性

#### 添加文件系统等待机制
```bash
# 等待文件系统完全挂载和包目录创建
logger -t "$LOG_TAG" "等待文件系统和包目录就绪..."
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
	if [ -d "$PKG_DIR" ] && [ -n "$(ls -A $PKG_DIR/*.ipk 2>/dev/null)" ]; then
		logger -t "$LOG_TAG" "包目录已就绪，找到 $(ls -1 $PKG_DIR/*.ipk 2>/dev/null | wc -l) 个包文件"
		break
	fi
	sleep 1
done
```

#### 改进错误处理
- 如果包目录不存在，返回错误码1（而不是0），这样脚本不会被删除，可以重试
- 添加详细的日志记录，便于排查问题

### 2. 添加详细的日志记录

在脚本关键位置添加日志：
- 脚本开始执行
- 文件系统等待状态
- 包目录检查结果
- opkg 就绪状态
- 每个安装步骤的结果

### 3. 恢复配置文件保护机制

添加了完整的配置文件保护机制：
- 安装前备份关键配置文件
- 安装后检查并恢复配置文件
- 验证配置文件完整性

## 修复内容

### 主要改进

1. **文件系统等待机制**
   - 等待最多15秒，确保文件系统完全挂载
   - 检查包目录是否存在且包含文件

2. **错误处理改进**
   - 如果包目录不存在，返回错误码1（可重试）
   - 如果 opkg 不可用，返回错误码1（可重试）
   - 如果配置文件缺失，返回错误码1（可重试）

3. **日志记录增强**
   - 记录脚本执行的每个关键步骤
   - 记录等待状态和检查结果
   - 记录安装成功和失败的详细信息

4. **配置文件保护**
   - 安装前备份关键配置文件
   - 安装后检查并恢复配置文件
   - 验证配置文件完整性

## 验证方法

### 1. 检查脚本是否正确更新

```bash
# 检查脚本内容
cat /root/CodeRepo/openwrt/openwrt/files/etc/uci-defaults/99_install_user_packages

# 检查脚本行数（应该约190行）
wc -l /root/CodeRepo/openwrt/openwrt/files/etc/uci-defaults/99_install_user_packages
```

### 2. 重新编译镜像

```bash
# 重新执行 config（会更新脚本）
make config

# 编译镜像
make build
```

### 3. 在 OpenWrt 系统上验证

```bash
# 查看安装日志
logread | grep user-packages

# 应该看到：
# - "脚本开始执行: 99_install_user_packages"
# - "等待文件系统和包目录就绪..."
# - "包目录已就绪，找到 X 个包文件"
# - "开始安装 user-ns-pkgs 中的包..."
# - "安装完成: 成功 X 个, 失败 Y 个"

# 检查包是否已安装
opkg list-installed | grep -E "(k3s|luci|uhttpd|rpcd)"

# 检查服务是否已启动
/etc/init.d/vsftpd status
/etc/init.d/sshd status
```

### 4. 如果脚本仍然未执行

检查脚本是否还在：
```bash
ls -l /etc/uci-defaults/99_install_user_packages
```

如果脚本还在，说明执行失败（返回了非零退出码），可以：
1. 查看日志：`logread | grep user-packages`
2. 手动执行：`/etc/uci-defaults/99_install_user_packages`
3. 检查错误原因并修复

## 关键改进点

### 1. 等待机制
- **文件系统等待**：最多等待15秒，确保文件系统完全挂载
- **系统初始化等待**：等待 config_generate 执行完成
- **opkg 等待**：等待 opkg 系统就绪

### 2. 错误处理
- **可重试的错误**：返回错误码1，脚本不会被删除
- **正常退出**：返回0，脚本会被删除
- **详细日志**：记录所有错误信息

### 3. 配置文件保护
- **备份机制**：安装前备份关键配置文件
- **恢复机制**：安装后检查并恢复配置文件
- **验证机制**：验证配置文件完整性

## 注意事项

1. **脚本执行时机**：脚本在系统启动的 boot 阶段执行，此时文件系统可能还没有完全挂载
2. **重试机制**：如果脚本执行失败（返回非零退出码），脚本不会被删除，下次启动可以重试
3. **日志查看**：如果脚本未执行，查看日志了解具体原因
4. **手动执行**：如果脚本还在，可以手动执行进行测试

## 相关文件

- 脚本位置：`/root/CodeRepo/openwrt/openwrt/files/etc/uci-defaults/99_install_user_packages`
- 源脚本：`/root/CodeRepo/openwrt/scripts/install-user-packages.sh`
- 问题分析：`/root/CodeRepo/openwrt/FIX_UCI_DEFAULTS_NOT_EXECUTED.md`

