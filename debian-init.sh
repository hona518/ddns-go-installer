#!/bin/bash

#############################################
#  Oracle / Debian 初始化脚本（旗舰版 v2.3）
#  作者：Amos（由 Copilot 协助优化）
#############################################

set -euo pipefail

LOG_FILE="/var/log/init.log"
STATE_DIR="/etc/init_amos"
mkdir -p "$STATE_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

# 颜色输出
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[36m"
RESET="\033[0m"

info()    { echo -e "${BLUE}[INFO]${RESET} $1"; }
success() { echo -e "${GREEN}[OK]${RESET} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
error()   { echo -e "${RED}[ERROR]${RESET} $1"; exit 1; }

trap 'error "脚本执行中断（行号：$LINENO）"' ERR

# Root 检查
if [ "$(id -u)" -ne 0 ]; then
    error "请使用 root 运行此脚本"
fi

#############################################
# 通用安全执行封装（避免误触发 ERR trap）
#############################################
safe_run() {
    local desc="$1"; shift
    set +e
    "$@"
    local rc=$?
    set -e
    if [ $rc -ne 0 ]; then
        warn "$desc 失败（退出码：$rc）"
    fi
    return 0
}

#############################################
# 检测 Debian 版本
#############################################
detect_debian_version() {
    DEB_VER=$(grep -oE "[0-9]+" /etc/debian_version | head -n1)
    info "检测到 Debian 版本：$DEB_VER"
}

#############################################
# BBR 模块
#############################################
enable_bbr() {
    info "检查 BBR 状态..."

    if ! grep -qw "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control; then
        warn "当前内核不支持 BBR，跳过配置"
        return
    fi

    local CURRENT_CC
    CURRENT_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
    if [ "$CURRENT_CC" = "bbr" ]; then
        success "BBR 已启用，无需重复配置"
        return
    fi

    info "启用 BBR..."
    cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

    safe_run "应用 sysctl 配置" sysctl --system

    local NEW_CC
    NEW_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
    if [ "$NEW_CC" = "bbr" ]; then
        success "BBR 已成功启用"
    else
        warn "BBR 配置写入后未生效，请手动检查"
    fi
}

#############################################
# APT 源配置（幂等）
#############################################
set_apt_sources() {
    if [ -f "$STATE_DIR/sources_done" ]; then
        info "APT 源已配置，跳过"
        return
    fi

    info "配置 Debian 官方源..."
    safe_run "备份 sources.list" mv /etc/apt/sources.list /etc/apt/sources.list.bak

    if [ "$DEB_VER" = "11" ]; then
        cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian bullseye main contrib non-free
deb http://security.debian.org/debian-security bullseye-security main contrib non-free
deb http://deb.debian.org/debian bullseye-updates main contrib non-free
deb http://archive.debian.org/debian bullseye-backports main contrib non-free
EOF
    elif [ "$DEB_VER" = "12" ]; then
        cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ bookworm-backports main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware
EOF
    else
        warn "未知 Debian 版本，跳过 APT 源配置"
    fi

    touch "$STATE_DIR/sources_done"
    success "APT 源已更新"
}

#############################################
# 系统更新（每次执行）
#############################################
update_system() {
    info "更新系统..."
    safe_run "apt-get update"  apt-get update
    safe_run "apt-get upgrade" apt-get upgrade -y
    safe_run "apt-get autoremove" apt-get autoremove -y
    safe_run "apt-get autoclean"  apt-get autoclean -y
    success "系统已更新"
}

#############################################
# 时间同步模块（IPv4 + IPv6 + 冗余 API）
#############################################
get_public_ip() {
    local IP=""
    local apis=(
        "https://api64.ipify.org"
        "https://api.ipify.org"
        "https://ifconfig.me/ip"
        "https://ipinfo.io/ip"
        "https://ipv4.icanhazip.com"
    )

    for api in "${apis[@]}"; do
        local TMP
        TMP=$(curl -s --max-time 5 "$api" || true)
        if [[ "$TMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$TMP" =~ ^[0-9a-fA-F:]+$ ]]; then
            IP="$TMP"
            success "获取公网 IP 成功：$IP（来源：$api）"
            break
        fi
    done

    echo "$IP"
}

setup_time_module() {
    info "开始配置时间同步模块..."

    if ! systemctl list-unit-files | grep -q systemd-timesyncd.service; then
        info "未检测到 systemd-timesyncd，正在安装..."
        safe_run "安装 systemd-timesyncd" apt-get install -y systemd-timesyncd
    fi

    if ! systemctl is-enabled --quiet systemd-timesyncd; then
        info "启用并启动 systemd-timesyncd..."
        safe_run "启用 systemd-timesyncd" systemctl enable --now systemd-timesyncd
    else
        success "systemd-timesyncd 已启用"
    fi

    local IP
    IP=$(get_public_ip)

    if [ -n "$IP" ]; then
        local NEW_TZ=""
        local tz_apis=(
            "https://ipapi.co/${IP}/timezone"
            "https://ipinfo.io/${IP}/timezone"
        )

        for tz_api in "${tz_apis[@]}"; do
            NEW_TZ=$(curl -s --max-time 5 "$tz_api" || true)
            [ -n "$NEW_TZ" ] && [ "$NEW_TZ" != "null" ] && break
        done

        if [ -n "$NEW_TZ" ] && [[ "$NEW_TZ" != "null" ]]; then
            local CURRENT_TZ
            CURRENT_TZ=$(timedatectl show -p Timezone --value 2>/dev/null)
            if [ "$CURRENT_TZ" != "$NEW_TZ" ]; then
                if timedatectl set-timezone "$NEW_TZ"; then
                    success "系统时区已更新为：$NEW_TZ（原来是 $CURRENT_TZ）"
                else
                    warn "时区设置失败，请手动检查"
                fi
            else
                info "系统时区已是：$CURRENT_TZ，无需修改"
            fi
        else
            warn "无法根据 IP 获取时区，跳过自动时区设置"
        fi
    else
        warn "无法获取公网 IP，跳过自动时区设置"
    fi

    local TZ NTP_SERVER
    TZ=$(timedatectl show -p Timezone --value 2>/dev/null)
    case "$TZ" in
        Asia/*)                 NTP_SERVER="asia.pool.ntp.org" ;;
        Europe/*)               NTP_SERVER="europe.pool.ntp.org" ;;
        America/*)              NTP_SERVER="north-america.pool.ntp.org" ;;
        Africa/*)               NTP_SERVER="africa.pool.ntp.org" ;;
        Oceania/*|Australia/*)  NTP_SERVER="oceania.pool.ntp.org" ;;
        *)                      NTP_SERVER="pool.ntp.org" ;;
    esac

    mkdir -p /etc/systemd/timesyncd.conf.d
    local NEW_CONF CONF_FILE
    NEW_CONF="[Time]\nNTP=$NTP_SERVER\nFallbackNTP=pool.ntp.org"
    CONF_FILE="/etc/systemd/timesyncd.conf.d/ntp.conf"

    if [ ! -f "$CONF_FILE" ] || ! diff -q <(echo -e "$NEW_CONF") "$CONF_FILE" >/dev/null 2>&1; then
        echo -e "$NEW_CONF" > "$CONF_FILE"
        safe_run "重启 systemd-timesyncd" systemctl restart systemd-timesyncd
        success "NTP 已更新为：$NTP_SERVER"
    else
        info "NTP 已是：$NTP_SERVER，无需修改"
    fi

    local STATUS_SYNC CURRENT_TZ
    STATUS_SYNC=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    CURRENT_TZ=$(timedatectl show -p Timezone --value 2>/dev/null)
    echo "------ 时间同步状态报告 ------"
    echo "当前时区       : $CURRENT_TZ"
    echo "NTP 服务器     : $NTP_SERVER"
    echo "NTP 是否同步   : $STATUS_SYNC"
    echo "--------------------------------"

    if [ "$STATUS_SYNC" = "yes" ]; then
        success "NTP 同步正常"
    else
        warn "NTP 同步异常，尝试修复..."
        safe_run "重启 systemd-timesyncd" systemctl restart systemd-timesyncd
    fi
}

#############################################
# sing-box 安装 / 更新 / 修复（带缓存 + 非侵入式）
#############################################
setup_or_update_singbox() {
    info "开始安装/更新 sing-box..."

    local ARCH
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l)  ARCH="armv7" ;;
        *)       warn "未识别架构：$(uname -m)，默认使用 amd64"; ARCH="amd64" ;;
    esac

    local OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        OS=$(uname -s)
    fi
    info "检测到系统类型：$OS，CPU 架构：$ARCH"

    local CURRENT_VERSION
    CURRENT_VERSION=$(sing-box version 2>/dev/null | head -n 1 | awk '{print $NF}' | sed 's/^v//')

    local CACHE_FILE="$STATE_DIR/singbox_latest"
    local LATEST_VERSION=""
    local now ts_cached

    now=$(date +%s)
    if [ -f "$CACHE_FILE" ]; then
        ts_cached=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
        if [ $((now - ts_cached)) -lt 86400 ]; then
            LATEST_VERSION=$(cat "$CACHE_FILE" 2>/dev/null || echo "")
            [ -n "$LATEST_VERSION" ] && info "使用缓存的最新版本号：$LATEST_VERSION"
        fi
    fi

    if [ -z "$LATEST_VERSION" ]; then
        LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
            | grep tag_name | head -n 1 | awk -F: '{print $2}' | sed 's/[", v]//g')
        if [ -n "$LATEST_VERSION" ]; then
            echo "$LATEST_VERSION" > "$CACHE_FILE"
        fi
    fi

    info "当前版本：${CURRENT_VERSION:-未安装}，最新版本：${LATEST_VERSION:-获取失败}"

    if [ -z "$LATEST_VERSION" ]; then
        warn "无法获取 sing-box 最新版本号（可能被限流），跳过更新"
        return
    fi

    if [ -n "$CURRENT_VERSION" ]; then
        if dpkg --compare-versions "$CURRENT_VERSION" eq "$LATEST_VERSION"; then
            success "sing-box 已是最新版本：$CURRENT_VERSION，无需更新"
            return
        elif dpkg --compare-versions "$CURRENT_VERSION" gt "$LATEST_VERSION"; then
            success "当前版本 ($CURRENT_VERSION) 高于最新稳定版 ($LATEST_VERSION)，无需更新"
            return
        fi
    fi

    info "检测到新版本：$LATEST_VERSION，准备更新..."

    local PACKAGE_URL INSTALL_TAR=false
    PACKAGE_URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
        | grep "browser_download_url.*${ARCH}.*deb" \
        | cut -d '"' -f4)

    if [ -z "$PACKAGE_URL" ]; then
        PACKAGE_URL=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
            | grep "browser_download_url.*linux-${ARCH}.*tar.gz" \
            | cut -d '"' -f4)
        INSTALL_TAR=true
    fi

    if [ -z "$PACKAGE_URL" ]; then
        warn "未找到适合架构的安装包"
        return
    fi

    local PKG="/tmp/sing-box_${LATEST_VERSION}_${ARCH}"
    if ! curl -L -o "$PKG" "$PACKAGE_URL"; then
        warn "下载失败：$PACKAGE_URL"
        return
    fi

    if [ "$INSTALL_TAR" = true ]; then
        safe_run "解压 sing-box tar 包" tar -xzf "$PKG" -C /tmp
        cp /tmp/sing-box*/sing-box /usr/bin/sing-box
        chmod +x /usr/bin/sing-box
    else
        if ! dpkg -i "$PKG"; then
            warn "dpkg 安装失败，可能缺少依赖"
            return
        fi
    fi

    local CONFIG="/etc/sing-box/config.json"
    local TMP_CONFIG="/tmp/sing-box-config.tmp"

    cat > "$TMP_CONFIG" <<'EOF'
{
  "log": {
    "level": "info",
    "timestamp": true,
    "output": "/var/log/sing-box.log"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "VLESSReality",
      "listen": "0.0.0.0",
      "listen_port": 52368,
      "users": [
        {
          "name": "xwbay-VLESS_Reality_Vision",
          "uuid": "0a733f17-af5c-46e6-a7fd-021677069d6f",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.amd.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.amd.com",
            "server_port": 443
          },
          "private_key": "OGYviki2votqKBOpVODriLzCZhgkl6xq0Mw-w2UAFFk",
          "short_id": [
            "6ba85179e30d4fc2"
          ]
        }
      }
    }
  ],
  "experimental": {
    "cache_file": {
      "enabled": true,
      "path": "/var/lib/sing-box/cache.db"
    }
  }
}
EOF

    if [ ! -f "$CONFIG" ] || ! diff -q "$TMP_CONFIG" "$CONFIG" >/dev/null 2>&1; then
        info "检测到配置文件变更 → 更新主配置"
        safe_run "停止 sing-box" systemctl stop sing-box
        mkdir -p /etc/sing-box
        cp "$TMP_CONFIG" "$CONFIG"
        chmod 644 "$CONFIG"
        safe_run "启动 sing-box" systemctl start sing-box
        success "配置文件已更新并重启 sing-box"
    else
        info "配置文件无变化，跳过更新"
    fi

    rm -f "$TMP_CONFIG"

    if sing-box check -c "$CONFIG"; then
        success "配置文件验证通过"
    else
        warn "配置文件存在错误，请检查 JSON 格式"
        return
    fi

    if systemctl is-active --quiet sing-box; then
        success "sing-box 已安装/更新至版本 $LATEST_VERSION 并运行正常"
        info "配置文件路径：$CONFIG"
        info "最后修改时间：$(stat -c %y "$CONFIG" | cut -d'.' -f1)"

        local SLOG="/var/log/sing-box.log"
        if [ -f "$SLOG" ]; then
            info "输出 sing-box 日志最后 20 行："
            tail -n 20 "$SLOG"
        else
            info "未找到文件日志，输出 systemd 日志："
            safe_run "读取 journalctl" journalctl -u sing-box -n 20 --no-pager
        fi
    else
        warn "sing-box 已安装，但服务未运行"
    fi
}

