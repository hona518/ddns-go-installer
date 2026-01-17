#!/usr/bin/env bash

#############################################
# ddns-go Uninstaller
# 卸载 ddns-go + systemd 服务
#############################################

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

uninstall() {
    log_info "停止 ddns-go 服务..."
    systemctl stop ddns-go 2>/dev/null || log_warn "服务可能未运行"

    log_info "禁用 ddns-go 服务..."
    systemctl disable ddns-go 2>/dev/null || true

    log_info "删除 systemd 服务文件..."
    rm -f /etc/systemd/system/ddns-go.service
    systemctl daemon-reload

    log_info "删除程序文件..."
    rm -rf /opt/ddns-go

    log_success "ddns-go 已成功卸载"
    echo ""
    echo "日志文件保留在：$LOG_FILE"
}

main() {
    parse_args "$@"
    uninstall
}

main "$@"
