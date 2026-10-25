.PHONY: all help source build build-all release release-all clean clean-all local check

# ============================================================
# 1Panel-Build: 1Panel v2 离线开源安装包构建工具
# ============================================================
# 仓库组成:
#   1Panel  (dev-v2)   -> 1panel-core, 1panel-agent
#   installer (v2)     -> install.sh, 1pctl, initscript/
#   最终产物: 离线安装包 (含二进制 + 安装脚本 + Docker 安装资源)
# ============================================================

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

# -- 可通过命令行覆盖的变量 --
VERSION        ?= $(shell git -C 1Panel-source describe --tags --always --dirty 2>/dev/null || echo "dev")
GOOS           ?= linux
GOARCH         ?= amd64
OUTPUT_DIR     ?= dist
PANEL_SRC      ?= 1Panel-source
INSTALLER_SRC  ?= installer-source
PARALLEL       ?= true

GO_VERSION     := $(shell go version 2>/dev/null || echo "not found")
NODE_VERSION   := $(shell node --version 2>/dev/null || echo "not found")

all: help

help: ## 显示所有可用 make target
	@echo ""
	@echo "  1Panel-Build - 1Panel v2 离线开源安装包构建工具"
	@echo "  ──────────────────────────────────────────────"
	@echo "  Go:    $(GO_VERSION)"
	@echo "  Node:  $(NODE_VERSION)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf("  %-22s %s\n", $$1, $$2)}'
	@echo ""

check: ## 检查构建环境是否就绪
	@echo ">> 检查环境..."
	@command -v go >/dev/null 2>&1 || { echo "  [缺失] Go (https://go.dev/dl/)"; exit 1; }
	@command -v node >/dev/null 2>&1 || { echo "  [缺失] Node.js (>=18)"; exit 1; }
	@command -v npm >/dev/null 2>&1 || true
	@command -v git >/dev/null 2>&1 || { echo "  [缺失] Git"; exit 1; }
	@echo "  [OK] Go:    $$(go version 2>/dev/null | awk '{print $$3}')"
	@echo "  [OK] Node:  $$(node --version 2>/dev/null)"
	@echo "  [OK] Git:   $$(git --version 2>/dev/null | awk '{print $$3}')"
	@echo ""

# ============================================================
# Stage 1: 拉取源码
# ============================================================
source: ## 克隆/更新 1Panel 与 installer 上游源码
	@if [ ! -d "$(PANEL_SRC)/.git" ]; then \
		echo ">> 克隆 1Panel 源码 (dev-v2)..."; \
		git clone --depth 1 --branch dev-v2 https://github.com/1Panel-dev/1Panel.git $(PANEL_SRC); \
	else \
		echo ">> 更新 1Panel 源码..."; \
		git -C $(PANEL_SRC) fetch --depth 1 origin dev-v2 && \
		git -C $(PANEL_SRC) reset --hard origin/dev-v2; \
	fi
	@if [ ! -d "$(INSTALLER_SRC)/.git" ]; then \
		echo ">> 克隆 installer 源码 (v2)..."; \
		git clone --depth 1 --branch v2 https://github.com/1Panel-dev/installer.git $(INSTALLER_SRC); \
	else \
		echo ">> 更新 installer 源码..."; \
		git -C $(INSTALLER_SRC) fetch --depth 1 origin v2 && \
		git -C $(INSTALLER_SRC) reset --hard origin v2; \
	fi
	@echo ">> 1Panel:    $$(git -C $(PANEL_SRC) describe --tags --always --dirty 2>/dev/null || echo 'unknown')"
	@echo ">> installer: $$(git -C $(INSTALLER_SRC) rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

# ============================================================
# Stage 2: 编译 (调用上游 Makefile)
# ============================================================
build: source ## 编译 core + agent 二进制 (单平台)
	@echo ">> 开始 1Panel 编译 ($(GOOS)/$(GOARCH))..."
	cd $(PANEL_SRC) && $(MAKE) build_all
	@echo ">> 编译完成. 产物: $(PANEL_SRC)/build/"

build-all: ## 编译所有支持的平台 (amd64 + arm64)
	$(MAKE) build GOARCH=amd64
	@mkdir -p $(PANEL_SRC)/build/amd64 && \
		mv $(PANEL_SRC)/build/1panel-core $(PANEL_SRC)/build/amd64/ && \
		mv $(PANEL_SRC)/build/1panel-agent $(PANEL_SRC)/build/amd64/
	$(MAKE) build GOARCH=arm64
	@mkdir -p $(PANEL_SRC)/build/arm64 && \
		mv $(PANEL_SRC)/build/1panel-core $(PANEL_SRC)/build/arm64/ && \
		mv $(PANEL_SRC)/build/1panel-agent $(PANEL_SRC)/build/arm64/
	@echo ">> 多平台编译完成: $(PANEL_SRC)/build/"
	@ls -lh $(PANEL_SRC)/build/*/

# ============================================================
# Stage 3: 离线安装包
# ============================================================
release: source build ## 生成单平台离线安装包
	./scripts/release.sh --version $(VERSION) --goos $(GOOS) --goarch $(GOARCH) \
		--panel $(PANEL_SRC) --installer $(INSTALLER_SRC) --output $(OUTPUT_DIR)

release-all: source build-all ## 生成所有平台离线安装包
	@for arch in amd64 arm64; do \
		echo ">> 打包 $$arch 离线安装包..."; \
		./scripts/release.sh --version $(VERSION) --goos linux --goarch $$arch \
			--panel $(PANEL_SRC) --installer $(INSTALLER_SRC) --output $(OUTPUT_DIR); \
	done
	@echo ">> 所有平台离线安装包生成完成"
	@ls -lh $(OUTPUT_DIR)/*

# ============================================================
# Stage 4: 本地开发模式
# ============================================================
local: ## 本地开发模式 (macOS/Linux -> 交叉编译 Linux amd64)
	cd $(PANEL_SRC) && $(MAKE) build_on_local
	@echo ">> 本地本地编译完成"
	@ls -lh $(PANEL_SRC)/build/

# ============================================================
# 清理
# ============================================================
clean: ## 清理构建产物
	rm -rf $(OUTPUT_DIR)
	rm -rf $(PANEL_SRC)/build/
	rm -rf $(PANEL_SRC)/core/cmd/server/web/assets
	@echo ">> 清理完成"

clean-all: clean ## 清理构建产物 + 源码
	rm -rf $(PANEL_SRC) $(INSTALLER_SRC)
	@echo ">> 完全清理完成"