#############################################
# nftables-only 防火墙体系（放在脚本最后执行）
#############################################
NFT_MAIN="/etc/nftables.conf"
NFT_D_DIR="/etc/nftables.d"
NFT_BACKUP_DIR="/etc/nftables.backups"
NFT_HASH_FILE="/etc/nftables.conf.init.sha256"
NFT_FW_FILE="${NFT_D_DIR}/20-fw-rules.conf"

nft_backup_config() {
    mkdir -p "$NFT_BACKUP_DIR"
    if [ -f "$NFT_MAIN" ]; then
        local ts
        ts=$(date +"%Y%m%d-%H%M%S")
        cp -a "$NFT_MAIN" "$NFT_BACKUP_DIR/nftables.conf.${ts}.bak"
        info "已备份 nftables 配置到：$NFT_BACKUP_DIR/nftables.conf.${ts}.bak"
    fi
}

nft_save_hash() {
    sha256sum "$NFT_MAIN" | awk '{print $1}' > "$NFT_HASH_FILE"
}

nft_check_hash_changed() {
    [ ! -f "$NFT_MAIN" ] || [ ! -f "$NFT_HASH_FILE" ] && return 1
    local old new
    old=$(cat "$NFT_HASH_FILE")
    new=$(sha256sum "$NFT_MAIN" | awk '{print $1}')
    [ "$old" = "$new" ]
}

