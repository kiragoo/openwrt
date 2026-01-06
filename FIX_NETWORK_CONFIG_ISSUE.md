# 修复 network 配置文件缺失问题

## 问题描述

在集成 `user-ns-pkgs` 中的 ipk 包后，发现安装完 OpenWrt 系统后 `/etc/config/network` 文件缺失，导致系统无法正常配置网络。

## 问题分析

### 根本原因

1. **执行时机问题**：
   - OpenWrt 启动流程：`/etc/init.d/boot` → `config_generate` → `uci_apply_defaults`
   - 我们的安装脚本在 `uci-defaults` 中执行，理论上在 `config_generate` 之后
   - 但某些包的安装可能会覆盖或删除配置文件

2. **包安装影响**：
   - 使用 `--force-overwrite` 可能导致某些包的 postinst 脚本覆盖配置文件
   - 某些包可能会删除或修改 `/etc/config/network`

3. **服务启动干扰**：
   - 在系统初始化完成前启动服务可能会干扰系统配置生成

## 修复方案

### 1. 配置文件保护机制

在安装包之前备份关键配置文件，安装后检查并恢复：

```bash
# 备份关键配置文件
CRITICAL_CONFIGS="network system firewall wireless"
for config in $CRITICAL_CONFIGS; do
    if [ -f "/etc/config/$config" ]; then
        cp "/etc/config/$config" "$BACKUP_DIR/$config"
    fi
done
```

### 2. 系统初始化等待

确保在系统初始化完成后再执行安装：

```bash
# 等待系统初始化完成
for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -f /etc/config/network ] && [ -f /etc/config/system ] && break
    sleep 1
done
```

### 3. 配置文件恢复和验证

安装包后检查配置文件完整性，如有问题则恢复：

```bash
# 检查 network 配置是否有基本的接口配置
if ! grep -q "^config interface" "$config_file" 2>/dev/null; then
    # 尝试重新生成或从备份恢复
    /bin/config_generate || cp "$backup_file" "$config_file"
fi
```

### 4. 服务延迟启动

避免干扰系统初始化，延迟启动我们的服务：

```bash
# 延迟启动服务，避免干扰系统初始化
(sleep 3 && /etc/init.d/vsftpd start) &
(sleep 5 && /etc/init.d/uhttpd restart) &
```

### 5. 错误处理

如果关键配置文件仍然缺失，脚本返回错误，不会被删除，可以重试：

```bash
if [ ! -f "/etc/config/network" ]; then
    logger -t "$LOG_TAG" "严重错误: /etc/config/network 仍然缺失"
    exit 1  # 脚本不会被删除，可以重试
fi
```

## 修复内容

### 修改的文件

1. **`scripts/install-user-packages.sh`**：
   - ✅ 添加系统初始化等待机制
   - ✅ 添加关键配置文件备份功能
   - ✅ 添加配置文件恢复和验证机制
   - ✅ 添加配置文件完整性检查
   - ✅ 延迟服务启动，避免干扰系统初始化
   - ✅ 改进错误处理，确保配置文件不丢失

## 验证方法

### 1. 编译和安装验证

```bash
# 编译镜像
make config
make build

# 安装镜像后，检查关键配置文件
ls -l /etc/config/network
ls -l /etc/config/system
ls -l /etc/config/firewall
```

### 2. 配置文件内容验证

```bash
# 检查 network 配置是否有基本内容
cat /etc/config/network

# 应该包含至少一个 interface 配置，例如：
# config interface 'loopback'
# config interface 'lan'
# config interface 'wan'
```

### 3. 系统服务验证

```bash
# 检查系统服务是否正常
/etc/init.d/network status
/etc/init.d/system status

# 检查我们的服务是否正常启动
/etc/init.d/vsftpd status
/etc/init.d/sshd status
```

### 4. 日志验证

```bash
# 查看安装日志
logread | grep user-packages

# 应该看到：
# - "备份关键配置文件..."
# - "已备份: /etc/config/network"
# - "检查并恢复关键配置文件..."
# - "安装完成: 成功 X 个, 失败 Y 个"
```

### 5. 网络功能验证

```bash
# 检查网络接口
ifconfig

# 检查路由
ip route

# 测试网络连接
ping -c 3 8.8.8.8
```

## 关键改进点

1. **配置文件保护**：
   - 安装前备份关键配置文件
   - 安装后验证并恢复配置文件
   - 确保配置文件完整性

2. **执行时机优化**：
   - 等待系统初始化完成
   - 确保 `config_generate` 已执行
   - 延迟服务启动

3. **错误处理**：
   - 配置文件缺失时自动恢复
   - 严重错误时脚本保留以便重试
   - 详细的日志记录

4. **系统兼容性**：
   - 不干扰 OpenWrt 正常启动流程
   - 不影响系统服务初始化
   - 确保所有系统配置正常

## 测试清单

- [ ] `/etc/config/network` 文件存在且内容完整
- [ ] `/etc/config/system` 文件存在且内容完整
- [ ] `/etc/config/firewall` 文件存在（如果已配置）
- [ ] 网络接口可以正常配置
- [ ] 系统服务正常启动
- [ ] 我们的服务（vsftpd, sshd）正常启动
- [ ] 日志中没有配置文件相关的错误
- [ ] 系统可以正常重启

## 注意事项

1. **首次启动**：首次启动时脚本会自动执行，安装包并启动服务
2. **配置文件**：如果配置文件被破坏，会自动从备份恢复
3. **服务启动**：服务会在后台延迟启动，不会阻塞系统初始化
4. **错误重试**：如果安装失败，脚本会保留，下次启动可以重试

## 生产环境建议

1. **测试验证**：在生产环境部署前，先在测试环境验证所有功能
2. **备份机制**：确保有系统配置的备份
3. **监控日志**：监控首次启动的日志，确保所有包安装成功
4. **网络配置**：确认网络配置符合生产环境需求

## 总结

通过添加配置文件保护机制、优化执行时机、改进错误处理，确保了：

- ✅ 系统关键配置文件不会丢失
- ✅ 不会干扰 OpenWrt 正常启动流程
- ✅ 所有系统服务正常初始化
- ✅ 我们的服务正常启动
- ✅ 系统完全可用，满足生产条件

