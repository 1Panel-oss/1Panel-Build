# 1Panel-Build

1Panel v2 离线开源安装包构建工具。自动合并两个上游仓库，编译所有二进制，生成可独立运行的离线安装包。

## 架构说明

本项目合并两个上游仓库的内容，生成完整的离线安装包：

| 上游仓库               | 分支     | 说明                    |
| ---------------------- | -------- | ----------------------- |
| `1Panel-dev/1Panel`    | `dev-v2` | 核心代码 (core + agent) |
| `1Panel-dev/installer` | `v2`     | 安装脚本与初始化文件     |

## 离线安装包内容

```
1panel-v2.4.1-offline-linux-amd64.tar.gz
└── 1panel-v2.4.1-offline-linux-amd64/
    ├── install.sh              # 主安装脚本
    ├── 1pctl                   # 管理控制 CLI
    ├── quick_start.sh          # 快速启动脚本
    ├── lang/                   # 多语言翻译
    │   ├── en.sh
    │   ├── zh.sh
    │   ├── fa.sh
    │   ├── pt-BR.sh
    │   └── ru.sh
    ├── initscript/             # 服务启动脚本
    │   ├── 1panel-core.service
    │   ├── 1panel-agent.service
    │   ├── 1panel-core.init
    │   ├── 1panel-agent.init
    │   ├── 1panel-core.openrc
    │   ├── 1panel-agent.openrc
    │   ├── 1panel-core.procd
    │   └── 1panel-agent.procd
    ├── 1panel-core             # 主控端二进制 (Go 静态编译)
    ├── 1panel-agent            # 被控端二进制 (Go 静态编译)
    ├── docker/                 # Docker 离线安装资源
    │   ├── bin/                # docker, dockerd, containerd 等
    │   ├── service/            # docker.service (systemd)
    │   └── conf/               # daemon.json
    ├── iptables-deb/           # iptables 离线包 (Debian)
    │   ├── debian11/
    │   ├── debian12/
    │   └── debian13/
    ├── VERSION                 # 版本信息
    └── 1panel.sha256           # 校验文件
```

## 前置依赖

| 工具    | 版本       | 用途               |
| ------- | ---------- | ------------------ |
| Go      | 1.27+      | 编译后端二进制     |
| Node.js | 18+ / 22+  | 构建前端资源       |
| npm     | 随 Node    | 前端包管理         |
| git     | 任意       | 克隆上游仓库       |
| curl    | 可选       | 下载 Docker 离线包 |

## 快速开始

### 指定版本构建

```bash
VERSION=v2.4.1 make release
```

### 多平台构建

```bash
make release-all
# 生成:
#   dist/1panel-v2.4.1-offline-linux-amd64.tar.gz
#   dist/1panel-v2.4.1-offline-linux-arm64.tar.gz
```

### 本地开发（仅适用于提 PR / 调试脚本）

```bash
# 仅做最新代码编译
make build
```

## Make targets

| Target        | 说明                                              |
| ------------- | ------------------------------------------------- |
| `make source` | 拉取 / 更新 1Panel 与 installer 源码               |
| `make build`  | 编译 core + agent（调用上游 Makefile）              |
| `make build-all` | 多平台编译（amd64 + arm64）                      |
| `make release` | 生成单平台离线安装包                               |
| `make release-all` | 生成所有平台离线安装包                          |
| `make check`     | 检查环境是否就绪                                 |
| `make clean`     | 清理构建产物                                     |
| `make clean-all` | 清理构建产物 + 源码                              |
| `make help`      | 显示帮助                                         |

### 变量覆盖

```bash
VERSION=v2.4.1 GOOS=linux GOARCH=arm64 GO_VERSION=1.27 make build
```

| 变量           | 默认值          | 说明                |
| -------------- | --------------- | ------------------- |
| `VERSION`      | git describe    | 版本标签            |
| `GOOS`         | linux           | 目标操作系统        |
| `GOARCH`       | amd64           | 目标架构            |
| `OUTPUT_DIR`   | dist            | 输出目录            |
| `PANEL_SRC`    | 1Panel-source   | 1Panel 源码目录     |
| `INSTALLER_SRC`| installer-source| installer 源码目录  |

## 离线包目标机器使用方法

```bash
# 1. 解压
tar -xzf 1panel-v2.4.1-offline-linux-amd64.tar.gz

# 2. 进入目录
cd 1panel-v2.4.1-offline-linux-amd64/

# 3. 执行安装
chmod +x install.sh 1pctl
sudo bash install.sh

# 4. 安装过程中选择 "离线模式" (安装脚本会检测当前目录下的 docker/ 资源)
```

## GitHub Actions

### Build 工作流 (push/PR)

在 `ubuntu-latest` 上使用 `setup-go@v5`(1.27) 和 `setup-node@v4`(22) 编译 `amd64` + `arm64`，生成离线安装包并输出为 workflow artifact（保留 7 天）。

### Release 工作流 (tag push)

- 触发条件：push tag `v*`
- 行为：矩阵编译 + 打包 + 自动创建 GitHub Release
- Release 包含：tar.gz + sha256 校验

## 许可

本项目脚本采用 [GPL-3.0](LICENSE) 许可，与上游 [1Panel](https://github.com/1Panel-dev/1Panel) 和 [installer](https://github.com/1Panel-dev/installer/) 保持一致。