nft_load_with_backup() {
    mkdir -p "$NFT_BACKUP_DIR"

    local ts backup
    ts=$(date +"%Y%m%d-%H%M%S")
    backup="${NFT_BACKUP_DIR}/nftables.conf.${ts}.preload.bak"
    cp -a "$NFT_MAIN" "$backup"

    if nft -f "$NFT_MAIN"; then
        success "nftables 规则加载成功"
        nft_save_hash
        return 0
    else
        warn "规则加载失败，正在回滚..."
        cp -a "$backup" "$NFT_MAIN"
        safe_run "回滚后重新加载 nftables" nft -f "$NFT_MAIN"
        return 1
    fi
}

nft_status_report() {
    echo "------ nftables 状态报告 ------"
    systemctl is-active --quiet nftables && echo "服务状态       : active" || echo "服务状态       : inactive"
    nft list ruleset | grep -q "table inet filter" && echo "主表 inet filter: 已加载" || echo "主表 inet filter: 未加载"
    nft list ruleset | grep -q "chain input" && echo "链 input       : 存在" || echo "链 input       : 不存在"
    nft list ruleset | grep -q "chain user_input" && echo "链 user_input  : 存在" || echo "链 user_input  : 不存在"
    echo "--------------------------------"
}

setup_nftables_only() {
    info "初始化 nftables-only 防火墙体系..."

    if command -v ufw >/dev/null 2>&1; then
        warn "检测到 UFW → 停用并卸载"
        safe_run "停止 ufw" systemctl stop ufw
        safe_run "禁用 ufw" systemctl disable ufw
        safe_run "关闭 ufw" ufw disable
        safe_run "卸载 ufw" apt-get remove -y ufw
    fi

    if systemctl list-unit-files | grep -q firewalld; then
        warn "检测到 firewalld → 停用并卸载"
        safe_run "停止 firewalld" systemctl stop firewalld
        safe_run "禁用 firewalld" systemctl disable firewalld
        safe_run "卸载 firewalld" apt-get remove -y firewalld
    fi

    if command -v iptables >/dev/null 2>&1; then
        info "清空 iptables 规则"
        safe_run "清空 iptables filter" iptables -F
        safe_run "清空 iptables 自定义链" iptables -X
        safe_run "清空 iptables nat" iptables -t nat -F
        safe_run "清空 iptables nat 链" iptables -t nat -X
        safe_run "清空 iptables mangle" iptables -t mangle -F
        safe_run "清空 iptables mangle 链" iptables -t mangle -X
    fi

    mkdir -p "$NFT_D_DIR"

    local NEED_INIT=false

    if [ ! -f "$NFT_MAIN" ]; then
        NEED_INIT=true
    elif ! nft -c -f "$NFT_MAIN" >/dev/null 2>&1; then
        warn "检测到语法错误，请手动修复 $NFT_MAIN"
        return 1
    fi

    if [ "$NEED_INIT" = false ]; then
        if ! nft list ruleset | grep -q "table inet filter"; then
            warn "当前 ruleset 未包含 table inet filter → 尝试加载现有配置"
            nft_load_with_backup || warn "加载现有配置失败"
        fi

        if ! nft list ruleset | grep -q "table inet filter"; then
            warn "加载现有配置后仍未检测到 table inet filter → 进入最小规则初始化"
            NEED_INIT=true
        fi
    fi

    if [ "$NEED_INIT" = true ]; then
        warn "正在初始化最小规则..."
        nft_backup_config

        cat > "$NFT_MAIN" <<'EOF'
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0;

        iif lo accept
        ct state established,related accept

        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        tcp dport 22 accept

        jump user_input

        reject with icmpx type admin-prohibited
    }

    chain user_input {
    }

    chain forward {
        type filter hook forward priority 0;
        reject with icmpx type admin-prohibited
    }

    chain output {
        type filter hook output priority 0;
        accept
    }
}

