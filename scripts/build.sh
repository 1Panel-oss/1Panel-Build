#!/usr/bin/env bash
# ============================================================
# 1Panel-Build - Build Script
# Compiles 1Panel core + agent, downloads offline Docker assets
# ============================================================
set -euo pipefail

# -- Defaults --
VERSION="dev"
GOOS="linux"
GOARCH="amd64"
PANEL_SRC="1Panel-source"
INSTALLER_SRC="installer-source"
OUTPUT_DIR="dist"
PARALLEL="true"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# -- Colors --
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_step()  { echo -e "\n${BOLD}--- $* ---${NC}"; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --version VER       Version tag (default: git describe or "dev")
  --goos OS           Target OS (default: linux)
  --goarch ARCH       Target arch (default: amd64)
  --panel DIR         1Panel source dir (default: 1Panel-source)
  --installer DIR     installer source dir (default: installer-source)
  --output DIR        Output dir (default: dist)
  -h, --help          Show help
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)    VERSION="$2"; shift 2 ;;
        --goos)       GOOS="$2"; shift 2 ;;
        --goarch)     GOARCH="$2"; shift 2 ;;
        --panel)      PANEL_SRC="$2"; shift 2 ;;
        --installer)  INSTALLER_SRC="$2"; shift 2 ;;
        --output)     OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help)    usage ;;
        *)            echo "Unknown: $1"; usage ;;
    esac
done

cd "$PROJECT_ROOT"
PANEL_SRC="$PROJECT_ROOT/$PANEL_SRC"
INSTALLER_SRC="$PROJECT_ROOT/$INSTALLER_SRC"
OUTPUT_DIR="$PROJECT_ROOT/$OUTPUT_DIR"

# -- Step 1: Source checkout --
log_step "Step 1/4: Checkout sources"

if [ ! -d "$PANEL_SRC/.git" ]; then
    log_info "Clone 1Panel (dev-v2)..."
    git clone --depth 1 --branch dev-v2 https://github.com/1Panel-dev/1Panel.git "$PANEL_SRC"
else
    git -C "$PANEL_SRC" fetch --depth 1 origin dev-v2
    git -C "$PANEL_SRC" reset --hard origin/dev-v2
fi

if [ ! -d "$INSTALLER_SRC/.git" ]; then
    log_info "Clone installer (v2)..."
    git clone --depth 1 --branch v2 https://github.com/1Panel-dev/installer.git "$INSTALLER_SRC"
else
    git -C "$INSTALLER_SRC" fetch --depth 1 origin v2
    git -C "$INSTALLER_SRC" reset --hard origin v2
fi

PANEL_VER=$(git -C "$PANEL_SRC" describe --tags --always --dirty 2>/dev/null || echo "unknown")
INSTALLER_VER=$(git -C "$INSTALLER_SRC" rev-parse --short HEAD 2>/dev/null || echo "n/a")
log_ok "1Panel:    $PANEL_VER"
log_ok "installer: $INSTALLER_VER"

# -- Step 2: Build binaries --
log_step "Step 2/4: Build binaries ($GOOS/$GOARCH)"

cd "$PANEL_SRC"
make build_all
cd "$PROJECT_ROOT"

log_ok "Binaries built:"
ls -lh "$PANEL_SRC/build/1panel-core" "$PANEL_SRC/build/1panel-agent" 2>/dev/null

# -- Step 3: Write version info --
log_step "Step 3/4: Write version info"

BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)
GO_VER=$(go version 2>/dev/null | awk '{print $3}' || echo "unknown")

cat > "$PANEL_SRC/build/VERSION" <<EOF
1Panel v$VERSION
Build: $BUILD_TIME
Go: $GO_VER
Platform: $GOOS/$GOARCH
Git: $PANEL_VER
Installer: $INSTALLER_VER
EOF

log_ok "Version info written"
cat "$PANEL_SRC/build/VERSION"

# -- Step 4: Done --
log_step "Step 4/4: Build summary"
echo ""
echo -e "  ${BOLD}Build artifacts:${NC}"
find "$PANEL_SRC/build" -maxdepth 1 -type f -exec ls -lh {} \; | awk '{print "    "$5, $NF}'
echo ""
log_ok "Build complete. Run release.sh to package."
