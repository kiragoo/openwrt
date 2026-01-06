#!/bin/sh
# 自动安装 user-ns-pkgs 中的 ipk 包
# 此脚本在首次启动时通过 uci-defaults 执行，安装完成后会被删除
# 
# 重要：此脚本会保护系统关键配置文件，确保不会因为包安装而丢失配置

PKG_DIR="/usr/lib/opkg/packages"
INSTALLED_FLAG="/etc/.user_packages_installed"
LOG_TAG="user-packages"
BACKUP_DIR="/tmp/config_backup_$$"

# 检查是否已经安装过
[ -f "$INSTALLED_FLAG" ] && exit 0

# 检查包目录是否存在
[ ! -d "$PKG_DIR" ] && exit 0

# 等待系统初始化完成
# 确保 config_generate 已经执行，关键配置文件已经生成
for i in 1 2 3 4 5 6 7 8 9 10; do
	# 检查关键配置文件是否存在（说明系统初始化已完成）
	[ -f /etc/config/network ] && [ -f /etc/config/system ] && break
	sleep 1
done

# 如果关键配置文件不存在，等待更长时间或尝试生成
if [ ! -f /etc/config/network ]; then
	logger -t "$LOG_TAG" "警告: /etc/config/network 不存在，等待系统初始化..."
	sleep 3
	# 如果仍然不存在，尝试生成（作为最后手段）
	if [ ! -f /etc/config/network ] && [ -x /bin/config_generate ]; then
		logger -t "$LOG_TAG" "尝试生成 network 配置..."
		/bin/config_generate
	fi
fi

# 等待 opkg 系统就绪
for i in 1 2 3 4 5; do
	[ -x /usr/bin/opkg ] && break
	sleep 1
done

# 检查 opkg 是否可用
[ ! -x /usr/bin/opkg ] && {
	logger -t "$LOG_TAG" "错误: opkg 不可用"
	exit 1
}

# 检查是否有包需要安装
if [ -z "$(ls -A $PKG_DIR/*.ipk 2>/dev/null)" ]; then
	logger -t "$LOG_TAG" "没有找到需要安装的包"
	exit 0
fi

# 备份关键配置文件（在安装包之前）
logger -t "$LOG_TAG" "备份关键配置文件..."
mkdir -p "$BACKUP_DIR"
CRITICAL_CONFIGS="network system firewall wireless"
for config in $CRITICAL_CONFIGS; do
	if [ -f "/etc/config/$config" ]; then
		cp "/etc/config/$config" "$BACKUP_DIR/$config"
		logger -t "$LOG_TAG" "已备份: /etc/config/$config"
	fi
done

logger -t "$LOG_TAG" "开始安装 user-ns-pkgs 中的包..."

# 安装所有 ipk 包
# 使用 --force-depends 和 --force-overwrite 来处理可能的依赖和覆盖问题
# opkg 会自动处理依赖关系
INSTALL_COUNT=0
FAILED_COUNT=0