include "/etc/nftables.d/*.conf"
EOF

        nft_load_with_backup
        safe_run "启用 nftables 服务" systemctl enable nftables
        safe_run "启动 nftables 服务" systemctl start nftables

        success "nftables-only 初始化完成"
        nft_status_report
        return 0
    fi

    info "检测到有效配置 → 非侵入式模式"

    if ! nft_check_hash_changed; then
        info "检测到用户修改过配置（hash 已变化）"
    else
        info "配置 hash 未变化，保持当前状态"
    fi

    systemctl is-active --quiet nftables || safe_run "启动 nftables 服务" systemctl start nftables

    nft_status_report
    success "nftables-only 防火墙体系已就绪"
}

#############################################
# nft 命令层（专业版 + 重复规则检测 + 帮助菜单）
#############################################
nft_fw_ensure_file() {
    mkdir -p "$NFT_D_DIR"
    if [ ! -f "$NFT_FW_FILE" ]; then
        cat > "$NFT_FW_FILE" <<'EOF'
# nft 命令层规则文件（自动生成）
# 规则入口：chain user_input
# 每条规则末尾带有标记：# nft:<action>:<port>:<proto>
EOF
    fi
}

nft_reload() {
    if ! nft -c -f "$NFT_MAIN" >/dev/null 2>&1; then
        error "语法错误，拒绝加载"
        return 1
    fi
    nft_load_with_backup
}

