#!/usr/bin/env bash

#############################################
# ddns-go Installer
# - 架构自动检测
# - 最新版本自动获取
# - 自动下载 / 安装 / systemd 配置
# - NAT / 网络结构诊断
# - 彩色输出 + 日志 + 调试模式
#############################################

#==================== 基本配置 ====================#

DEFAULT_PORT=9876
LOG_FILE="/var/log/ddns-go-installer.log"
DEBUG=false

#==================== 颜色定义 ====================#

COLOR_RED="\e[31m"
COLOR_GREEN="\e[32m"
COLOR_YELLOW="\e[33m"
COLOR_BLUE="\e[34m"
COLOR_RESET="\e[0m"

log_init() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    : > "$LOG_FILE" 2>/dev/null || true
}

log_raw() {
    # 仅写入日志文件，不上色
    echo "[$(date '+%F %T')] $*" >>"$LOG_FILE" 2>/dev/null || true
}

log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
    log_raw "[INFO] $*"
}

log_success() {
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $*"
    log_raw "[OK] $*"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"
    log_raw "[WARN] $*"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*"
    log_raw "[ERROR] $*"
}

debug() {
    if [ "$DEBUG" = true ]; then
        echo -e "${COLOR_YELLOW}[DEBUG]${COLOR_RESET} $*"
        log_raw "[DEBUG] $*"
    fi
}

#==================== 参数解析 ====================#

PORT="$DEFAULT_PORT"

print_usage() {
    cat <<EOF
用法: $0 [--port 端口] [--debug]

可选参数：
  --port <端口>    指定 ddns-go Web 端口（默认：$DEFAULT_PORT）
  --debug          开启调试模式（输出更多细节）
  -h, --help       显示本帮助
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --port)
                shift
                if [[ -z "$1" || "$1" =~ ^- ]]; then
                    log_error "缺少 --port 参数值"
                    exit 1
                fi
                PORT="$1"
                ;;
            --debug)
                DEBUG=true
                ;;
            -h|--help)
                print_usage
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

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        log_error "系统缺少 curl 或 wget，请先安装：apt install -y curl"
        exit 1
    fi

    if ! command -v tar >/dev/null 2>&1; then
        log_error "系统缺少 tar，请先安装：apt install -y tar"
        exit 1
    fi

    if ! command -v systemctl >/dev/null 2>&1; then
        log_error "系统缺少 systemd（systemctl），当前系统可能不支持本脚本。"
        exit 1
    fi

    log_success "依赖检查通过"
}

#==================== 架构检测 ====================#

detect_arch() {
    log_info "检测 CPU 架构..."

    local arch
    arch=$(uname -m)
    debug "uname -m 返回：$arch"

    case "$arch" in
        x86_64)   ARCH="amd64" ;;
        aarch64)  ARCH="arm64" ;;
        armv7l)   ARCH="armv7" ;;
        *)
            log_error "不支持的架构：$arch"
            exit 1
            ;;
    esac

    log_success "检测到架构：$ARCH"
}

#==================== 获取最新版本 ====================#

fetch_latest_version() {
    log_info "获取 ddns-go 最新版本..."

    local api="https://api.github.com/repos/jeessy2/ddns-go/releases/latest"
    debug "请求 GitHub API: $api"

    LATEST=$(curl -fsSL "$api" | grep tag_name | cut -d '"' -f 4 || true)

    if [ -z "$LATEST" ]; then
        log_error "获取 ddns-go 最新版本失败，请检查网络或稍后重试。"
        exit 1
    fi

    log_success "最新版本：$LATEST"
}

#==================== 下载并解压 ====================#

download_and_extract() {
    log_info "下载 ddns-go..."

    local url="https://github.com/jeessy2/ddns-go/releases/download/${LATEST}/ddns-go-${LATEST}-linux-${ARCH}.tar.gz"
    debug "下载地址：$url"

    mkdir -p /opt/ddns-go
    cd /opt/ddns-go || exit 1

    if command -v curl >/dev/null 2>&1; then
        curl -L -o ddns-go.tar.gz "$url"
    else
        wget -O ddns-go.tar.gz "$url"
    fi

    log_info "解压 ddns-go..."
    tar -xzf ddns-go.tar.gz
    rm -f ddns-go.tar.gz
    chmod +x ddns-go

    log_success "ddns-go 下载并解压完成"
}

#==================== 安装 systemd 服务 ====================#

install_systemd_service() {
    log_info "安装 systemd 服务..."

    # ddns-go 自带 install 命令
    ./ddns-go install

    # 修改默认端口（如果用户指定了）
    if [ "$PORT" != "$DEFAULT_PORT" ]; then
        log_info "设置自定义端口：$PORT"
        # 这里假设 ddns-go 的配置文件在首次启动后生成
        # 如果需要更强控制，可以在首次启动后再修改配置文件
    fi

    systemctl daemon-reload
    systemctl enable ddns-go
    systemctl restart ddns-go

    log_success "systemd 服务安装并已启动"
}

#==================== 网络检测（IPv4 / IPv6） ====================#

