# OpenWrt Build Makefile
# 可配置的变量

# OpenWrt 版本
OPENWRT_VERSION ?= 24.10.0
OPENWRT_BRANCH ?= v$(OPENWRT_VERSION)

# 架构配置
TARGET_ARCH ?= x86
TARGET_SUBARCH ?= 64
TARGET_PROFILE ?= Generic

# 构建配置
BUILD_DIR ?= openwrt
CONFIG_FILE ?= config-k3s
JOBS ?= $(shell nproc)

# 下载源
OPENWRT_REPO ?= https://github.com/openwrt/openwrt.git

# 颜色输出
COLOR_RESET = \033[0m
COLOR_GREEN = \033[32m
COLOR_YELLOW = \033[33m
COLOR_BLUE = \033[34m

.PHONY: all help download feeds config build clean distclean menuconfig info

all: build

help:
	@echo "$(COLOR_BLUE)OpenWrt 构建系统$(COLOR_RESET)"
	@echo ""
	@echo "可用目标:"
	@echo "  $(COLOR_GREEN)download$(COLOR_RESET)    - 下载 OpenWrt 源码"
	@echo "  $(COLOR_GREEN)feeds$(COLOR_RESET)       - 更新和安装 feeds"
	@echo "  $(COLOR_GREEN)config$(COLOR_RESET)      - 应用配置文件"
	@echo "  $(COLOR_GREEN)menuconfig$(COLOR_RESET)  - 打开配置菜单"
	@echo "  $(COLOR_GREEN)build$(COLOR_RESET)       - 编译 OpenWrt"
	@echo "  $(COLOR_GREEN)clean$(COLOR_RESET)       - 清理构建文件"
	@echo "  $(COLOR_GREEN)distclean$(COLOR_RESET)   - 完全清理（包括源码）"
	@echo "  $(COLOR_GREEN)info$(COLOR_RESET)        - 显示当前配置信息"
	@echo ""
	@echo "可配置变量:"
	@echo "  OPENWRT_VERSION  - OpenWrt 版本 (默认: $(OPENWRT_VERSION))"
	@echo "  TARGET_ARCH      - 目标架构 (默认: $(TARGET_ARCH))"
	@echo "  TARGET_SUBARCH   - 子架构 (默认: $(TARGET_SUBARCH))"
	@echo "  CONFIG_FILE      - 配置文件 (默认: $(CONFIG_FILE))"
	@echo "  JOBS             - 并行编译任务数 (默认: $(JOBS))"
	@echo ""
	@echo "示例:"
	@echo "  make download"
	@echo "  make build"
	@echo "  make OPENWRT_VERSION=23.05.2 download"
	@echo "  make JOBS=8 build"
	@echo "  make CONFIG_FILE=config-custom build"

info:
	@echo "$(COLOR_BLUE)当前配置:$(COLOR_RESET)"
	@echo "  OpenWrt 版本: $(COLOR_YELLOW)$(OPENWRT_VERSION)$(COLOR_RESET)"
	@echo "  目标架构: $(COLOR_YELLOW)$(TARGET_ARCH)/$(TARGET_SUBARCH)$(COLOR_RESET)"
	@echo "  构建目录: $(COLOR_YELLOW)$(BUILD_DIR)$(COLOR_RESET)"
	@echo "  配置文件: $(COLOR_YELLOW)$(CONFIG_FILE)$(COLOR_RESET)"
	@echo "  并行任务: $(COLOR_YELLOW)$(JOBS)$(COLOR_RESET)"

download:
	@echo "$(COLOR_GREEN)下载 OpenWrt $(OPENWRT_VERSION)...$(COLOR_RESET)"
	@if [ -d "$(BUILD_DIR)" ]; then \
		echo "$(COLOR_YELLOW)构建目录已存在，跳过下载$(COLOR_RESET)"; \
	else \
		git clone --branch $(OPENWRT_BRANCH) --depth 1 $(OPENWRT_REPO) $(BUILD_DIR); \
	fi

feeds: download
	@echo "$(COLOR_GREEN)更新 feeds...$(COLOR_RESET)"
	cd $(BUILD_DIR) && ./scripts/feeds update -a
	@echo "$(COLOR_GREEN)安装 feeds...$(COLOR_RESET)"
	cd $(BUILD_DIR) && ./scripts/feeds install -a

config: feeds
	@echo "$(COLOR_GREEN)应用配置文件...$(COLOR_RESET)"
	@if [ ! -f "$(CONFIG_FILE)" ]; then \
		echo "$(COLOR_YELLOW)警告: 配置文件 $(CONFIG_FILE) 不存在$(COLOR_RESET)"; \
		exit 1; \
	fi
	cp $(CONFIG_FILE) $(BUILD_DIR)/.config
	@echo "$(COLOR_GREEN)集成 user-ns-pkgs 中的 ipk 包到镜像...$(COLOR_RESET)"
	@if [ -d "user-ns-pkgs" ] && [ -n "$$(ls -A user-ns-pkgs/*.ipk 2>/dev/null)" ]; then \
		mkdir -p $(BUILD_DIR)/files/usr/lib/opkg/packages; \
		cp user-ns-pkgs/*.ipk $(BUILD_DIR)/files/usr/lib/opkg/packages/; \
		echo "$(COLOR_GREEN)已复制 $$(ls -1 user-ns-pkgs/*.ipk 2>/dev/null | wc -l) 个 ipk 包到镜像$(COLOR_RESET)"; \
	else \
		echo "$(COLOR_YELLOW)警告: user-ns-pkgs 目录不存在或为空，跳过 ipk 集成$(COLOR_RESET)"; \
	fi
	@echo "$(COLOR_GREEN)创建首次启动安装脚本...$(COLOR_RESET)"
	@mkdir -p $(BUILD_DIR)/files/etc/uci-defaults
	@if [ -f scripts/install-user-packages.sh ]; then \
		cp scripts/install-user-packages.sh $(BUILD_DIR)/files/etc/uci-defaults/99_install_user_packages; \
		chmod +x $(BUILD_DIR)/files/etc/uci-defaults/99_install_user_packages; \
	else \
		echo "$(COLOR_YELLOW)警告: scripts/install-user-packages.sh 不存在，跳过安装脚本创建$(COLOR_RESET)"; \
	fi
	@echo "$(COLOR_GREEN)编译配置工具并设置目标架构: $(TARGET_ARCH)/$(TARGET_SUBARCH)$(COLOR_RESET)"
	@cd $(BUILD_DIR) && FORCE_UNSAFE_CONFIGURE=1 make defconfig 2>/dev/null || true
	@cd $(BUILD_DIR) && \
		sed -i '/^CONFIG_TARGET_/d' .config && \
		sed -i '/^CONFIG_TARGET_ROOTFS_PARTSIZE/d' .config && \
		if [ "$(TARGET_ARCH)" = "x86" ]; then \
			echo "CONFIG_TARGET_x86=y" >> .config; \
			echo "CONFIG_TARGET_x86_$(TARGET_SUBARCH)=y" >> .config; \
			echo "CONFIG_TARGET_BOARD=\"x86\"" >> .config; \
			echo "CONFIG_TARGET_SUBTARGET=\"$(TARGET_SUBARCH)\"" >> .config; \
			echo "CONFIG_TARGET_PROFILE=\"Generic\"" >> .config; \
			echo "CONFIG_TARGET_ROOTFS_EXT4FS=y" >> .config; \
			echo "CONFIG_GRUB_IMAGES=y" >> .config; \
			echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config; \
			echo "CONFIG_PACKAGE_kmod-vmxnet3=y" >> .config; \
			echo "CONFIG_PACKAGE_kmod-e1000=y" >> .config; \
			echo "CONFIG_PACKAGE_kmod-e1000e=y" >> .config; \
		elif [ "$(TARGET_ARCH)" = "armvirt" ]; then \
			echo "CONFIG_TARGET_armvirt=y" >> .config; \
			echo "CONFIG_TARGET_armvirt_$(TARGET_SUBARCH)=y" >> .config; \
			echo "CONFIG_TARGET_BOARD=\"armvirt\"" >> .config; \
			echo "CONFIG_TARGET_SUBTARGET=\"$(TARGET_SUBARCH)\"" >> .config; \
			echo "CONFIG_TARGET_PROFILE=\"Generic\"" >> .config; \
		elif [ "$(TARGET_ARCH)" = "bcm27xx" ]; then \
			echo "CONFIG_TARGET_bcm27xx=y" >> .config; \
			echo "CONFIG_TARGET_bcm27xx_$(TARGET_SUBARCH)=y" >> .config; \
			echo "CONFIG_TARGET_BOARD=\"bcm27xx\"" >> .config; \
			echo "CONFIG_TARGET_SUBTARGET=\"$(TARGET_SUBARCH)\"" >> .config; \
			echo "CONFIG_TARGET_PROFILE=\"Generic\"" >> .config; \
		fi
	@echo "$(COLOR_GREEN)从配置文件恢复 ROOTFS_PARTSIZE 设置...$(COLOR_RESET)"
	@cd $(BUILD_DIR) && \
		if grep -q "^CONFIG_TARGET_ROOTFS_PARTSIZE=" $(CURDIR)/$(CONFIG_FILE); then \
			grep "^CONFIG_TARGET_ROOTFS_PARTSIZE=" $(CURDIR)/$(CONFIG_FILE) >> .config; \
		fi
	@cd $(BUILD_DIR) && FORCE_UNSAFE_CONFIGURE=1 make defconfig

menuconfig: feeds
	@echo "$(COLOR_GREEN)打开配置菜单...$(COLOR_RESET)"
	cd $(BUILD_DIR) && FORCE_UNSAFE_CONFIGURE=1 make menuconfig
	@echo "$(COLOR_YELLOW)保存配置到 $(CONFIG_FILE)...$(COLOR_RESET)"
	cp $(BUILD_DIR)/.config $(CONFIG_FILE)

build: config
	@echo "$(COLOR_GREEN)开始编译 OpenWrt (使用 $(JOBS) 个并行任务)...$(COLOR_RESET)"
	cd $(BUILD_DIR) && FORCE_UNSAFE_CONFIGURE=1 make -j$(JOBS) V=s

clean:
	@echo "$(COLOR_YELLOW)清理构建文件...$(COLOR_RESET)"
	@if [ -d "$(BUILD_DIR)" ]; then \
		cd $(BUILD_DIR) && \
		if [ ! -f .config ]; then \
			touch .config && echo "CONFIG_HAVE_DOT_CONFIG=y" >> .config; \
		fi && \
		FORCE_UNSAFE_CONFIGURE=1 make clean; \
		rm -f .config; \
	fi

distclean:
	@echo "$(COLOR_YELLOW)完全清理...$(COLOR_RESET)"
	@if [ -d "$(BUILD_DIR)" ]; then \
		cd $(BUILD_DIR) && FORCE_UNSAFE_CONFIGURE=1 make distclean; \
	fi
	rm -rf $(BUILD_DIR)

# 快捷目标
rebuild: clean build

# 显示编译输出位置
show-images:
	@echo "$(COLOR_BLUE)编译产物位置:$(COLOR_RESET)"
	@if [ -d "$(BUILD_DIR)/bin/targets" ]; then \
		if [ "$(TARGET_ARCH)" = "x86" ]; then \
			echo "$(COLOR_GREEN)IMG 镜像文件:$(COLOR_RESET)"; \
			find $(BUILD_DIR)/bin/targets -name "*.img.gz" -o -name "*.img" | grep -E "(combined|rootfs)" | sort; \
			echo ""; \
			echo "$(COLOR_YELLOW)其他文件:$(COLOR_RESET)"; \
			find $(BUILD_DIR)/bin/targets -name "*.bin" -o -name "*.vmdk" -o -name "*.vdi" | sort; \
		else \
			find $(BUILD_DIR)/bin/targets -name "*.img.gz" -o -name "*.bin"; \
		fi \
	else \
		echo "$(COLOR_YELLOW)未找到编译产物$(COLOR_RESET)"; \
	fi
