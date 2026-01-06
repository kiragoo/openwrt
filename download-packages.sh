#!/bin/bash

# OpenWrt 24.10.0 包下载脚本
VERSION="24.10.0"
ARCH="x86_64"
BASE_URL="https://downloads.openwrt.org/releases/${VERSION}/packages/${ARCH}"
TARGET_DIR="user-namespace-pkgs"

# 创建目标目录
mkdir -p "${TARGET_DIR}"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== OpenWrt ${VERSION} 包下载工具 ===${NC}"
echo ""

# 下载 Packages.gz 文件
echo -e "${YELLOW}正在获取包索引...${NC}"
wget -q -O /tmp/Packages-base.gz "${BASE_URL}/base/Packages.gz" || { echo -e "${RED}无法下载 base feed${NC}"; exit 1; }
wget -q -O /tmp/Packages-luci.gz "${BASE_URL}/luci/Packages.gz" || { echo -e "${RED}无法下载 luci feed${NC}"; exit 1; }
wget -q -O /tmp/Packages-packages.gz "${BASE_URL}/packages/Packages.gz" || { echo -e "${YELLOW}警告: 无法下载 packages feed${NC}"; }

# 提取包文件名
get_package_filename() {
    local feed=$1
    local package=$2
    local packages_file="/tmp/Packages-${feed}.gz"
    
    if [ ! -f "$packages_file" ]; then
        return 1
    fi
    
    zcat "$packages_file" | awk -v pkg="$package" '
        /^Package: / { 
            if ($2 == pkg) { 
                found=1 
            } else { 
                found=0 
            } 
        }
        found && /^Filename: / { 
            print $2 
            exit
        }
    '
}

# 下载单个包（自动尝试多个 feed）
download_package() {
    local preferred_feed=$1
    local package=$2
    
    # 尝试的 feed 顺序：首选 feed -> base -> luci -> packages
    local feeds_to_try=("$preferred_feed")
    if [ "$preferred_feed" != "base" ]; then
        feeds_to_try+=("base")
    fi
    if [ "$preferred_feed" != "luci" ]; then
        feeds_to_try+=("luci")
    fi
    if [ "$preferred_feed" != "packages" ]; then
        feeds_to_try+=("packages")
    fi
    
    local filename=""
    local found_feed=""
    
    for feed in "${feeds_to_try[@]}"; do
        filename=$(get_package_filename "$feed" "$package")
        if [ -n "$filename" ]; then
            found_feed="$feed"
            break
        fi
    done
    
    if [ -z "$filename" ]; then
        echo -e "  ${RED}未找到: ${package}${NC}"
        return 1
    fi
    
    local url="${BASE_URL}/${found_feed}/${filename}"
    local target="${TARGET_DIR}/${filename}"
    
    if [ -f "$target" ]; then
        echo -e "  ${YELLOW}已存在: ${filename}${NC}"
        return 0
    fi
    
    echo -e "  ${GREEN}下载: ${filename} (from ${found_feed} feed)${NC}"
    if wget -q -O "$target" "$url" 2>/dev/null; then
        return 0
    else
        echo -e "  ${RED}失败: ${filename}${NC}"
        return 1
    fi
}

# 主包列表
echo -e "${YELLOW}=== 下载主包 ===${NC}"

# uhttpd 及其依赖
echo -e "${GREEN}下载 uhttpd...${NC}"
download_package "base" "uhttpd"
download_package "base" "libubox20240329"
download_package "base" "libblobmsg-json20240329"
download_package "base" "libjson-script20240329"
download_package "base" "libjson-c5"

# ubus 及其依赖
echo -e "${GREEN}下载 ubus...${NC}"
download_package "base" "ubus"
download_package "base" "ubusd"
download_package "base" "libubus20250102"

# netifd 及其依赖
echo -e "${GREEN}下载 netifd...${NC}"
download_package "base" "netifd"
download_package "base" "libuci20250120"
download_package "base" "libnl-tiny1"
download_package "base" "jshn"
download_package "base" "libudebug"
download_package "base" "ucode"
download_package "base" "libucode20230711"
download_package "base" "ucode-mod-fs"