nft_status() {
    nft_status_report
}

nft_help() {
    cat <<'EOF'
NFT(7)                     User Commands                     NFT(7)

NAME
       nft - nftables 命令层（专业版）

SYNOPSIS
       nft_allow <port|service> [tcp|udp|both]
       nft_deny  <port|service> [tcp|udp|both]
       nft_list
       nft_delete <rule-number>
       nft_reload
       nft_status
       nft_help

DESCRIPTION
       nft 命令层为 nftables-only 防火墙体系提供了类似 UFW 的
       高级端口管理接口。所有规则写入：

           /etc/nftables.d/20-fw-rules.conf

       并通过主配置中的 user_input 链自动加载。

AUTHOR
       Amos & Copilot — 2026

NFT(7)                     User Commands                     NFT(7)
EOF
}

alias nft='nft_help'
alias nft?='nft_help'

nft_resolve_service() {
    local svc="$1"
    local proto="${2:-tcp}"

    [[ "$svc" =~ ^[0-9]+$ ]] && { echo "$svc:$proto"; return; }

    case "$svc" in
        ssh)   echo "22:tcp"; return ;;
        http)  echo "80:tcp"; return ;;
        https) echo "443:tcp"; return ;;
        dns)   echo "53:udp"; return ;;
    esac

    local port
    port=$(getent services "$svc"/"$proto" | awk '{print $2}' | cut -d/ -f1)
    [ -n "$port" ] && { echo "$port:$proto"; return; }

    error "无法解析服务名：$svc"
}