for pkg in $PKG_DIR/*.ipk; do
	if [ -f "$pkg" ]; then
		pkg_name=$(basename "$pkg")
		logger -t "$LOG_TAG" "正在安装: $pkg_name"
		
		if opkg install --force-depends --force-overwrite "$pkg" >/tmp/opkg_install.log 2>&1; then
			INSTALL_COUNT=$((INSTALL_COUNT + 1))
			logger -t "$LOG_TAG" "成功安装: $pkg_name"
		else
			FAILED_COUNT=$((FAILED_COUNT + 1))
			logger -t "$LOG_TAG" "安装失败: $pkg_name"
			logger -t "$LOG_TAG" "$(cat /tmp/opkg_install.log)"
		fi
	fi
done

# 恢复和保护关键配置文件（在安装包之后）
logger -t "$LOG_TAG" "检查并恢复关键配置文件..."
for config in $CRITICAL_CONFIGS; do
	backup_file="$BACKUP_DIR/$config"
	config_file="/etc/config/$config"
	
	if [ -f "$backup_file" ]; then
		# 如果配置文件被删除或损坏，从备份恢复
		if [ ! -f "$config_file" ] || [ ! -s "$config_file" ]; then
			logger -t "$LOG_TAG" "恢复配置文件: $config_file"
			cp "$backup_file" "$config_file"
			chmod 0644 "$config_file"
		else
			# 如果配置文件存在，检查关键内容是否丢失
			# 对于 network 配置，检查是否有基本的接口配置
			if [ "$config" = "network" ]; then
				if ! grep -q "^config interface" "$config_file" 2>/dev/null; then
					logger -t "$LOG_TAG" "警告: network 配置可能损坏，尝试恢复..."
						# 先尝试重新生成
						if [ -x /bin/config_generate ]; then
							/bin/config_generate
							# 如果重新生成后仍然没有接口配置，则恢复备份
							if ! grep -q "^config interface" "$config_file" 2>/dev/null; then
								logger -t "$LOG_TAG" "从备份恢复 network 配置"
								cp "$backup_file" "$config_file"
								chmod 0644 "$config_file"
							fi
						else
							# 如果 config_generate 不可用，直接恢复备份
							logger -t "$LOG_TAG" "从备份恢复 network 配置"
							cp "$backup_file" "$config_file"
							chmod 0644 "$config_file"
						fi
				fi
			fi
		fi
	fi
done

# 清理备份目录
rm -rf "$BACKUP_DIR"

# 提交 UCI 配置更改
uci commit 2>/dev/null || true

# 标记已安装
touch "$INSTALLED_FLAG"

logger -t "$LOG_TAG" "安装完成: 成功 $INSTALL_COUNT 个, 失败 $FAILED_COUNT 个"

# 验证关键配置文件是否存在
MISSING_CONFIGS=""
for config in network system; do
	if [ ! -f "/etc/config/$config" ] || [ ! -s "/etc/config/$config" ]; then
		MISSING_CONFIGS="$MISSING_CONFIGS $config"
	fi
done

if [ -n "$MISSING_CONFIGS" ]; then
	logger -t "$LOG_TAG" "错误: 关键配置文件缺失: $MISSING_CONFIGS"
	logger -t "$LOG_TAG" "尝试重新生成配置..."
	[ -x /bin/config_generate ] && /bin/config_generate
	# 如果仍然缺失，返回错误（脚本不会被删除，可以重试）
	for config in $MISSING_CONFIGS; do
		if [ ! -f "/etc/config/$config" ]; then
			logger -t "$LOG_TAG" "严重错误: /etc/config/$config 仍然缺失"
			exit 1
		fi
	done
fi

# 等待系统服务完全启动后再启动我们的服务
# 确保不会干扰系统初始化
sleep 2

# 启用并启动相关服务（延迟启动，确保系统初始化完成）
if [ -x /etc/init.d/vsftpd ]; then
	/etc/init.d/vsftpd enable 2>/dev/null
	# 延迟启动，避免干扰系统初始化
	(sleep 3 && /etc/init.d/vsftpd start 2>/dev/null && logger -t "$LOG_TAG" "vsftpd 服务已启动") &
fi

if [ -x /etc/init.d/sshd ]; then
	/etc/init.d/sshd enable 2>/dev/null
	# 延迟启动，避免干扰系统初始化
	(sleep 3 && /etc/init.d/sshd start 2>/dev/null && logger -t "$LOG_TAG" "sshd 服务已启动") &
fi

# 重启相关服务以确保配置生效（延迟执行）
(sleep 5 && {
	if [ -x /etc/init.d/uhttpd ]; then
		/etc/init.d/uhttpd restart 2>/dev/null && logger -t "$LOG_TAG" "uhttpd 服务已重启"
	fi
	
	if [ -x /etc/init.d/rpcd ]; then
		/etc/init.d/rpcd restart 2>/dev/null && logger -t "$LOG_TAG" "rpcd 服务已重启"
	fi
}) &

logger -t "$LOG_TAG" "user-ns-pkgs 包安装完成，服务将在后台启动"

exit 0


