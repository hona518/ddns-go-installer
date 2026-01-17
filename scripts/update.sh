#!/usr/bin/env bash

#############################################
# ddns-go Updater
# 自动更新到最新版本
#############################################

DEFAULT_PORT=9876
LOG_FILE="/var/log/ddns-go-installer.log"
DEBUG=false

COLOR_RED="\e[31m"
COLOR_GREEN="\e[32m"
COLOR_YELLOW="\e[33m"
COLOR_BLUE="\e[34m"
COLOR_RESET="\e[0m"

log_raw() { echo "[$(date '+%F %T')] $*" >>"$LOG_FILE"; }
log_info() { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"; log_raw "[INFO] $*"; }
log_success() { echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $*"; log_raw "[OK] $*"; }
log_warn() { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"; log_raw "[WARN] $*"; }
log_error() { echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*"; log_raw "[ERROR] $*"; }
debug() { [ "$DEBUG" = true ] && echo -e "${COLOR_YELLOW}[DEBUG]${COLOR_RESET} $*" && log_raw "[DEBUG] $*"; }

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --debug) DEBUG=true ;;
            -h|--help)
                echo "用法: $0 [--debug]"
                exit 0
                ;;
            *) log_warn "忽略未知参数：$1" ;;
        esac
        shift
    done
}

check_ddns_go() {
    if [ ! -f /opt/ddns-go/ddns-go ]; then
        log_error "未检测到 /opt/ddns-go/ddns-go，请先运行 install.sh"
        exit 1
    fi
}

detect_arch() {
    arch=$(uname -m)
    case "$arch" in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        *) log_error "不支持的架构：$arch"; exit 1 ;;
    esac
    log_info "检测到架构：$ARCH"
}

fetch_latest() {
    LATEST=$(curl -fsSL https://api.github.com/repos/jeessy2/ddns-go/releases/latest | grep tag_name | cut -d '"' -f 4)
    [ -z "$LATEST" ] && log_error "获取最新版本失败" && exit 1
    log_info "最新版本：$LATEST"
}

fetch_current() {
    CURRENT=$(/opt/ddns-go/ddns-go -v 2>/dev/null | grep -oE "v[0-9.]+")
    [ -z "$CURRENT" ] && CURRENT="未知"
    log_info "当前版本：$CURRENT"
}

update_binary() {
    if [ "$CURRENT" = "$LATEST" ]; then
        log_success "当前已是最新版本，无需更新"
        exit 0
    fi

    log_info "开始更新..."

    cd /opt/ddns-go
    URL="https://github.com/jeessy2/ddns-go/releases/download/${LATEST}/ddns-go-${LATEST}-linux-${ARCH}.tar.gz"

    curl -L -o ddns-go.tar.gz "$URL"
    tar -xzf ddns-go.tar.gz
    rm -f ddns-go.tar.gz
    chmod +x ddns-go

    systemctl restart ddns-go
    log_success "更新完成，已重启 ddns-go 服务"
}

main() {
    parse_args "$@"
    check_ddns_go
    detect_arch
    fetch_latest
    fetch_current
    update_binary
}

main "$@"