nft_rule_exists() {
    local action="$1" port="$2" proto="$3"
    grep -q "# nft:${action}:${port}:${proto}" "$NFT_FW_FILE" 2>/dev/null
}

nft_allow() {
    local target="${1:-}"
    local proto="${2:-tcp}"

    [ -z "$target" ] && error "用法：nft_allow <端口|服务名> [tcp|udp|both]"

    nft_fw_ensure_file

    local port resolved
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        port="$target"
    else
        resolved=$(nft_resolve_service "$target" "$proto")
        port="${resolved%%:*}"
        proto="${resolved##*:}"
    fi

    case "$proto" in
        tcp|udp)
            if nft_rule_exists "allow" "$port" "$proto"; then
                warn "规则已存在：allow $port/$proto"
            else
                echo "$proto dport $port accept  # nft:allow:$port:$proto" >> "$NFT_FW_FILE"
                info "已允许端口：$port ($proto)"
            fi
            ;;
        both)
            for p in tcp udp; do
                if nft_rule_exists "allow" "$port" "$p"; then
                    warn "规则已存在：allow $port/$p"
                else
                    echo "$p dport $port accept  # nft:allow:$port:$p" >> "$NFT_FW_FILE"
                    info "已允许端口：$port ($p)"
                fi
            done
            ;;
        *)
            error "协议必须是 tcp/udp/both"
            ;;
    esac

    nft_reload
}

