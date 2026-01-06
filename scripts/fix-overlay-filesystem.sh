#!/bin/sh
# 修复 OpenWrt overlay 文件系统问题
# 解决 /etc/config/network 无权限和 uci I/O error 问题

LOG_TAG="fix-overlay"

logger -t "$LOG_TAG" "开始检查 overlay 文件系统..."

# 检查 overlay 是否已挂载
if ! mount | grep -q "overlay on /overlay"; then
	logger -t "$LOG_TAG" "警告: overlay 文件系统未挂载，尝试修复..."
	
	# 检查 rootfs_data 分区
	if [ -b /dev/sda2 ] || [ -b /dev/vda2 ] || [ -b /dev/hda2 ]; then
		# 尝试找到 rootfs_data 分区
		ROOTFS_DATA=""
		for dev in /dev/sda2 /dev/vda2 /dev/hda2 /dev/nvme0n1p2; do
			if [ -b "$dev" ]; then
				ROOTFS_DATA="$dev"
				break
			fi
		done
		
		if [ -n "$ROOTFS_DATA" ]; then
			logger -t "$LOG_TAG" "找到 rootfs_data 分区: $ROOTFS_DATA"
			
			# 检查文件系统类型
			FS_TYPE=$(blkid -s TYPE -o value "$ROOTFS_DATA" 2>/dev/null || echo "")
			
			if [ -z "$FS_TYPE" ]; then
				logger -t "$LOG_TAG" "格式化 rootfs_data 分区..."
				mkfs.ext4 -F -L rootfs_data "$ROOTFS_DATA" 2>&1 | logger -t "$LOG_TAG"
				FS_TYPE="ext4"
			fi
			
			# 创建挂载点
			mkdir -p /mnt/rootfs_data
			
			# 挂载 rootfs_data
			if mount -t "$FS_TYPE" "$ROOTFS_DATA" /mnt/rootfs_data 2>&1 | logger -t "$LOG_TAG"; then
				logger -t "$LOG_TAG" "rootfs_data 分区挂载成功"
				
				# 创建 overlay 目录结构
				mkdir -p /mnt/rootfs_data/upper
				mkdir -p /mnt/rootfs_data/work
				
				# 挂载 overlay
				if mount -t overlay overlay -o lowerdir=/,upperdir=/mnt/rootfs_data/upper,workdir=/mnt/rootfs_data/work /overlay 2>&1 | logger -t "$LOG_TAG"; then
					logger -t "$LOG_TAG" "overlay 文件系统挂载成功"
					
					# 创建必要的目录
					mkdir -p /overlay/upper/etc/config
					mkdir -p /overlay/upper/etc/uci-defaults
					
					# 设置权限
					chmod 755 /overlay/upper/etc/config
					chmod 755 /overlay/upper/etc/uci-defaults
					
					# 重新挂载根文件系统为 overlay
					mount -o remount /overlay /
					
					logger -t "$LOG_TAG" "overlay 文件系统修复完成"
				else
					logger -t "$LOG_TAG" "错误: 无法挂载 overlay"
					umount /mnt/rootfs_data 2>/dev/null
					return 1
				fi
			else
				logger -t "$LOG_TAG" "错误: 无法挂载 rootfs_data 分区"
				return 1
			fi
		else
			logger -t "$LOG_TAG" "错误: 未找到 rootfs_data 分区"
			return 1
		fi
	else
		logger -t "$LOG_TAG" "警告: 未找到标准 rootfs_data 分区，可能需要手动配置"
	fi
else
	logger -t "$LOG_TAG" "overlay 文件系统已正确挂载"
fi

# 检查 overlay 空间
OVERLAY_FREE=$(df /overlay 2>/dev/null | tail -1 | awk '{print $4}')
if [ -n "$OVERLAY_FREE" ] && [ "$OVERLAY_FREE" -lt 1024 ]; then
	logger -t "$LOG_TAG" "警告: overlay 空间不足 (${OVERLAY_FREE}KB)"
fi

# 检查配置文件权限
if [ -d /overlay/upper/etc/config ]; then
	# 确保配置文件目录可写
	chmod 755 /overlay/upper/etc/config 2>/dev/null
	
	# 检查并修复关键配置文件权限
	for config in network system firewall; do
		config_file="/overlay/upper/etc/config/$config"
		if [ -f "$config_file" ]; then
			chmod 644 "$config_file" 2>/dev/null
			logger -t "$LOG_TAG" "已修复权限: $config_file"
		fi
	done
fi

# 验证 uci 是否可以正常工作
if command -v uci >/dev/null 2>&1; then
	if uci show >/dev/null 2>&1; then
		logger -t "$LOG_TAG" "uci 工作正常"
	else
		logger -t "$LOG_TAG" "警告: uci 无法正常工作，可能需要重启"
	fi
fi

logger -t "$LOG_TAG" "overlay 文件系统检查完成"

exit 0

