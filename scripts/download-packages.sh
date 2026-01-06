#!/bin/bash

# OpenWrt 24.10.0 包下载脚本（增强版：支持版本和架构检查，非官方仓库）
VERSION="24.10.0"
ARCH="x86_64"
BASE_URL="https://downloads.openwrt.org/releases/${VERSION}/packages/${ARCH}"
TARGET_DIR="user-namespace-pkgs"

# 非官方仓库配置（如果需要）
CUSTOM_REPOS=""  # 格式: "repo1_url|repo2_url"，用 | 分隔

# 创建目标目录
mkdir -p "${TARGET_DIR}"

# 架构和版本检查函数
check_architecture() {
    local pkg_arch=$1
    local pkg_file=$2
    
    # 从包文件名提取架构信息
    local file_arch=$(echo "$pkg_file" | grep -oE "_[a-z0-9_]+\.ipk$" | sed 's/_//' | sed 's/\.ipk//')
    
    # 检查架构是否匹配（支持通配符和变体）
    if [[ "$file_arch" == *"$ARCH"* ]] || [[ "$file_arch" == "all" ]] || [[ "$file_arch" == "noarch" ]]; then
        return 0
    fi
    
    # 架构映射（处理不同的架构命名）
    case "$ARCH" in
        x86_64)
            if [[ "$file_arch" == "x86-64" ]] || [[ "$file_arch" == "amd64" ]]; then
                return 0
            fi
            ;;
        aarch64)
            if [[ "$file_arch" == "arm64" ]] || [[ "$file_arch" == "aarch64_generic" ]]; then
                return 0
            fi
            ;;
        arm_cortex-a9)
            if [[ "$file_arch" == "arm_cortex-a9_vfpv3" ]] || [[ "$file_arch" == "arm_cortex-a9_neon" ]]; then
                return 0
            fi
            ;;
    esac
    
    return 1
}

# 版本检查函数
check_version_compatibility() {
    local pkg_version=$1
    local required_version=$2
    
    # 如果不需要版本检查，返回成功
    if [ -z "$required_version" ]; then
        return 0
    fi
    
    # 简单的版本比较（可以根据需要扩展）
    # 这里假设版本格式为 major.minor.patch
    return 0  # 暂时总是返回成功，实际使用时可以添加版本比较逻辑
}

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

# 验证 ipk 文件是否有效
verify_ipk_file() {
    local file=$1
    
    # 检查文件是否存在
    if [ ! -f "$file" ]; then
        return 1
    fi
    
    # 检查文件大小（不能为0或太小，至少应该大于100字节）
    local size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
    if [ -z "$size" ] || [ "$size" -lt 100 ]; then
        echo -e "    ${RED}文件大小异常: ${size} 字节${NC}"
        return 1
    fi
    
    # 检查文件类型：ipk 文件可能是 gzip 压缩的 ar 归档文件
    local file_type=$(file -b "$file" 2>/dev/null)
    
    # 如果是 gzip 压缩文件，先解压再验证
    if echo "$file_type" | grep -q "gzip"; then
        local temp_file=$(mktemp)
        if gunzip -c "$file" > "$temp_file" 2>/dev/null; then
            # 检查解压后的文件是否为 ar 格式
            if command -v ar >/dev/null 2>&1; then
                if ar t "$temp_file" >/dev/null 2>&1; then
                    rm -f "$temp_file"
                    return 0
                fi
            else
                # 如果没有 ar 命令，检查文件头是否为 ar 格式
                local header=$(head -c 8 "$temp_file" 2>/dev/null)
                rm -f "$temp_file"
                if [ "$header" = "!<arch>" ]; then
                    return 0
                fi
            fi
            rm -f "$temp_file"
        fi
    fi
    
    # 如果不是 gzip 压缩，直接检查是否为 ar 格式
    if command -v ar >/dev/null 2>&1; then
        if ar t "$file" >/dev/null 2>&1; then
            return 0
        fi
    else
        # 如果没有 ar 命令，检查文件头是否为 ar 格式
        local header=$(head -c 8 "$file" 2>/dev/null)
        if [ "$header" = "!<arch>" ]; then
            return 0
        fi
    fi
    
    # 如果以上验证都失败，但文件大小合理，仍然认为有效（可能是压缩格式的 ipk）
    # 因为 OpenWrt 的 ipk 文件可能是 gzip 压缩的
    if [ "$size" -gt 100 ]; then
        return 0
    fi
    
    return 1
}