nft_deny() {
    local target="${1:-}"
    local proto="${2:-tcp}"

    [ -z "$target" ] && error "用法：nft_deny <端口|服务名> [tcp|udp|both]"

    nft_fw_ensure_file

    local port resolved
    if [[ "$target" =~ ^[0-9]+$ ]]; then
        port="$target"
    else
        resolved=$(nft_resolve_service "$target" "$proto")
        port="${resolved%%:*}"
        proto="${resolved##*:}"
    fi

    case "$proto" in
        tcp|udp)
            if nft_rule_exists "deny" "$port" "$proto"; then
                warn "规则已存在：deny $port/$proto"
            else
                echo "$proto dport $port drop  # nft:deny:$port:$proto" >> "$NFT_FW_FILE"
                info "已拒绝端口：$port ($proto)"
            fi
            ;;
        both)
            for p in tcp udp; do
                if nft_rule_exists "deny" "$port" "$p"; then
                    warn "规则已存在：deny $port/$p"
                else
                    echo "$p dport $port drop  # nft:deny:$port:$p" >> "$NFT_FW_FILE"
                    info "已拒绝端口：$port ($p)"
                fi
            done
            ;;
        *)
            error "协议必须是 tcp/udp/both"
            ;;
    esac

    nft_reload
}

nft_list() {
    nft_fw_ensure_file
    echo "------ nft 命令层规则列表 ------"
    nl -ba "$NFT_FW_FILE"
    echo "--------------------------------"
}

nft_delete() {
    local id="${1:-}"
    [ -z "$id" ] && error "用法：nft_delete <编号>"

    nft_fw_ensure_file

    sed -n "${id}p" "$NFT_FW_FILE" >/dev/null 2>&1 || error "编号不存在"

    sed -i "${id}d" "$NFT_FW_FILE"
    info "已删除规则编号：$id"

    nft_reload
}

#############################################
# 自动加载 nft 命令层到 ~/.bashrc（路径自适应）
#############################################
install_nft_command_layer_auto() {
    local bashrc="$HOME/.bashrc"
    local script_path

    script_path="$(realpath "$0" 2>/dev/null || true)"

    if [ -z "$script_path" ] || [ ! -f "$script_path" ]; then
        warn "无法检测脚本路径，跳过 bashrc 注入"
        return
    fi

    info "检测到脚本路径：$script_path"

    touch "$bashrc"

    sed -i '/debian-init.sh/d' "$bashrc"

    {
        echo ""
        echo "# 自动加载 nft 命令层（路径自适应，仅加载函数，不自动执行 main）"
        echo "if [ -f \"$script_path\" ]; then"
        echo "    source \"$script_path\""
        echo "fi"
    } >> "$bashrc"

    success "已将脚本路径写入 ~/.bashrc：$script_path"
    info "请重新登录 SSH 以启用 nft 命令层"
}

#############################################
# 主流程（nftables 放在最后执行）
#############################################
main() {
    info "开始系统初始化流程..."

    detect_debian_version
    enable_bbr
    set_apt_sources
    update_system
    setup_time_module
    setup_or_update_singbox

    setup_nftables_only
    install_nft_command_layer_auto

    success "全部任务执行完毕！系统已成功初始化"
    info "日志文件：$LOG_FILE"
}

# 防止被 source 时自动执行 main（避免循环）
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
