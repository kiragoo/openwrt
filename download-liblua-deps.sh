#!/bin/sh

# 从 OpenWrt 官方源下载 liblua 及其所有依赖包
# OpenWrt 24.10.0 x86_64

VERSION="24.10.0"
ARCH="x86_64"
BASE_URL="https://downloads.openwrt.org/releases/${VERSION}/packages/${ARCH}"
TARGET_DIR="user-namespace-pkgs"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 创建目标目录
mkdir -p "${TARGET_DIR}"

echo -e "${GREEN}=== 下载 liblua 及其所有依赖包 ===${NC}"
echo "版本: ${VERSION}"
echo "架构: ${ARCH}"
echo "目标目录: ${TARGET_DIR}"
echo ""

# 下载 Packages.gz 文件
echo -e "${YELLOW}正在获取包索引...${NC}"
wget -q -O /tmp/Packages-base.gz "${BASE_URL}/base/Packages.gz" || { echo -e "${RED}无法下载 base feed${NC}"; exit 1; }
wget -q -O /tmp/Packages-packages.gz "${BASE_URL}/packages/Packages.gz" || { echo -e "${RED}无法下载 packages feed${NC}"; exit 1; }
wget -q -O /tmp/Packages-luci.gz "${BASE_URL}/luci/Packages.gz" || echo -e "${YELLOW}警告: 无法下载 luci feed${NC}"

# 验证 ipk 文件是否有效
verify_ipk_file() {
    local file=$1
    if [ ! -f "$file" ]; then
        return 1
    fi
    local size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0")
    if [ "$size" -gt 100 ]; then
        return 0
    fi
    return 1
}

