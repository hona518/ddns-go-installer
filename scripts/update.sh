#!/usr/bin/env bash

#############################################
# ddns-go Updater (增强版)
#############################################

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
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --debug)
                DEBUG=true
                ;;
            -h|--help)
                echo "用法: $0 [--debug]"
                exit 0
                ;;
            *)
                log_warn "忽略未知参数：$1"
                ;;
        esac
        shift
    done
}

#==================== 检查依赖 ====================#
check_dependencies() {
    log_info "检查依赖..."

    for cmd in curl tar systemctl ss; do
        if ! command -v $cmd >/dev/null 2>&1; then
            log_error "缺少依赖：$cmd"
            exit 1
        fi
    done

    log_success "依赖检查通过"
}

#==================== 检测当前端口 ====================#
detect_port() {
    SERVICE_FILE="/etc/systemd/system/ddns-go.service"

    if [ ! -f "$SERVICE_FILE" ]; then
        log_error "未找到 systemd 服务文件：$SERVICE_FILE"
        exit 1
    fi

    PORT=$(grep ExecStart "$SERVICE_FILE" | sed -E 's/.*-l :([0-9]+).*/\1/')

    if [ -z "$PORT" ]; then
        log_warn "未找到端口，使用默认端口 9876"
        PORT=9876
    fi

    log_success "当前端口：$PORT"
}

#==================== 交互式修改端口 ====================#
ask_new_port() {
    echo ""
    echo -n "是否需要修改端口？[y/N]: "
    read -r change_port

    case "$change_port" in
        y|Y)
            echo -n "请输入新的端口号（1-65535）： "
            read -r new_port

            if ! [[ "$new_port" =~ ^[0-9]+$ ]]; then
                log_error "端口必须是数字"
                ask_new_port
                return
            fi

            if [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
                log_error "端口必须在 1-65535 范围内"
                ask_new_port
                return
            fi

            PORT=$new_port
            log_success "端口已修改为：${PORT}"
            ;;
        *)
            log_info "保持原端口：${PORT}"
            ;;
    esac
}

#==================== 检测端口占用 ====================#
check_port_in_use() {
    log_info "检测端口是否被占用..."

    if ss -tulnp | grep -q ":${PORT} "; then
        PROCESS=$(ss -tulnp | grep ":${PORT} " | awk '{print $NF}')
        log_warn "端口 ${PORT} 已被占用（进程：${PROCESS}）"
        echo "更新后 ddns-go 可能无法正常启动，请注意。"
    else
        log_success "端口 ${PORT} 未被占用"
    fi
}

#==================== 获取最新版本 ====================#
fetch_latest_version() {
    log_info "获取 ddns-go 最新版本..."

    LATEST=$(curl -fsSL https://api.github.com/repos/jeessy2/ddns-go/releases/latest | grep tag_name | cut -d '"' -f 4)
    VERSION="${LATEST#v}"

    if [ -z "$VERSION" ]; then
        log_error "获取最新版本失败"
        exit 1
    fi

    log_success "最新版本：$LATEST（实际版本号：$VERSION）"
}

#==================== 检测 CPU 架构 ====================#
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

#==================== 下载并替换二进制 ====================#
download_and_replace() {
    log_info "下载 ddns-go 最新版本..."

    cd /opt/ddns-go || exit 1

    URL="https://github.com/jeessy2/ddns-go/releases/download/${LATEST}/ddns-go_${VERSION}_${DDNS_ARCH}.tar.gz"
    debug "下载地址：$URL"

    curl -L -o ddns-go.tar.gz "$URL"

    if [ "$(stat -c%s ddns-go.tar.gz)" -lt 100000 ]; then
        log_error "下载文件异常（可能是 404 页面）"
        exit 1
    fi

    log_info "解压 ddns-go..."

    if ! tar -xzf ddns-go.tar.gz; then
        log_error "解压失败"
        exit 1
    fi

    rm -f ddns-go.tar.gz
    chmod +x ddns-go

    log_success "ddns-go 更新完成"
}

#==================== 修复 systemd 服务端口 ====================#
fix_systemd_port() {
    SERVICE_FILE="/etc/systemd/system/ddns-go.service"

    log_info "写入端口到 systemd 服务文件..."

    sed -i "s|ExecStart=.*|ExecStart=/opt/ddns-go/ddns-go -l :${PORT}|g" "$SERVICE_FILE"

    systemctl daemon-reload
    systemctl restart ddns-go

    log_success "systemd 服务已更新为端口：${PORT}"
}

#==================== 主流程 ====================#
main() {
    echo "=========================================="
    echo "     ddns-go Updater (自动更新脚本)"
    echo "=========================================="

    log_init
    parse_args "$@"

    check_dependencies
    detect_port
    ask_new_port
    check_port_in_use
    fetch_latest_version
    detect_arch
    download_and_replace
    fix_systemd_port

    echo ""
    echo "=========================================="
    echo -e "        ${COLOR_GREEN}更新完成！${COLOR_RESET}"
    echo "=========================================="
    echo "当前端口：${PORT}"
    echo "日志文件：$LOG_FILE"
    echo "=========================================="
}

main "$@"
