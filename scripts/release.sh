#!/usr/bin/env bash
# ============================================================
# 1Panel-Build - Release Packing Script
# Assembles offline installer package:
#   - install.sh, 1pctl, quick_start.sh, lang/ (from installer repo)
#   - 1panel-core, 1panel-agent (from 1Panel build)
#   - docker/ (offline Docker binaries)
#   - iptables-deb/ (offline iptables debs)
# ============================================================
set -euo pipefail

# -- Defaults --
VERSION="dev"
GOOS="linux"
GOARCH="amd64"
PANEL_SRC="1Panel-source"
INSTALLER_SRC="installer-source"
OUTPUT_DIR="dist"
FORMAT="tar.gz"
INCLUDE_DOCKER="true"
INCLUDE_IPTABLES="true"

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
  --version VER       Version (default: "dev")
  --goos OS           Target OS (default: linux)
  --goarch ARCH       Target arch (default: amd64)
  --panel DIR         1Panel source dir
  --installer DIR     installer source dir
  --output DIR        Output dir (default: dist)
  --format FMT        Archive: tar.gz|zip (default: tar.gz)
  --no-docker         Skip Docker offline assets
  --no-iptables       Skip iptables offline debs
  -h, --help          Show help
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="$2"; shift 2 ;;
        --goos)        GOOS="$2"; shift 2 ;;
        --goarch)      GOARCH="$2"; shift 2 ;;
        --panel)       PANEL_SRC="$2"; shift 2 ;;
        --installer)   INSTALLER_SRC="$2"; shift 2 ;;
        --output)      OUTPUT_DIR="$2"; shift 2 ;;
        --format)      FORMAT="$2"; shift 2 ;;
        --no-docker)   INCLUDE_DOCKER="false"; shift ;;
        --no-iptables) INCLUDE_IPTABLES="false"; shift ;;
        -h|--help)     usage ;;
        *)             echo "Unknown: $1"; usage ;;
    esac
done

cd "$PROJECT_ROOT"
PANEL_SRC="$PROJECT_ROOT/$PANEL_SRC"
INSTALLER_SRC="$PROJECT_ROOT/$INSTALLER_SRC"
OUTPUT_DIR="$PROJECT_ROOT/$OUTPUT_DIR"

PACK_NAME="1panel-v${VERSION}-offline-${GOOS}-${GOARCH}"
PACK_DIR="$OUTPUT_DIR/$PACK_NAME"

# -- Validate inputs --
if [ ! -d "$PANEL_SRC/build" ]; then
    echo "Error: 1Panel build/ not found. Run build.sh first."
    exit 1
fi
if [ ! -d "$INSTALLER_SRC" ]; then
    echo "Error: installer source not found."
    exit 1
fi

# Resolve version from git if "dev"
if [ "$VERSION" = "dev" ]; then
    VERSION=$(git -C "$PANEL_SRC" describe --tags --always --dirty 2>/dev/null || echo "dev")
fi

# -- Step 1: Assemble package directory --
log_step "Step 1/4: Assemble package directory"

rm -rf "$OUTPUT_DIR"
mkdir -p "$PACK_DIR"

# Copy installer files
log_info "Copy installer files..."
cp "$INSTALLER_SRC/install.sh" "$PACK_DIR/"
cp "$INSTALLER_SRC/1pctl" "$PACK_DIR/"
cp "$INSTALLER_SRC/quick_start.sh" "$PACK_DIR/"
cp -r "$INSTALLER_SRC/lang" "$PACK_DIR/"
cp -r "$INSTALLER_SRC/initscript" "$PACK_DIR/"

chmod +x "$PACK_DIR/install.sh"
chmod +x "$PACK_DIR/1pctl"
chmod +x "$PACK_DIR/quick_start.sh"

# Copy compiled binaries
log_info "Copy compiled binaries..."
cp "$PANEL_SRC/build/1panel-core" "$PACK_DIR/"
cp "$PANEL_SRC/build/1panel-agent" "$PACK_DIR/"

log_ok "Install files assembled at: $PACK_DIR"