# 从 Packages.gz 中提取包文件名
get_package_filename() {
    local feed=$1
    local package=$2
    local packages_file="/tmp/Packages-${feed}.gz"
    
    if [ ! -f "$packages_file" ]; then
        return 1
    fi
    
    zcat "$packages_file" 2>/dev/null | awk -v pkg="$package" '
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

# 从 Packages.gz 中提取包的依赖列表
get_package_dependencies() {
    local feed=$1
    local package=$2
    local packages_file="/tmp/Packages-${feed}.gz"
    
    if [ ! -f "$packages_file" ]; then
        return 1
    fi
    
    # 提取 Depends 行，然后解析每个依赖
    zcat "$packages_file" 2>/dev/null | awk -v pkg="$package" '
        /^Package: / { 
            if ($2 == pkg) { 
                found=1 
            } else { 
                found=0 
            } 
        }
        found && /^Depends: / {
            # 打印整行 Depends
            print $0
            exit
        }
    ' | sed 's/^Depends: //' | tr ',' '\n' | while read dep; do
        # 清理每个依赖：去除空格、版本号、括号等
        dep=$(echo "$dep" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | sed 's/[()].*//' | sed 's/^+//' | sed 's/[<>=].*//')
        if [ -n "$dep" ] && [ "$dep" != "libc" ] && [ "$dep" != "libgcc" ]; then
            echo "$dep"
        fi
    done
}

# 下载单个包
download_package() {
    local feed=$1
    local package=$2
    
    # 尝试的 feed 顺序：首选 feed -> base -> packages -> luci
    local feeds_to_try="$feed"
    if [ "$feed" != "base" ]; then
        feeds_to_try="$feeds_to_try base"
    fi
    if [ "$feed" != "packages" ]; then
        feeds_to_try="$feeds_to_try packages"
    fi
    if [ "$feed" != "luci" ] && [ -f "/tmp/Packages-luci.gz" ]; then
        feeds_to_try="$feeds_to_try luci"
    fi
    
    local filename=""
    local found_feed=""
    
    for f in $feeds_to_try; do
        filename=$(get_package_filename "$f" "$package")
        if [ -n "$filename" ]; then
            found_feed="$f"
            break
        fi
    done
    
    if [ -z "$filename" ]; then
        echo -e "  ${RED}未找到: ${package}${NC}"
        return 1
    fi
    
    local url="${BASE_URL}/${found_feed}/${filename}"
    local target="${TARGET_DIR}/$(basename "$filename")"
    
    # 如果文件已存在，验证其完整性
    if [ -f "$target" ]; then
        if verify_ipk_file "$target"; then
            echo -e "  ${YELLOW}已存在且有效: $(basename "$filename")${NC}"
            return 0
        else
            echo -e "  ${YELLOW}已存在但损坏，将重新下载: $(basename "$filename")${NC}"
            rm -f "$target"
        fi
    fi
    
    # 下载包
    echo -e "  ${GREEN}下载: $(basename "$filename")${NC}"
    if wget --progress=dot:giga -O "$target" "$url" 2>&1 >/dev/null && [ -f "$target" ]; then
        if verify_ipk_file "$target"; then
            echo -e "  ${GREEN}✓ 下载成功: $(basename "$filename")${NC}"
            return 0
        else
            echo -e "  ${RED}✗ 下载的文件损坏${NC}"
            rm -f "$target"
            return 1
        fi
    else
        echo -e "  ${RED}✗ 下载失败${NC}"
        rm -f "$target"
        return 1
    fi
}

# 递归下载依赖（避免循环）
download_dependencies() {
    local feed=$1
    local package=$2
    local visited_packages="$3"
    
    # 检查是否已访问过此包（避免循环依赖）
    if echo "$visited_packages" | grep -q "^${package}$\|^${package},"; then
        return 0
    fi
    visited_packages="${visited_packages}${visited_packages:+,}${package}"
    
    # 获取包的依赖
    local deps=$(get_package_dependencies "$feed" "$package")
    
    if [ -z "$deps" ]; then
        return 0
    fi
    
    # 下载每个依赖
    for dep in $deps; do
        # 清理依赖名称
        dep=$(echo "$dep" | sed 's/[<>=].*//' | sed 's/^+//' | sed 's/[^a-zA-Z0-9_-].*//')
        
        # 跳过系统包和已下载的包
        if [ -z "$dep" ] || [ "$dep" = "libc" ] || [ "$dep" = "libgcc" ]; then
            continue
        fi
        
        # 检查是否已下载
        if ls "${TARGET_DIR}/${dep}"*.ipk 2>/dev/null | grep -q .; then
            continue
        fi
        
        # 尝试从多个 feed 下载依赖
        echo -e "    ${YELLOW}发现依赖: ${dep}${NC}"
        local downloaded=false
        
        # 尝试 base feed
        if download_package "base" "$dep"; then
            downloaded=true
            # 递归下载此依赖的依赖
            download_dependencies "base" "$dep" "$visited_packages"
        fi
        
        # 尝试 packages feed
        if [ "$downloaded" = false ] && download_package "packages" "$dep"; then
            downloaded=true
            download_dependencies "packages" "$dep" "$visited_packages"
        fi
        
        # 尝试 luci feed
        if [ "$downloaded" = false ] && [ -f "/tmp/Packages-luci.gz" ] && download_package "luci" "$dep"; then
            downloaded=true
            download_dependencies "luci" "$dep" "$visited_packages"
        fi
        
        if [ "$downloaded" = false ]; then
            echo -e "    ${RED}警告: 未找到依赖包 ${dep}${NC}"
        fi
    done
}

# 查找所有 liblua 相关的包
echo -e "${GREEN}查找 liblua 相关包...${NC}"
liblua_packages=$(zcat /tmp/Packages-base.gz /tmp/Packages-packages.gz 2>/dev/null | grep "^Package: liblua" | awk '{print $2}' | sort -u)

if [ -z "$liblua_packages" ]; then
    echo -e "${RED}未找到 liblua 相关包${NC}"
    exit 1
fi

echo -e "${YELLOW}找到以下 liblua 包:${NC}"
for pkg in $liblua_packages; do
    echo "  - $pkg"
done
echo ""

# 下载每个 liblua 包及其依赖
for pkg in $liblua_packages; do
    echo -e "${GREEN}下载 ${pkg} 及其依赖...${NC}"
    
    # 确定包所在的 feed
    pkg_feed="base"
    if get_package_filename "packages" "$pkg" >/dev/null 2>&1; then
        pkg_feed="packages"
    fi
    
    # 下载主包
    if download_package "$pkg_feed" "$pkg"; then
        echo -e "${GREEN}✓ ${pkg} 下载成功${NC}"
        # 下载依赖
        download_dependencies "$pkg_feed" "$pkg" ""
    else
        echo -e "${RED}✗ ${pkg} 下载失败${NC}"
    fi
    echo ""
done

# 验证下载的包
echo -e "${YELLOW}=== 验证下载的包 ===${NC}"
verified_count=0
failed_count=0

for ipk_file in "${TARGET_DIR}"/*.ipk; do
    if [ -f "$ipk_file" ]; then
        if verify_ipk_file "$ipk_file"; then
            verified_count=$((verified_count + 1))
        else
            failed_count=$((failed_count + 1))
            echo -e "  ${RED}损坏: $(basename "$ipk_file")${NC}"
        fi
    fi
done

if [ $failed_count -eq 0 ]; then
    echo -e "${GREEN}所有文件验证通过 (${verified_count} 个文件)${NC}"
else
    echo -e "${RED}发现 ${failed_count} 个损坏的文件，${verified_count} 个文件正常${NC}"
fi

echo ""
echo -e "${GREEN}=== 下载完成 ===${NC}"
echo "包已保存到: ${TARGET_DIR}/"
echo ""
echo "已下载的 liblua 相关包:"
ls -lh "${TARGET_DIR}"/liblua*.ipk 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || echo "  (无)"
echo ""
echo "所有已下载的包列表:"
ls -lh "${TARGET_DIR}"/*.ipk 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
