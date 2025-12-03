# GitHub Actions 工作流说明

## build-and-test.yml

这个工作流自动化构建和测试 OpenWrt K3s 镜像。

### 触发条件

- 推送到 `main` 分支
- 推送到 `dev` 分支

**注意**：只有直接推送（push）到这两个分支时才会触发构建，Pull Request 不会触发。

### 当前版本说明

当前工作流包括 **完整的构建和测试流程**：

**构建阶段：**
- 下载 OpenWrt 源码
- 编译 x86_64 镜像
- 验证构建产物

**测试阶段：**
- 启动 QEMU 虚拟机
- 验证内核特性（Cgroups、Namespaces、OverlayFS）
- 安装 K3s 和 Containerd
- 验证集群状态
- 测试部署功能

**产物上传：**
- OpenWrt 镜像（保留 30 天）
- 测试日志（保留 7 天）

### 工作流步骤

#### 1. 环境准备
- 使用 Ubuntu 22.04 运行器
- 清理磁盘空间（删除不必要的预装软件）
- 安装构建依赖和 QEMU 虚拟化工具

#### 2. 构建 OpenWrt
- 下载 OpenWrt 24.10.0 源码
- 更新和安装 feeds
- 使用 config-k3s 配置编译 x86_64 镜像

#### 3. 准备虚拟机
- 解压并准备镜像文件
- 扩展镜像到 8GB（为 K3s 提供足够空间）
- 使用 QEMU/KVM 启动虚拟机（后台运行）

#### 4. 配置 OpenWrt
- 等待虚拟机完全启动
- 通过 SSH 连接到虚拟机（端口 2222）

#### 5. 验证内核特性
使用 `.github/scripts/verify-kernel.sh` 验证：
- Cgroups（资源控制）
- Namespaces（隔离）
- 网络模块（veth、vxlan、br_netfilter）
- OverlayFS（容器存储）

#### 6. 安装 K3s
使用 `.github/scripts/install-k3s.sh`：
- 更新软件包列表
- 安装必要依赖（ca-certificates、curl）
- 下载并执行 K3s 安装脚本
- 配置使用 Containerd 运行时

#### 7. 验证 K3s 集群
使用 `.github/scripts/verify-k3s.sh`：
- 检查 K3s 版本和服务状态
- 等待节点就绪
- 验证系统 Pods 运行状态
- 检查 Containerd 运行时

#### 8. 测试部署
使用 `.github/scripts/test-deployment.sh`：
- 创建测试部署（Nginx）
- 验证 Pod 启动和运行
- 检查容器列表
- 清理测试资源

#### 9. 收集日志
- 从虚拟机收集系统日志
- 汇总所有测试日志
- 上传日志文件

#### 10. 产物上传
- 上传 OpenWrt 镜像（保留 30 天）
- 上传测试日志（保留 7 天）

#### 11. 资源清理
- 停止虚拟机
- 删除临时文件
- 生成测试摘要

### 环境变量

| 变量 | 值 | 说明 |
|------|-----|------|
| `OPENWRT_VERSION` | 24.10.0 | OpenWrt 版本 |
| `TARGET_ARCH` | x86 | 目标架构 |
| `TARGET_SUBARCH` | 64 | 子架构 |
| `CONFIG_FILE` | config-k3s | 配置文件 |

### 超时设置

- 总超时时间：180 分钟（3 小时）
- 各步骤超时：
  - 虚拟机启动：30 秒
  - SSH 连接等待：最多 150 秒（30 次 × 5 秒）
  - K3s 节点就绪：最多 300 秒（30 次 × 10 秒）
  - 部署测试：120 秒

### 产物

#### OpenWrt 镜像
- 名称：`openwrt-k3s-x86-64`
- 格式：`.img.gz`
- 保留时间：30 天
- 仅在成功时上传

#### 测试日志
- 名称：`test-logs`
- 包含文件：
  - `all-logs.txt` - 汇总日志（包含系统日志和 dmesg）
  - `verify-kernel.log` - 内核特性验证
  - `install-k3s.log` - K3s 安装日志
  - `verify-k3s.log` - 集群验证日志
  - `test-deployment.log` - 部署测试日志
- 保留时间：7 天
- 总是上传（包括失败情况）

### 成功标准

工作流成功需要满足：
1. OpenWrt 镜像构建成功
2. 虚拟机正常启动
3. 所有内核特性验证通过
4. K3s 安装成功
5. 节点状态为 Ready
6. 系统 Pods 运行正常
7. 测试部署创建和运行成功

### 故障排查

如果工作流失败：

1. **查看 Actions 日志**
   - 点击失败的工作流
   - 展开失败的步骤查看详细日志

2. **下载测试日志**
   - 在 Artifacts 中下载 `build-and-test-logs`
   - 查看具体的错误信息

3. **常见问题**
   - 磁盘空间不足：检查 "Free up disk space" 步骤
   - 编译失败：检查 config-k3s 配置
   - 虚拟机启动失败：查看 vm.log
   - K3s 安装失败：检查网络连接和依赖
   - 节点未就绪：查看 K3s 日志

### 本地调试

使用 [act](https://github.com/nektos/act) 在本地运行 GitHub Actions：

```bash
# 安装 act
# macOS
brew install act

# Linux
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

# 运行工作流
act push

# 运行特定 job
act -j build-and-test

# 使用大型运行器镜像（更接近 GitHub 环境）
act -P ubuntu-22.04=catthehacker/ubuntu:full-22.04
```

### 优化建议

1. **缓存优化**
   - 可以添加 OpenWrt 源码缓存
   - 缓存已下载的软件包

2. **并行化**
   - 可以创建多个 job 测试不同架构
   - 分离构建和测试步骤

3. **通知**
   - 添加 Slack/Discord 通知
   - 发送邮件通知

4. **定时构建**
   - 添加 cron 触发器定期构建
   - 确保配置持续有效

### 安全注意事项

- 不要在日志中输出敏感信息
- 使用 GitHub Secrets 存储凭证
- 限制工作流权限
- 定期更新依赖版本
