# 修复 uci-defaults 脚本未执行问题

## 问题描述

通过制作好的 img 镜像安装 OpenWrt 系统时，`/etc/uci-defaults/99_install_user_packages` 脚本没有被执行，相关的包都没有被安装。

## 问题分析

### 可能的原因

1. **脚本提前退出**
   - 脚本在第13行检查包目录是否存在：`[ ! -d "$PKG_DIR" ] && exit 0`
   - 在 uci-defaults 执行时，文件系统可能还没有完全挂载，导致目录检查失败
   - 脚本静默退出（exit 0），会被 uci_apply_defaults 删除，无法重试

2. **opkg 不可用**
   - 脚本在第22-25行检查 opkg 是否可用
   - 如果 opkg 不可用，脚本返回错误码1，不会被删除，但也不会执行安装

3. **执行时机问题**
   - uci-defaults 在 `/etc/init.d/boot` 的 `boot()` 函数中执行
   - 执行时机可能在文件系统完全挂载之前
   - `/usr/lib/opkg/packages` 目录可能还没有被创建

4. **脚本版本不一致**
   - 镜像中的脚本是旧版本，缺少系统初始化等待机制
   - 缺少配置文件保护机制

### uci_apply_defaults 执行机制

从 `/etc/init.d/boot` 中可以看到：

```bash
uci_apply_defaults() {
    cd /etc/uci-defaults || return 0
    files="$(ls)"
    [ -z "$files" ] && return 0
    for file in $files; do
        ( . "./$(basename $file)" ) && rm -f "$file"
    done
    uci commit
}
```

关键点：
- 脚本执行成功（返回0）后会被删除
- 脚本执行失败（返回非0）后不会被删除，可以重试
- 脚本在子shell中执行，不会影响主进程

## 解决方案

### 1. 更新脚本到最新版本

将 `scripts/install-user-packages.sh` 的最新版本复制到镜像中，包含：
- 系统初始化等待机制
- 配置文件保护机制
- 更好的错误处理

### 2. 增强脚本的健壮性

添加以下改进：
- 更长的等待时间，确保文件系统完全挂载
- 更详细的日志记录，便于排查问题
- 检查文件系统是否可写
- 检查包目录是否真的存在且包含文件

### 3. 添加调试日志

在脚本关键位置添加日志，便于排查问题：
- 脚本开始执行
- 每个检查点的结果
- 执行失败的原因

## 修复步骤

1. 更新镜像中的脚本文件
2. 增强脚本的健壮性
3. 添加详细的日志记录
4. 测试验证

