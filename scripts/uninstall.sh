#!/usr/bin/env bash

#############################################
# ddns-go Uninstaller (最终增强版)
#############################################

LOG_FILE="/var/log/ddns-go-installer.log"

#==================== 颜色 ====================#
COLOR_RED="\e[31m"
COLOR_GREEN="\e[32m"
COLOR_YELLOW="\e[33m"
COLOR_BLUE="\e[34m"
COLOR_RESET="\e[0m"

log_init() {
    mkdir -p "$(dirname "$LOG_FILE")"
    : > "$LOG_FILE"
}

log_raw() { echo "[$(date '+%F %T')] $*" >>"$LOG_FILE"; }
log_info() { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"; log_raw "[INFO] $*"; }
log_success() { echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $*"; log_raw "[OK] $*"; }
log_warn() { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"; log_raw "[WARN] $*"; }
log_error() { echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*"; log_raw "[ERROR] $*"; }

#==================== 检测端口 ====================#
detect_port() {
    SERVICE_FILE="/etc/systemd/system/ddns-go.service"

    if [ ! -f "$SERVICE_FILE" ]; then
        log_warn "未找到 systemd 服务文件，无法检测端口"
        PORT=""
        return
    fi

    PORT=$(grep ExecStart "$SERVICE_FILE" | sed -E 's/.*-l :([0-9]+).*/\1/')

    if [ -z "$PORT" ]; then
        log_warn "未在 systemd 服务文件中找到端口"
    else
        log_info "检测到 ddns-go 使用端口：${PORT}"
    fi
}

#==================== 停止并禁用服务 ====================#
remove_systemd_service() {
    log_info "停止并禁用 ddns-go 服务..."

    systemctl stop ddns-go 2>/dev/null
    systemctl disable ddns-go 2>/dev/null

    if [ -f "/etc/systemd/system/ddns-go.service" ]; then
        rm -f /etc/systemd/system/ddns-go.service
        systemctl daemon-reload
        log_success "systemd 服务已删除"
    else
        log_warn "未找到 systemd 服务文件"
    fi
}

#==================== 删除程序文件 ====================#
remove_binary() {
    log_info "删除 ddns-go 程序文件..."

    if [ -f "/opt/ddns-go/ddns-go" ]; then
        rm -f /opt/ddns-go/ddns-go
        log_success "已删除 /opt/ddns-go/ddns-go"
    else
        log_warn "未找到 ddns-go 二进制文件"
    fi
}

#==================== 删除配置文件 ====================#
remove_config() {
    echo -n "是否删除配置文件（/opt/ddns-go/.ddns_go_config.yaml）？[y/N]: "
    read -r answer

    case "$answer" in
        y|Y)
            rm -f /opt/ddns-go/.ddns_go_config.yaml 2>/dev/null
            log_success "配置文件已删除"
            ;;
        *)
            log_info "已保留配置文件"
            ;;
    esac
}

#==================== 防火墙清理提示 ====================#
cleanup_firewall() {
    if [ -z "$PORT" ]; then
        log_warn "未检测到端口，跳过防火墙清理提示"
        return
    fi

    echo ""
    echo "================ 防火墙清理提示 ================"

    # UFW
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "${PORT}"; then
            echo -e "${COLOR_YELLOW}UFW 中存在端口 ${PORT} 的放行规则${COLOR_RESET}"
            echo "如需删除： ufw delete allow ${PORT}"
        fi
    fi

    # firewalld
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        if firewall-cmd --list-ports | grep -q "${PORT}/tcp"; then
            echo -e "${COLOR_YELLOW}firewalld 中存在端口 ${PORT}/tcp 的放行规则${COLOR_RESET}"
            echo "如需删除： firewall-cmd --permanent --remove-port=${PORT}/tcp && firewall-cmd --reload"
        fi
    fi

    # iptables
    if command -v iptables >/dev/null 2>&1; then
        if iptables -L INPUT -n | grep -q "${PORT}"; then
            echo -e "${COLOR_YELLOW}iptables 中存在端口 ${PORT} 的放行规则${COLOR_RESET}"
            echo "如需删除： iptables -D INPUT -p tcp --dport ${PORT} -j ACCEPT"
        fi
    fi

    echo "================================================"
}

#==================== 主流程 ====================#
main() {
    echo "=========================================="
    echo "     ddns-go Uninstaller (卸载脚本)"
    echo "=========================================="

    log_init
    detect_port
    remove_systemd_service
    remove_binary
    remove_config
    cleanup_firewall

    echo ""
    echo "=========================================="
    echo -e "        ${COLOR_GREEN}卸载完成！${COLOR_RESET}"
    echo "=========================================="
    echo "日志文件：$LOG_FILE"
    echo "=========================================="
}

main "$@"