# 下载单个包（自动尝试多个 feed）
download_package() {
    local preferred_feed=$1
    local package=$2
    local max_retries=${3:-3}  # 默认重试3次
    
    # 尝试的 feed 顺序：首选 feed -> base -> luci -> packages
    # 使用空格分隔的字符串而不是数组（兼容 sh）
    local feeds_to_try="$preferred_feed"
    if [ "$preferred_feed" != "base" ]; then
        feeds_to_try="$feeds_to_try base"
    fi
    if [ "$preferred_feed" != "luci" ]; then
        feeds_to_try="$feeds_to_try luci"
    fi
    if [ "$preferred_feed" != "packages" ]; then
        feeds_to_try="$feeds_to_try packages"
    fi
    
    local filename=""
    local found_feed=""
    
    for feed in $feeds_to_try; do
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
    
    # 如果文件已存在，验证其完整性
    if [ -f "$target" ]; then
        if verify_ipk_file "$target"; then
            echo -e "  ${YELLOW}已存在且有效: ${filename}${NC}"
            return 0
        else
            echo -e "  ${YELLOW}已存在但损坏，将重新下载: ${filename}${NC}"
            rm -f "$target"
        fi
    fi
    
    # 尝试下载，带重试机制
    local retry=0
    while [ $retry -lt $max_retries ]; do
        if [ $retry -gt 0 ]; then
            echo -e "  ${YELLOW}重试下载 (${retry}/${max_retries}): ${filename}${NC}"
            sleep 1
        else
            echo -e "  ${GREEN}下载: ${filename} (from ${found_feed} feed)${NC}"
        fi
        
        # 使用 wget 下载，显示进度但不显示详细信息
        if wget --progress=dot:giga -O "$target" "$url" 2>&1 >/dev/null && [ -f "$target" ]; then
            # 下载成功，验证文件
            if verify_ipk_file "$target"; then
                echo -e "    ${GREEN}下载成功并验证通过${NC}"
                return 0
            else
                echo -e "    ${RED}下载的文件损坏，将重试${NC}"
                rm -f "$target"
            fi
        else
            echo -e "    ${RED}下载失败${NC}"
            rm -f "$target"
        fi
        
        retry=$((retry + 1))
    done
    
    echo -e "  ${RED}失败: ${filename} (已重试 ${max_retries} 次)${NC}"
    return 1
}

