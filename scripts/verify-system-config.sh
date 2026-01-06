#!/bin/sh
# 系统配置验证脚本
# 用于验证 OpenWrt 系统配置是否完整和正确

VERIFY_FAILED=0

echo "=== OpenWrt 系统配置验证 ==="
echo ""

# 检查关键配置文件
echo "1. 检查关键配置文件..."
CRITICAL_CONFIGS="network system"
for config in $CRITICAL_CONFIGS; do
    config_file="/etc/config/$config"
    if [ -f "$config_file" ]; then
        if [ -s "$config_file" ]; then
            echo "  ✓ $config_file 存在且非空"
        else
            echo "  ✗ $config_file 存在但为空"
            VERIFY_FAILED=1
        fi
    else
        echo "  ✗ $config_file 不存在"
        VERIFY_FAILED=1
    fi
done

# 检查 network 配置内容
echo ""
echo "2. 检查 network 配置内容..."
if [ -f /etc/config/network ]; then
    if grep -q "^config interface" /etc/config/network; then
        interface_count=$(grep -c "^config interface" /etc/config/network)
        echo "  ✓ network 配置包含 $interface_count 个接口配置"
    else
        echo "  ✗ network 配置缺少接口配置"
        VERIFY_FAILED=1
    fi
else
    echo "  ✗ /etc/config/network 不存在"
    VERIFY_FAILED=1
fi

# 检查系统服务
echo ""
echo "3. 检查系统服务..."
SYSTEM_SERVICES="network system"
for service in $SYSTEM_SERVICES; do
    if [ -x "/etc/init.d/$service" ]; then
        echo "  ✓ /etc/init.d/$service 存在"
    else
        echo "  ✗ /etc/init.d/$service 不存在"
        VERIFY_FAILED=1
    fi
done

# 检查我们的服务
echo ""
echo "4. 检查 user-ns-pkgs 相关服务..."
USER_SERVICES="vsftpd sshd uhttpd rpcd"
for service in $USER_SERVICES; do
    if [ -x "/etc/init.d/$service" ]; then
        echo "  ✓ /etc/init.d/$service 存在"
    else
        echo "  - /etc/init.d/$service 不存在（可能未安装）"
    fi
done

# 检查网络接口
echo ""
echo "5. 检查网络接口..."
if command -v ifconfig >/dev/null 2>&1; then
    interface_count=$(ifconfig 2>/dev/null | grep -c "^[a-z]" || echo "0")
    if [ "$interface_count" -gt 0 ]; then
        echo "  ✓ 发现 $interface_count 个网络接口"
    else
        echo "  ✗ 未发现网络接口"
        VERIFY_FAILED=1
    fi
elif command -v ip >/dev/null 2>&1; then
    interface_count=$(ip link show 2>/dev/null | grep -c "^[0-9]" || echo "0")
    if [ "$interface_count" -gt 0 ]; then
        echo "  ✓ 发现 $interface_count 个网络接口"
    else
        echo "  ✗ 未发现网络接口"
        VERIFY_FAILED=1
    fi
else
    echo "  - 无法检查网络接口（命令不可用）"
fi

# 检查安装标志
echo ""
echo "6. 检查包安装状态..."
if [ -f /etc/.user_packages_installed ]; then
    echo "  ✓ user-ns-pkgs 包已安装"
else
    echo "  - user-ns-pkgs 包未安装（首次启动时会自动安装）"
fi

# 检查安装日志
echo ""
echo "7. 检查安装日志..."
if command -v logread >/dev/null 2>&1; then
    log_count=$(logread | grep -c "user-packages" || echo "0")
    if [ "$log_count" -gt 0 ]; then
        echo "  ✓ 发现 $log_count 条 user-packages 相关日志"
        echo "  最近 5 条日志："
        logread | grep "user-packages" | tail -5 | sed 's/^/    /'
    else
        echo "  - 未发现 user-packages 相关日志"
    fi
else
    echo "  - 无法检查日志（logread 命令不可用）"
fi

# 总结
echo ""
echo "=== 验证结果 ==="
if [ $VERIFY_FAILED -eq 0 ]; then
    echo "✓ 系统配置验证通过"
    exit 0
else
    echo "✗ 系统配置验证失败，请检查上述错误"
    exit 1
fi

