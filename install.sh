#!/usr/bin/env bash

#############################################
# ddns-go Installer (修复版)
# - 自动架构检测
# - 自动获取最新版本
# - 正确下载 ddns-go 官方 tar.gz
# - 完整 systemd 安装
# - NAT / IPv6 / ASN 检测
# - 彩色输出 + 日志 + 调试模式
#############################################

DEFAULT_PORT=9876
LOG_FILE="/var/log/ddns-go-installer.log"
DEBUG=false

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
debug() { [ "$DEBUG" = true ] && echo -e "${COLOR_YELLOW}[DEBUG]${COLOR_RESET} $*" && log_raw "[DEBUG] $*"; }

#==================== 参数解析 ====================#
PORT="$DEFAULT_PORT"

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --port)
                shift
                PORT="$1"
                ;;
            --debug)
                DEBUG=true
                ;;
            -h|--help)
                echo "用法: $0 [--port 9876] [--debug]"
                exit 0
                ;;
            *)
                log_warn "忽略未知参数：$1"
                ;;
        esac
        shift
    done
}

#==================== 依赖检查 ====================#
check_dependencies() {
    log_info "检查依赖..."

    for cmd in curl tar systemctl; do
        if ! command -v $cmd >/dev/null 2>&1; then
            log_error "缺少依赖：$cmd"
            exit 1
        fi
    done

    log_success "依赖检查通过"
}

#==================== 架构检测 ====================#
detect_arch() {
    log_info "检测 CPU 架构..."

    case "$(uname -m)" in
        x86_64)   DDNS_ARCH="linux_x86_64" ;;
        aarch64)  DDNS_ARCH="linux_arm64" ;;
        armv7l)   DDNS_ARCH="linux_armv7" ;;
        *)
            log_error "不支持的架构：$(uname -m)"
            exit 1
            ;;
    esac

    log_success "检测到架构：$DDNS_ARCH"
}

#==================== 获取最新版本 ====================#
fetch_latest_version() {
    log_info "获取 ddns-go 最新版本..."

    LATEST=$(curl -fsSL https://api.github.com/repos/jeessy2/ddns-go/releases/latest | grep tag_name | cut -d '"' -f 4)

    if [ -z "$LATEST" ]; then
        log_error "获取最新版本失败"
        exit 1
    fi

    VERSION="${LATEST#v}"

    log_success "最新版本：$LATEST（实际版本号：$VERSION）"
}

#==================== 下载并解压 ====================#
download_and_extract() {
    log_info "下载 ddns-go..."

    mkdir -p /opt/ddns-go
    cd /opt/ddns-go || exit 1

    URL="https://github.com/jeessy2/ddns-go/releases/download/${LATEST}/ddns-go_${VERSION}_${DDNS_ARCH}.tar.gz"
    debug "下载地址：$URL"

    curl -L -o ddns-go.tar.gz "$URL"

    # 校验文件大小（避免下载到 404 HTML）
    if [ "$(stat -c%s ddns-go.tar.gz)" -lt 100000 ]; then
        log_error "下载文件异常（可能是 404 页面），请检查网络或版本号"
        exit 1
    fi

    log_info "解压 ddns-go..."

    if ! tar -xzf ddns-go.tar.gz; then
        log_error "解压失败，文件可能损坏"
        exit 1
    fi

    rm -f ddns-go.tar.gz
    chmod +x ddns-go

    log_success "ddns-go 下载并解压完成"
}

#==================== 安装 systemd 服务 ====================#
install_systemd_service() {
    log_info "安装 systemd 服务..."

    ./ddns-go install

    systemctl daemon-reload
    systemctl enable ddns-go
    systemctl restart ddns-go

    log_success "systemd 服务安装并已启动"
}

#==================== 公网 IP 检测 ====================#
detect_public_ip() {
    log_info "检测公网 IP..."

    PUB_IPV4=$(curl -4 -fsSL https://api.ipify.org || echo "")
    PUB_IPV6=$(curl -6 -fsSL https://api64.ipify.org || echo "")

    [ -n "$PUB_IPV4" ] && log_success "公网 IPv4：$PUB_IPV4" || log_warn "未获取到公网 IPv4"
    [ -n "$PUB_IPV6" ] && log_success "公网 IPv6：$PUB_IPV6" || log_warn "未获取到公网 IPv6"
}

#==================== NAT / 网络结构诊断 ====================#
network_diagnose() {
    log_info "网络结构诊断..."

    LOCAL_IPV4=$(hostname -I | awk '{print $1}')

    if [[ "$LOCAL_IPV4" =~ ^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
        PRIVATE="是（私网）"
    else
        PRIVATE="否（公网）"
    fi

    if [[ "$LOCAL_IPV4" =~ ^100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\. ]]; then
        CGNAT="是（运营商 CGNAT）"
    else
        CGNAT="否"
    fi

    ASN=$(curl -fsSL https://ipinfo.io/org || echo "未知")
    COUNTRY=$(curl -fsSL https://ipinfo.io/country || echo "未知")

    echo ""
    echo "====== 网络诊断报告 ======"
    echo "本地 IPv4：$LOCAL_IPV4"
    echo "是否私网：$PRIVATE"
    echo "是否 CGNAT：$CGNAT"
    echo "公网 IPv4：${PUB_IPV4:-无}"
    echo "公网 IPv6：${PUB_IPV6:-无}"
    echo "ASN：$ASN"
    echo "国家：$COUNTRY"
    echo "=========================="
    echo ""
}

#==================== 主流程 ====================#
main() {
    echo "=========================================="
    echo "     ddns-go Installer (自动安装脚本)"
    echo "=========================================="

    log_init
    parse_args "$@"

    log_info "使用端口：$PORT"
    [ "$DEBUG" = true ] && log_info "调试模式已开启"

    check_dependencies
    detect_arch
    fetch_latest_version
    download_and_extract
    install_systemd_service
    detect_public_ip
    network_diagnose

    echo ""
    echo "=========================================="
    echo -e "           ${COLOR_GREEN}安装完成！${COLOR_RESET}"
    echo "=========================================="
    echo "访问地址："
    [ -n "$PUB_IPV4" ] && echo "  IPv4: \`http://${PUB_IPV4}:${PORT}\`"
    [ -n "$PUB_IPV6" ] && echo "  IPv6: \`http://[${PUB_IPV6}]:${PORT}\`"
    echo ""
    echo "配置文件：/opt/ddns-go/.ddns_go_config.yaml"
    echo "systemd 服务名：ddns-go"
    echo "日志文件：$LOG_FILE"
    echo "=========================================="
}

main "$@"