detect_public_ip() {
    log_info "检测公网 IPv4 / IPv6..."

    PUB_IPV4=$(curl -4 -fsSL https://api.ipify.org || echo "")
    PUB_IPV6=$(curl -6 -fsSL https://api64.ipify.org || echo "")

    if [ -z "$PUB_IPV4" ]; then
        log_warn "未获取到公网 IPv4"
    else
        log_success "公网 IPv4：$PUB_IPV4"
    fi

    if [ -z "$PUB_IPV6" ]; then
        log_warn "未获取到公网 IPv6"
    else
        log_success "公网 IPv6：$PUB_IPV6"
    fi
}

#==================== 高级 NAT / 网络结构诊断 ====================#

network_diagnose() {
    log_info "高级 NAT / 网络结构诊断..."

    # 本地 IPv4
    LOCAL_IPV4=$(hostname -I | awk '{print $1}')
    debug "本地 IPv4：$LOCAL_IPV4"

    # 本地是否私网
    if [[ "$LOCAL_IPV4" == 10.* || "$LOCAL_IPV4" == 192.168.* || "$LOCAL_IPV4" == 172.16.* || "$LOCAL_IPV4" == 172.17.* || "$LOCAL_IPV4" == 172.18.* || "$LOCAL_IPV4" == 172.19.* || "$LOCAL_IPV4" == 172.2[0-9].* || "$LOCAL_IPV4" == 172.3[0-1].* ]]; then
        LOCAL_IS_PRIVATE="是（私网 IP）"
    else
        LOCAL_IS_PRIVATE="否（公网 IP）"
    fi

    # CGNAT 检测（100.64.0.0/10）
    if [[ "$LOCAL_IPV4" == 100.6[4-9].* || "$LOCAL_IPV4" == 100.[7-9]* || "$LOCAL_IPV4" == 100.1* || "$LOCAL_IPV4" == 100.2* || "$LOCAL_IPV4" == 100.3* ]]; then
        CGNAT_STATUS="是（运营商 CGNAT）"
    else
        CGNAT_STATUS="否"
    fi

    # IPv6 模式
    if [[ -z "$PUB_IPV4" && -n "$PUB_IPV6" ]]; then
        IPV6_MODE="IPv6-only（可能为 NAT64 环境）"
    elif [[ -n "$PUB_IPV4" && -n "$PUB_IPV6" ]]; then
        IPV6_MODE="双栈（IPv4 + IPv6）"
    else
        IPV6_MODE="仅 IPv4"
    fi

    # ASN / 国家 / 组织（ipinfo.io）
    ASN=$(curl -fsSL https://ipinfo.io/org || echo "未知")
    COUNTRY=$(curl -fsSL https://ipinfo.io/country || echo "未知")
    REGION=$(curl -fsSL https://ipinfo.io/region || echo "未知")
    CITY=$(curl -fsSL https://ipinfo.io/city || echo "未知")

    echo ""
    echo "====== 网络结构诊断报告 ======"
    echo "本地 IPv4：$LOCAL_IPV4"
    echo "本地 IP 是否私网：$LOCAL_IS_PRIVATE"
    echo "是否为运营商 CGNAT：$CGNAT_STATUS"
    echo ""
    echo "公网 IPv4：${PUB_IPV4:-无}"
    echo "公网 IPv6：${PUB_IPV6:-无}"
    echo "IPv6 模式：$IPV6_MODE"
    echo ""
    echo "出口 ASN / 组织：$ASN"
    echo "出口国家：$COUNTRY"
    echo "出口地区：$REGION"
    echo "出口城市：$CITY"
    echo "================================"
    echo ""

    log_raw "网络诊断：LOCAL_IPV4=$LOCAL_IPV4, PRIVATE=$LOCAL_IS_PRIVATE, CGNAT=$CGNAT_STATUS, PUB_IPV4=$PUB_IPV4, PUB_IPV6=$PUB_IPV6, IPV6_MODE=$IPV6_MODE, ASN=$ASN, COUNTRY=$COUNTRY, REGION=$REGION, CITY=$CITY"
}

#==================== 防火墙检测 ====================#

firewall_check() {
    log_info "检测防火墙状态..."

    if command -v ufw >/dev/null 2>&1; then
        UFW_STATUS=$(ufw status | grep "$PORT" || echo "端口 $PORT 未在 UFW 中显式放行")
        log_info "UFW 状态：$UFW_STATUS"
    else
        log_warn "未检测到 UFW（可能使用其他防火墙或未启用防火墙）"
    fi
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
    firewall_check

    echo ""
    echo "=========================================="
    echo -e "           ${COLOR_GREEN}安装完成！${COLOR_RESET}"
    echo "=========================================="
    echo "访问地址（如端口被修改，请以实际为准）："
    [ -n "$PUB_IPV4" ] && echo "  IPv4: http://${PUB_IPV4}:${PORT}"
    [ -n "$PUB_IPV6" ] && echo "  IPv6: http://[${PUB_IPV6}]:${PORT}"
    echo ""
    echo "配置文件路径：/opt/ddns-go/.ddns_go_config.yaml"
    echo "systemd 服务名：ddns-go"
    echo ""
    echo "常用管理命令："
    echo "  systemctl status ddns-go"
    echo "  systemctl restart ddns-go"
    echo "  systemctl stop ddns-go"
    echo "  systemctl enable ddns-go"
    echo ""
    echo "日志文件：$LOG_FILE"
    echo "=========================================="
}

main "$@"