# luci-base 及其依赖
echo -e "${GREEN}下载 luci-base 及其依赖...${NC}"
download_package "luci" "luci-base"
download_package "base" "rpcd"
download_package "base" "rpcd-mod-file"
download_package "base" "rpcd-mod-ucode"
download_package "base" "rpcd-mod-luci"  # luci-base 需要
download_package "base" "rpcd-mod-iwinfo"  # luci-mod-status 和 luci-mod-network 需要
download_package "base" "libiwinfo20230701"  # rpcd-mod-iwinfo 需要（注意：包名包含版本号）
download_package "base" "libiwinfo-data"  # libiwinfo 需要
download_package "base" "ucode-mod-uci"
download_package "base" "ucode-mod-ubus"
download_package "base" "ucode-mod-math"
download_package "base" "ucode-mod-html"  # luci-base 需要
# cgi-io 在 24.10.0 中不存在，尝试从 23.05.0 下载
download_cgi_io() {
    local target="${TARGET_DIR}/cgi-io_*.ipk"
    if ls ${target} 2>/dev/null | grep -q .; then
        echo -e "  ${YELLOW}已存在: cgi-io${NC}"
        return 0
    fi
    echo -e "  ${YELLOW}尝试从 OpenWrt 23.05.0 下载 cgi-io...${NC}"
    wget -q -O /tmp/Packages-cgiio.gz "https://downloads.openwrt.org/releases/23.05.0/packages/${ARCH}/base/Packages.gz" 2>/dev/null
    if [ $? -eq 0 ]; then
        local filename=$(zcat /tmp/Packages-cgiio.gz | awk '/^Package: cgi-io$/{found=1} found && /^Filename: /{print $2; exit}')
        if [ -n "$filename" ]; then
            local url="https://downloads.openwrt.org/releases/23.05.0/packages/${ARCH}/base/${filename}"
            local target_file="${TARGET_DIR}/$(basename $filename)"
            if wget -q -O "$target_file" "$url" 2>/dev/null; then
                echo -e "  ${GREEN}下载成功: $(basename $filename) (from OpenWrt 23.05.0)${NC}"
                return 0
            fi
        fi
    fi
    echo -e "  ${RED}未找到: cgi-io${NC}"
    return 1
}
download_cgi_io
download_package "luci" "liblucihttp-ucode"
download_package "luci" "liblucihttp0"

# uhttpd 模块
echo -e "${GREEN}下载 uhttpd-mod-ubus...${NC}"
download_package "base" "uhttpd-mod-ubus"

# luci 管理界面及其依赖
echo -e "${GREEN}下载 luci-mod-admin-full 及其依赖...${NC}"
download_package "luci" "luci-mod-admin-full"
download_package "luci" "luci-mod-status"  # luci-mod-admin-full 需要
download_package "luci" "luci-mod-system"  # luci-mod-admin-full 需要
download_package "luci" "luci-mod-network"  # luci-mod-admin-full 需要

# dropbear (SSH/SFTP 服务器)
# 注意: dropbear 已包含 SFTP 服务器功能，无需单独的 dropbear-sftp-server 包
echo -e "${GREEN}下载 dropbear (SSH/SFTP 服务器)...${NC}"
download_package "base" "dropbear"
download_package "base" "zlib"  # dropbear 的依赖（如果启用了 zlib 支持）

