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
	cd $(BUILD_DIR) && make defconfig

menuconfig: feeds
	@echo "$(COLOR_GREEN)打开配置菜单...$(COLOR_RESET)"
	cd $(BUILD_DIR) && make menuconfig
	@echo "$(COLOR_YELLOW)保存配置到 $(CONFIG_FILE)...$(COLOR_RESET)"
	cp $(BUILD_DIR)/.config $(CONFIG_FILE)

build: config
	@echo "$(COLOR_GREEN)开始编译 OpenWrt (使用 $(JOBS) 个并行任务)...$(COLOR_RESET)"
	cd $(BUILD_DIR) && make -j$(JOBS) V=s

clean:
	@echo "$(COLOR_YELLOW)清理构建文件...$(COLOR_RESET)"
	@if [ -d "$(BUILD_DIR)" ]; then \
		cd $(BUILD_DIR) && make clean; \
	fi

distclean:
	@echo "$(COLOR_YELLOW)完全清理...$(COLOR_RESET)"
	@if [ -d "$(BUILD_DIR)" ]; then \
		cd $(BUILD_DIR) && make distclean; \
	fi
	rm -rf $(BUILD_DIR)

# 快捷目标
rebuild: clean build

# 显示编译输出位置
show-images:
	@echo "$(COLOR_BLUE)编译产物位置:$(COLOR_RESET)"
	@if [ -d "$(BUILD_DIR)/bin/targets" ]; then \
		find $(BUILD_DIR)/bin/targets -name "*.img.gz" -o -name "*.bin"; \
	else \
		echo "$(COLOR_YELLOW)未找到编译产物$(COLOR_RESET)"; \
	fi