# -- Step 2: Download offline Docker binaries --
if [ "$INCLUDE_DOCKER" = "true" ]; then
    log_step "Step 2/4: Download offline Docker binaries"

    DOCKER_VERSION="28.3.3"
    DOCKER_URL="https://download.docker.com/linux/static/stable/${GOARCH}/docker-${DOCKER_VERSION}.tgz"
    DOCKER_DIR="$PACK_DIR/docker"

    mkdir -p "$DOCKER_DIR"

    log_info "Downloading Docker ${DOCKER_VERSION} (${GOARCH})..."
    log_info "URL: $DOCKER_URL"

    if command -v curl &>/dev/null; then
        curl -fsSL "$DOCKER_URL" -o "/tmp/docker-${DOCKER_VERSION}.tgz"
    elif command -v wget &>/dev/null; then
        wget -q "$DOCKER_URL" -O "/tmp/docker-${DOCKER_VERSION}.tgz"
    else
        log_warn "curl/wget not available, skipping Docker download"
    fi

    if [ -f "/tmp/docker-${DOCKER_VERSION}.tgz" ]; then
        log_info "Extracting Docker binaries..."
        mkdir -p "$DOCKER_DIR/bin"
        tar -xzf "/tmp/docker-${DOCKER_VERSION}.tgz" -C /tmp/
        cp /tmp/docker/* "$DOCKER_DIR/bin/"
        rm -rf /tmp/docker/ "/tmp/docker-${DOCKER_VERSION}.tgz"

        # Create docker.service
        mkdir -p "$DOCKER_DIR/service"
        cat > "$DOCKER_DIR/service/docker.service" <<'DOCKER_SERVICE'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service containerd.service
Wants=network-online.target
Requires=docker.socket containerd.service

[Service]
Type=notify
ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutStartSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
DOCKER_SERVICE

        # Create daemon.json
        mkdir -p "$DOCKER_DIR/conf"
        cat > "$DOCKER_DIR/conf/daemon.json" <<'DAEMON_JSON'
{
  "log-opts": {
    "max-size": "5m",
    "max-file": "2"
  }
}
DAEMON_JSON

        chmod +x "$DOCKER_DIR/bin/"*
        log_ok "Docker ${DOCKER_VERSION} offline assets ready"
    fi
else
    log_step "Step 2/4: Skip Docker (disabled)"
fi

# -- Step 3: Download offline iptables debs --
if [ "$INCLUDE_IPTABLES" = "true" ] && [ "$GOARCH" = "amd64" ]; then
    log_step "Step 3/4: Download offline iptables debs"

    IPTABLES_DIR="$PACK_DIR/iptables-deb"
    mkdir -p "$IPTABLES_DIR"

    # iptables offline debs for Debian 11/12/13 (from 1Panel project)
    declare -A IPTABLES_URLS=(
        ["debian11"]="https://resource.fit2cloud.com/network/iptables-deb/debian11/"
        ["debian12"]="https://resource.fit2cloud.com/network/iptables-deb/debian12/"
        ["debian13"]="https://resource.fit2cloud.com/network/iptables-deb/debian13/"
    )

    for debian_ver in debian11 debian12 debian13; do
        DEB_DIR="$IPTABLES_DIR/${debian_ver}"
        mkdir -p "$DEB_DIR"

        log_info "Trying iptables debs for ${debian_ver}..."
        for pkg in iptables libip6tc2 libxtables12; do
            URL="${IPTABLES_URLS[$debian_ver]}${pkg}_amd64.deb"
            if curl -fsSL "$URL" -o "$DEB_DIR/${pkg}.deb" 2>/dev/null; then
                log_info "  Downloaded: ${pkg}.deb"
            else
                log_warn "  Failed: ${pkg}.deb (may not exist for ${debian_ver})"
            fi
        done
    done

    # Remove empty dirs
    find "$IPTABLES_DIR" -type d -empty -delete 2>/dev/null || true
    log_ok "iptables debs downloaded"
elif [ "$GOARCH" = "arm64" ]; then
    log_step "Step 3/4: Skip iptables (ARM64 uses different packages)"
else
    log_step "Step 3/4: Skip iptables (disabled)"
fi

# -- Step 4: Create archive --
log_step "Step 4/4: Create archive"

# Write comprehensive VERSION file
cat > "$PACK_DIR/VERSION" <<EOF
1Panel v${VERSION}
Build: $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
Platform: ${GOOS}/${GOARCH}
Type: offline-installer
Components:
  - install.sh
  - 1pctl
  - quick_start.sh
  - lang/
  - initscript/
  - 1panel-core
  - 1panel-agent
  - docker/
  - iptables-deb/
EOF

cd "$OUTPUT_DIR"
ARCHIVE_PATH=""

case "$FORMAT" in
    tar.gz)
        ARCHIVE_PATH="${PACK_NAME}.tar.gz"
        tar -czf "$ARCHIVE_PATH" "$PACK_NAME/"
        ;;
    zip)
        ARCHIVE_PATH="${PACK_NAME}.zip"
        if command -v zip &>/dev/null; then
            zip -r -q "$ARCHIVE_PATH" "$PACK_NAME/"
        else
            ARCHIVE_PATH="${PACK_NAME}.tar.gz"
            tar -czf "$ARCHIVE_PATH" "$PACK_NAME/"
        fi
        ;;
esac

# Generate checksum
sha256sum "$ARCHIVE_PATH" > "${ARCHIVE_PATH}.sha256"
cd "$PROJECT_ROOT"

ARCHIVE_SIZE=$(du -h "$OUTPUT_DIR/$ARCHIVE_PATH" | cut -f1)
log_ok "Archive: $OUTPUT_DIR/$ARCHIVE_PATH ($ARCHIVE_SIZE)"
log_ok "Checksum: $OUTPUT_DIR/${ARCHIVE_PATH}.sha256"

# Print contents summary
echo ""
echo -e "  ${BOLD}Package contents:${NC}"
find "$PACK_DIR" -maxdepth 2 -maxdepth 2 | while read f; do
    if [ -f "$f" ]; then
        SIZE=$(du -sh "$f" 2>/dev/null | cut -f1)
        echo "    $SIZE  $(basename "$f")"
    elif [ -d "$f" ]; then
        echo "    [dir]  $(basename "$f")/"
    fi
done

echo ""
log_ok "Offline installer packaged: $OUTPUT_DIR/$ARCHIVE_PATH"