# 递归下载依赖的函数
download_dependencies() {
    local feed=$1
    local package=$2
    local packages_file="/tmp/Packages-${feed}.gz"
    local max_depth=${3:-3}  # 最大递归深度，默认3层
    local current_depth=${4:-0}
    
    if [ $current_depth -ge $max_depth ]; then
        return 0
    fi
    
    if [ ! -f "$packages_file" ]; then
        return 1
    fi
    
    # 提取包的依赖信息
    local deps=$(zcat "$packages_file" | awk -v pkg="$package" '
        /^Package: / { 
            if ($2 == pkg) { 
                found=1 
            } else { 
                found=0 
            } 
        }
        found && /^Depends: / {
            # 提取依赖包名（去除版本号、架构等）
            gsub(/[()]/, " ", $0)
            for (i=2; i<=NF; i++) {
                if ($i ~ /^[a-zA-Z0-9_-]+$/) {
                    print $i
                } else if ($i ~ /^\+/) {
                    # 处理 +libc 这样的依赖
                    gsub(/\+/, "", $i)
                    print $i
                }
            }
        }
    ')
    
    # 下载每个依赖
    for dep in $deps; do
        # 清理依赖名称（去除版本号等）
        dep=$(echo "$dep" | sed 's/[<>=].*//' | sed 's/^+//')
        # 跳过已下载的包
        if ls "${TARGET_DIR}/${dep}"*.ipk 2>/dev/null | grep -q .; then
            continue
        fi
        # 递归下载依赖
        if [ -n "$dep" ] && [ "$dep" != "libc" ]; then
            echo -e "    ${YELLOW}发现依赖: ${dep} (深度 $((current_depth+1)))${NC}"
            download_package "base" "$dep" && download_dependencies "base" "$dep" $max_depth $((current_depth+1))
            download_package "packages" "$dep" && download_dependencies "packages" "$dep" $max_depth $((current_depth+1))
        fi
    done
}

# vsftpd (FTP 服务器) 及其依赖
echo -e "${GREEN}下载 vsftpd 及其依赖...${NC}"
download_package "packages" "vsftpd"
download_package "packages" "vsftpd-tls"  # TLS 支持版本
# vsftpd-tls 需要 libopenssl3
download_package "packages" "libopenssl3"  # vsftpd-tls 需要
# 下载 libopenssl3 的依赖（递归）
download_dependencies "packages" "libopenssl3" 2 0

# openssh-sftp-server (SFTP 服务器) 及其依赖
echo -e "${GREEN}下载 openssh-sftp-server 及其依赖...${NC}"
download_package "packages" "openssh-sftp-server"
download_package "packages" "openssh-server"  # openssh-server 主包
download_package "packages" "openssh-keygen"  # openssh-server 需要
download_package "packages" "openssh-moduli"  # 模数文件
# openssh-server 的依赖
download_package "packages" "libopenssl3"  # openssh-server 需要（如果还没下载）
download_package "packages" "libfido2-1"  # openssh-server 需要
download_package "base" "zlib"  # openssh-server 需要（如果还没下载）
# libfido2-1 的依赖
download_package "packages" "libcbor0"  # libfido2-1 需要
# 注意: libudev 在 OpenWrt 中可能不存在或由系统提供，如果下载失败可以忽略
download_package "base" "libudev"  # libfido2-1 需要（尝试 base feed）
download_package "packages" "libudev"  # libfido2-1 需要（尝试 packages feed）
download_package "packages" "libudev-zero"  # libudev 的替代方案（Provides: libudev）
# libudev-zero 的依赖
download_package "packages" "libevdev"  # libudev-zero 需要
# 下载依赖的依赖（递归）
download_dependencies "packages" "libcbor0" 2 0
download_dependencies "packages" "libevdev" 2 0
download_dependencies "packages" "libopenssl3" 2 0

echo ""
echo -e "${GREEN}=== 下载完成 ===${NC}"
echo -e "包已保存到: ${TARGET_DIR}/"
echo ""
echo "已下载的包："
ls -lh "${TARGET_DIR}"/*.ipk 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || echo "  无"
echo ""
echo -e "${YELLOW}=== 安装说明 ===${NC}"
echo "在 OpenWrt 系统上安装这些包："
echo ""
echo "1. 将 ${TARGET_DIR}/ 目录复制到 OpenWrt 系统"
echo "2. 在 OpenWrt 系统上执行："
echo ""
echo "   # 首先检查系统架构和版本："
echo "   opkg print-architecture"
echo "   cat /etc/openwrt_release"
echo ""
echo "   # 如果遇到架构不兼容错误，尝试以下方法："
echo "   # 方法1: 强制安装（如果确定包兼容）："
echo "   opkg install --force-depends --force-overwrite ${TARGET_DIR}/*.ipk"
echo ""
echo "   # 方法2: 正常安装（推荐，但可能因架构问题失败）："
echo "   opkg install ${TARGET_DIR}/*.ipk"
echo ""
echo "   # 方法3: 如果 cgi-io 缺失导致失败，可以尝试跳过："
echo "   opkg install --force-depends ${TARGET_DIR}/*.ipk"
echo ""
echo "3. 如果仍有依赖问题，确保已更新包列表："
echo "   opkg update"
echo ""
echo "4. 安装完成后，重启服务："
echo "   /etc/init.d/uhttpd restart"
echo "   /etc/init.d/rpcd restart"
echo ""
echo -e "${RED}重要提示:${NC}"
echo "  - 如果出现架构不兼容，请检查系统架构是否与脚本中的 ARCH=${ARCH} 匹配"
echo "  - 如果系统架构不同，需要修改脚本中的 ARCH 变量并重新下载"
echo "  - cgi-io 包可能在新版本中已不需要，如果安装失败可以尝试 --force-depends"
echo "  - 确保 OpenWrt 版本与脚本中的 VERSION=${VERSION} 匹配"
echo ""
echo -e "${GREEN}已下载的服务包:${NC}"
echo "  - vsftpd: FTP 服务器 (包含 vsftpd 和 vsftpd-tls)"
echo "  - openssh-sftp-server: SFTP 服务器"
echo "  - openssh-server: OpenSSH 服务器"
echo ""
echo "已下载的依赖包:"
echo "  - libopenssl3: vsftpd-tls 和 openssh-server 需要"
echo "  - libfido2-1: openssh-server 需要"
echo "  - libcbor0: libfido2-1 需要"
echo "  - libudev-zero: libfido2-1 需要（提供 libudev）"
echo "  - libevdev: libudev-zero 需要"
echo ""
echo "安装后启动服务："
echo "  /etc/init.d/vsftpd start    # 启动 FTP 服务器"
echo "  /etc/init.d/sshd start      # 启动 OpenSSH 服务器"
echo "  /etc/init.d/vsftpd enable   # 设置开机自启"
echo "  /etc/init.d/sshd enable     # 设置开机自启"