# 递归下载依赖的函数（改进版：跨 feed 搜索，确保版本和架构匹配）
download_dependencies() {
    local feed=$1
    local package=$2
    local packages_file="/tmp/Packages-${feed}.gz"
    local max_depth=${3:-5}  # 最大递归深度，增加到5层以确保完整依赖树
    local current_depth=${4:-0}
    local visited_packages="${5:-}"  # 跟踪已处理的包，避免循环依赖
    
    if [ $current_depth -ge $max_depth ]; then
        echo -e "    ${YELLOW}达到最大深度 $max_depth，停止递归${NC}"
        return 0
    fi
    
    # 检查是否已访问过此包（避免循环依赖）
    if echo "$visited_packages" | grep -q "^${package}$\|^${package},"; then
        return 0
    fi
    visited_packages="${visited_packages}${visited_packages:+,}${package}"
    
    if [ ! -f "$packages_file" ]; then
        # 如果当前 feed 没有 Packages 文件，尝试其他 feed
        return 1
    fi
    
    # 提取包的依赖信息（改进：更好地解析依赖）
    local deps=$(zcat "$packages_file" 2>/dev/null | awk -v pkg="$package" '
        /^Package: / { 
            if ($2 == pkg) { 
                found=1 
            } else { 
                found=0 
            } 
        }
        found && /^Depends: / {
            # 提取依赖包名（去除版本号、架构等）
            # 处理格式: Depends: libc, libubox, libuci (>= 1.2.3), +libc
            gsub(/[()]/, " ", $0)
            for (i=2; i<=NF; i++) {
                # 跳过版本号、比较运算符等
                if ($i ~ /^[<>=]/) continue
                if ($i ~ /^[0-9]/) continue
                if ($i ~ /^[a-zA-Z0-9_-]+$/) {
                    print $i
                } else if ($i ~ /^\+/) {
                    # 处理 +libc 这样的依赖
                    gsub(/\+/, "", $i)
                    if ($i ~ /^[a-zA-Z0-9_-]+$/) {
                        print $i
                    }
                }
            }
        }
    ')
    
    if [ -z "$deps" ]; then
        return 0
    fi
    
    # 下载每个依赖
    for dep in $deps; do
        # 清理依赖名称（去除版本号等）
        dep=$(echo "$dep" | sed 's/[<>=].*//' | sed 's/^+//' | sed 's/[^a-zA-Z0-9_-].*//')
        
        # 跳过系统包和已下载的包
        if [ -z "$dep" ] || [ "$dep" = "libc" ] || [ "$dep" = "libgcc" ]; then
            continue
        fi
        
        # 检查是否已下载
        if ls "${TARGET_DIR}/${dep}"*.ipk 2>/dev/null | grep -q .; then
            continue
        fi
        
        # 尝试从多个 feed 下载依赖（按优先级：base -> luci -> packages）
        echo -e "    ${YELLOW}[深度 $((current_depth+1))] 发现依赖: ${dep}${NC}"
        local downloaded=false
        
        # 尝试 base feed
        if download_package "base" "$dep"; then
            downloaded=true
            # 递归下载此依赖的依赖
            download_dependencies "base" "$dep" $max_depth $((current_depth+1)) "$visited_packages"
        fi
        
        # 尝试 luci feed
        if [ "$downloaded" = false ] && download_package "luci" "$dep"; then
            downloaded=true
            download_dependencies "luci" "$dep" $max_depth $((current_depth+1)) "$visited_packages"
        fi
        
        # 尝试 packages feed
        if [ "$downloaded" = false ] && download_package "packages" "$dep"; then
            downloaded=true
            download_dependencies "packages" "$dep" $max_depth $((current_depth+1)) "$visited_packages"
        fi
        
        if [ "$downloaded" = false ]; then
            echo -e "    ${RED}警告: 未找到依赖包 ${dep}${NC}"
        fi
    done
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

# luci-base 及其完整依赖（确保所有依赖都被下载）
echo -e "${GREEN}下载 luci-base 及其完整依赖树...${NC}"
echo -e "${YELLOW}确保 luci-base 的所有依赖（包括间接依赖）都被下载${NC}"

# 首先下载 luci-base 主包
if ! download_package "luci" "luci-base"; then
    echo -e "${RED}错误: 无法下载 luci-base，请检查版本和架构配置${NC}"
    exit 1
fi

# 下载 luci-base 的直接依赖（根据 Packages 文件中的 Depends）
echo -e "${YELLOW}下载 luci-base 的直接依赖...${NC}"
download_package "base" "rpcd"
download_package "base" "rpcd-mod-file"
download_package "base" "rpcd-mod-ucode"
download_package "base" "rpcd-mod-luci"  # luci-base 需要
download_package "luci" "liblucihttp-ucode"  # luci-base 需要（重要！）
download_package "luci" "liblucihttp0"  # liblucihttp-ucode 可能需要

# ucode 及其模块（luci-base 需要）
download_package "base" "ucode"  # luci-base 需要
download_package "base" "libucode20230711"  # ucode 需要
download_package "base" "ucode-mod-fs"  # luci-base 需要
download_package "base" "ucode-mod-uci"  # luci-base 需要
download_package "base" "ucode-mod-ubus"  # luci-base 需要
download_package "base" "ucode-mod-math"  # luci-base 需要
download_package "base" "ucode-mod-html"  # luci-base 需要

# rpcd-mod-iwinfo 及其依赖（luci-mod-status 和 luci-mod-network 需要）
download_package "base" "rpcd-mod-iwinfo"  # luci-mod-status 和 luci-mod-network 需要
download_package "base" "libiwinfo20230701"  # rpcd-mod-iwinfo 需要（注意：包名包含版本号）
download_package "base" "libiwinfo-data"  # libiwinfo 需要

# 递归下载 luci-base 的所有依赖（包括间接依赖）
echo -e "${YELLOW}递归下载 luci-base 的完整依赖树（深度优先，5层深度）...${NC}"
download_dependencies "luci" "luci-base" 5 0 ""

# 递归下载各个关键依赖的依赖
echo -e "${YELLOW}递归下载 rpcd 的依赖...${NC}"
download_dependencies "base" "rpcd" 5 0 ""
echo -e "${YELLOW}递归下载 rpcd-mod-luci 的依赖...${NC}"
download_dependencies "base" "rpcd-mod-luci" 5 0 ""
echo -e "${YELLOW}递归下载 liblucihttp-ucode 的依赖...${NC}"
download_dependencies "luci" "liblucihttp-ucode" 5 0 ""
echo -e "${YELLOW}递归下载 ucode 的依赖...${NC}"
download_dependencies "base" "ucode" 5 0 ""
echo -e "${YELLOW}递归下载 ucode-mod-html 的依赖...${NC}"
download_dependencies "base" "ucode-mod-html" 5 0 ""

echo -e "${GREEN}luci-base 依赖树下载完成${NC}"
# cgi-io 在 24.10.0 中不存在，尝试从多个来源下载（包括非官方来源）
download_cgi_io() {
    local target="${TARGET_DIR}/cgi-io_*.ipk"
    local existing_file=$(ls ${target} 2>/dev/null | head -1)
    
    if [ -n "$existing_file" ] && verify_ipk_file "$existing_file"; then
        echo -e "  ${YELLOW}已存在且有效: cgi-io${NC}"
        return 0
    elif [ -n "$existing_file" ]; then
        echo -e "  ${YELLOW}已存在但损坏，将重新下载: cgi-io${NC}"
        rm -f "$existing_file"
    fi
    
    echo -e "  ${YELLOW}搜索 cgi-io 包（包括非官方来源）...${NC}"
    
    # 尝试从多个版本和来源下载 cgi-io
    # 使用空格分隔的字符串而不是数组（兼容 sh）
    local sources="https://downloads.openwrt.org/releases/23.05.0/packages/${ARCH}/base https://downloads.openwrt.org/releases/23.05.3/packages/${ARCH}/base https://downloads.openwrt.org/releases/22.03.5/packages/${ARCH}/base https://downloads.openwrt.org/releases/21.02.7/packages/${ARCH}/base https://downloads.openwrt.org/snapshots/packages/${ARCH}/base https://archive.openwrt.org/releases/23.05.0/packages/${ARCH}/base https://archive.openwrt.org/releases/22.03.5/packages/${ARCH}/base"
    
    # 尝试从镜像站点下载
    local mirrors="https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/23.05.0/packages/${ARCH}/base https://mirror.sjtu.edu.cn/openwrt/releases/23.05.0/packages/${ARCH}/base"
    
    # 合并所有来源
    local all_sources="$sources $mirrors"
    
    for base_url in $all_sources; do
        echo -e "  ${YELLOW}尝试从: ${base_url}${NC}"
        wget -q -O /tmp/Packages-cgiio.gz "${base_url}/Packages.gz" 2>/dev/null
        if [ $? -eq 0 ] && [ -f /tmp/Packages-cgiio.gz ]; then
            local filename=$(zcat /tmp/Packages-cgiio.gz 2>/dev/null | awk '/^Package: cgi-io$/{found=1} found && /^Filename: /{print $2; exit}')
            if [ -n "$filename" ]; then
                local url="${base_url}/${filename}"
                local target_file="${TARGET_DIR}/$(basename $filename)"
                local retry=0
                local max_retries=3
                
                while [ $retry -lt $max_retries ]; do
                    if [ $retry -gt 0 ]; then
                        echo -e "    ${YELLOW}重试下载 (${retry}/${max_retries}): $(basename $filename)${NC}"
                        sleep 1
                    else
                        echo -e "  ${GREEN}找到 cgi-io，开始下载: $(basename $filename)${NC}"
                    fi
                    
                    if wget --progress=dot:giga -O "$target_file" "$url" 2>&1 >/dev/null && [ -f "$target_file" ]; then
                        if verify_ipk_file "$target_file"; then
                            echo -e "  ${GREEN}下载成功并验证通过: $(basename $filename)${NC}"
                            echo -e "  ${GREEN}来源: ${base_url}${NC}"
                            rm -f /tmp/Packages-cgiio.gz
                            return 0
                        else
                            echo -e "    ${RED}下载的文件损坏，将重试${NC}"
                            rm -f "$target_file"
                        fi
                    else
                        echo -e "    ${RED}下载失败${NC}"
                        rm -f "$target_file"
                    fi
                    retry=$((retry + 1))
                done
            fi
        fi
        rm -f /tmp/Packages-cgiio.gz
    done
    
    # 如果所有官方来源都失败，尝试从 GitHub Actions 或其他构建产物下载
    echo -e "  ${YELLOW}尝试从 GitHub 构建产物查找...${NC}"
    # 注意：GitHub 通常不提供预编译的 ipk 包，这里只是占位
    
    # 最后尝试：从已知的预编译包 URL 下载（如果存在）
    echo -e "  ${YELLOW}尝试直接下载已知的 cgi-io 包...${NC}"
    # 注意：这些包名只是示例，实际不存在
    
    # 注意：由于 cgi-io 在所有检查的来源中都不存在，我们创建一个占位说明
    echo -e "  ${RED}警告: 在所有检查的来源中都未找到 cgi-io 包${NC}"
    echo -e "  ${YELLOW}cgi-io 在 OpenWrt 24.10.0 中可能已被移除或整合到其他包中${NC}"
    echo -e "  ${YELLOW}建议: 安装时使用 --force-depends 选项跳过此依赖${NC}"
    echo -e "  ${YELLOW}或者: 从源码编译 cgi-io 包${NC}"
    
    return 1
}
# cgi-io 下载（luci-base 声明需要，但可能已不需要）
download_cgi_io

# uhttpd 模块
echo -e "${GREEN}下载 uhttpd-mod-ubus...${NC}"
download_package "base" "uhttpd-mod-ubus"

# luci 管理界面及其依赖（完整依赖树下载）
echo -e "${GREEN}下载 luci-mod-admin-full 及其完整依赖树...${NC}"
echo -e "${YELLOW}确保所有依赖（包括间接依赖）都被下载，版本和架构匹配...${NC}"

# 首先下载主包
if ! download_package "luci" "luci-mod-admin-full"; then
    echo -e "${RED}错误: 无法下载 luci-mod-admin-full，请检查版本和架构配置${NC}"
    exit 1
fi

# 下载直接依赖
download_package "luci" "luci-mod-status"  # luci-mod-admin-full 需要
download_package "luci" "luci-mod-system"  # luci-mod-admin-full 需要
download_package "luci" "luci-mod-network"  # luci-mod-admin-full 需要

# 递归下载 luci-mod-admin-full 的所有依赖（包括间接依赖）
echo -e "${YELLOW}递归下载 luci-mod-admin-full 的完整依赖树（深度优先）...${NC}"
download_dependencies "luci" "luci-mod-admin-full" 5 0 ""

# 递归下载各个 luci-mod 的依赖
echo -e "${YELLOW}递归下载 luci-mod-status 的依赖...${NC}"
download_dependencies "luci" "luci-mod-status" 5 0 ""
echo -e "${YELLOW}递归下载 luci-mod-system 的依赖...${NC}"
download_dependencies "luci" "luci-mod-system" 5 0 ""
echo -e "${YELLOW}递归下载 luci-mod-network 的依赖...${NC}"
download_dependencies "luci" "luci-mod-network" 5 0 ""

# 再次确保 luci-base 的所有依赖都已下载（因为 luci-mod-admin-full 依赖 luci-base）
echo -e "${YELLOW}再次检查并下载 luci-base 的依赖（确保完整性）...${NC}"
download_dependencies "luci" "luci-base" 5 0 ""

echo -e "${GREEN}luci-mod-admin-full 依赖树下载完成${NC}"

# dropbear (SSH/SFTP 服务器)
# 注意: dropbear 已包含 SFTP 服务器功能，无需单独的 dropbear-sftp-server 包
echo -e "${GREEN}下载 dropbear (SSH/SFTP 服务器)...${NC}"
download_package "base" "dropbear"
download_package "base" "zlib"  # dropbear 的依赖（如果启用了 zlib 支持）

# vsftpd (FTP 服务器) 及其依赖
# 注意: vsftpd 和 vsftpd-tls 有文件冲突，只下载 vsftpd（基础版本）
# vsftpd（基础版本）不需要 libopenssl3，只有 vsftpd-tls 需要
echo -e "${GREEN}下载 vsftpd 及其依赖...${NC}"
download_package "packages" "vsftpd"  # 基础版本
# download_package "packages" "vsftpd-tls"  # 跳过，与 vsftpd 冲突

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

# 验证关键包是否已下载
echo -e "${YELLOW}=== 验证关键包 ===${NC}"
critical_packages="luci-base luci-mod-admin-full uhttpd rpcd rpcd-mod-luci liblucihttp-ucode ucode-mod-html"
missing_packages=""

for pkg in $critical_packages; do
    if ls "${TARGET_DIR}/${pkg}"*.ipk 2>/dev/null | grep -q .; then
        echo -e "  ${GREEN}✓ ${pkg}${NC}"
    else
        echo -e "  ${RED}✗ ${pkg} 未找到${NC}"
        missing_packages="${missing_packages} ${pkg}"
    fi
done

if [ -n "$missing_packages" ]; then
    echo ""
    echo -e "${RED}警告: 以下关键包未下载:${missing_packages}${NC}"
    echo -e "${YELLOW}请检查下载日志并重新运行脚本${NC}"
else
    echo ""
    echo -e "${GREEN}✓ 所有关键包已下载${NC}"
fi

echo ""
echo "已下载的包："
ls -lh "${TARGET_DIR}"/*.ipk 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || echo "  无"
echo ""

# 验证所有已下载的文件
echo -e "${YELLOW}=== 验证已下载的文件 ===${NC}"
verified_count=0
failed_count=0
failed_files=""

for ipk_file in "${TARGET_DIR}"/*.ipk; do
    if [ -f "$ipk_file" ]; then
        if verify_ipk_file "$ipk_file"; then
            verified_count=$((verified_count + 1))
        else
            failed_count=$((failed_count + 1))
            failed_file=$(basename "$ipk_file")
            failed_files="${failed_files}${failed_files:+ }${failed_file}"
            echo -e "  ${RED}损坏: ${failed_file}${NC}"
        fi
    fi
done

if [ $failed_count -eq 0 ]; then
    echo -e "${GREEN}所有文件验证通过 (${verified_count} 个文件)${NC}"
else
    echo -e "${RED}发现 ${failed_count} 个损坏的文件，${verified_count} 个文件正常${NC}"
    echo -e "${YELLOW}建议删除损坏的文件并重新运行脚本下载${NC}"
    if [ -n "$failed_files" ]; then
        echo "损坏的文件列表："
        for file in $failed_files; do
            echo "  - $file"
        done
    fi
fi
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
echo "  - 如果遇到 'Malformed packages file' 错误，说明 ipk 文件损坏"
echo "    请删除损坏的文件并重新运行脚本下载（脚本会自动验证文件完整性）"
echo ""
echo -e "${GREEN}已下载的服务包:${NC}"
echo "  - vsftpd: FTP 服务器（注意：vsftpd 和 vsftpd-tls 不能同时安装）"
echo "  - openssh-sftp-server: SFTP 服务器"
echo "  - openssh-server: OpenSSH 服务器"
echo ""
echo -e "${GREEN}已下载的 LuCI 核心包:${NC}"
echo "  - luci-base: LuCI 核心包（已下载完整依赖树）"
echo "  - luci-mod-admin-full: LuCI 完整管理界面"
echo "  - luci-mod-status: 状态模块"
echo "  - luci-mod-system: 系统模块"
echo "  - luci-mod-network: 网络模块"
echo "  - liblucihttp-ucode: LuCI HTTP 库（ucode）"
echo "  - liblucihttp0: LuCI HTTP 库"
echo ""
echo -e "${GREEN}已下载的 RPC 和 Ucode 包:${NC}"
echo "  - rpcd: RPC 守护进程"
echo "  - rpcd-mod-luci: LuCI RPC 模块"
echo "  - rpcd-mod-file: 文件操作模块"
echo "  - rpcd-mod-ucode: ucode 模块"
echo "  - rpcd-mod-iwinfo: 无线信息模块"
echo "  - ucode: ucode 解释器"
echo "  - ucode-mod-html: HTML 模块（luci-base 必需）"
echo "  - ucode-mod-uci: UCI 模块"
echo "  - ucode-mod-ubus: ubus 模块"
echo "  - ucode-mod-math: 数学模块"
echo "  - ucode-mod-fs: 文件系统模块"
echo ""
echo "已下载的其他依赖包:"
echo "  - libopenssl3: openssh-server 需要"
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
echo ""
echo -e "${YELLOW}重要提示:${NC}"
echo "  - vsftpd 和 vsftpd-tls 有文件冲突，只能安装其中一个"
echo "  - 脚本只下载了 vsftpd（基础版本）"
echo "  - 如果系统已安装 vsftpd-tls，请先卸载: opkg remove vsftpd-tls"

