#!/bin/bash

#############################################
#  Oracle / Debian 初始化脚本（旗舰修复版 v3.0）
#  优化：Amos & Gemini
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

# 通用安全执行封装
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
# 检测系统版本
#############################################
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
        VERSION_ID=${VERSION_ID:-0}
    else
        OS_ID=$(uname -s)
        VERSION_ID=0
    fi
    info "检测到系统：$OS_ID $VERSION_ID"
}

#############################################
# 检测 SSH 端口
#############################################
detect_ssh_ports() {
    SSH_PORTS=()
    if [ -f /etc/ssh/sshd_config ]; then
        while read -r line; do
            line="${line%%#*}"
            line="$(echo "$line" | xargs || true)"
            [ -z "$line" ] && continue
            if [[ "$line" =~ ^Port[[:space:]]+([0-9]+)$ ]]; then
                SSH_PORTS+=("${BASH_REMATCH[1]}")
            fi
        done < /etc/ssh/sshd_config
    fi
    [ ${#SSH_PORTS[@]} -eq 0 ] && SSH_PORTS=(22)
    info "检测到 SSH 端口：${SSH_PORTS[*]}"
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
        success "BBR 已启用"
        return
    fi

    info "启用 BBR..."
    cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl --system >/dev/null 2>&1
    success "BBR 已成功启用"
}

#############################################
# APT 源配置（仅限 Debian）
#############################################
set_apt_sources() {
    if [ "$OS_ID" != "debian" ]; then
        info "非标准 Debian 系统 ($OS_ID)，跳过 APT 源覆盖以保证安全"
        return
    fi

    if [ -f "$STATE_DIR/sources_done" ]; then
        info "APT 源已配置，跳过"
        return
    fi

    info "配置 Debian 官方源..."
    cp /etc/apt/sources.list /etc/apt/sources.list.bak

    # 去除非数字字符
    DEB_MAJOR_VER=$(echo "$VERSION_ID" | grep -oE "^[0-9]+")

    if [ "$DEB_MAJOR_VER" = "11" ]; then
        cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian bullseye main contrib non-free
deb http://security.debian.org/debian-security bullseye-security main contrib non-free
deb http://deb.debian.org/debian bullseye-updates main contrib non-free
deb http://archive.debian.org/debian bullseye-backports main contrib non-free
EOF
    elif [ "$DEB_MAJOR_VER" = "12" ]; then
        cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ bookworm-backports main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware
EOF
    else
        warn "未涵盖的 Debian 版本 ($VERSION_ID)，跳过源配置"
    fi

    touch "$STATE_DIR/sources_done"
    success "APT 源已更新"
}

#############################################
# 系统更新
#############################################
update_system() {
    info "更新系统软件包..."
    export DEBIAN_FRONTEND=noninteractive
    safe_run "apt update" apt-get update
    safe_run "apt upgrade" apt-get upgrade -y
    safe_run "apt autoremove" apt-get autoremove -y
    success "系统更新完成"
}

#############################################
# 时间同步模块
#############################################
setup_time_module() {
    info "配置时间同步..."
    if ! command -v systemd-timesyncd >/dev/null; then
        apt-get install -y systemd-timesyncd
    fi
    systemctl enable --now systemd-timesyncd

    # 简单粗暴：强制使用 Google/Cloudflare NTP
    mkdir -p /etc/systemd/timesyncd.conf.d
    cat > /etc/systemd/timesyncd.conf.d/ntp.conf <<EOF
[Time]
NTP=time.google.com time.cloudflare.com pool.ntp.org
FallbackNTP=ntp.ubuntu.com
EOF
    systemctl restart systemd-timesyncd
    
    # 尝试自动设置时区 (通过 IP API)
    local IP TZ_API
    IP=$(curl -s --max-time 3 https://api.ipify.org || echo "")
    if [ -n "$IP" ]; then
        TZ_API=$(curl -s --max-time 3 "http://ip-api.com/line/${IP}?fields=timezone" || echo "")
        if [ -n "$TZ_API" ] && [[ "$TZ_API" != *"fail"* ]]; then
             timedatectl set-timezone "$TZ_API"
             success "时区已更新为: $TZ_API"
        fi
    fi
}

#############################################
# sing-box 智能安装/修复
#############################################
setup_or_update_singbox() {
    info "正在处理 sing-box..."

    # 1. 架构判断
    local ARCH
    case "$(uname -m)" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *)       warn "不支持的架构"; return ;;
    esac

    # 2. 版本获取 (带 Fallback)
    local LATEST_VERSION
    LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep tag_name | cut -d '"' -f4 | sed 's/^v//')
    if [ -z "$LATEST_VERSION" ]; then
        warn "GitHub API 受限，尝试使用固定版本 check (1.10.6)"
        LATEST_VERSION="1.10.6" # 备用版本
    fi
    
    local CURRENT_VERSION
    CURRENT_VERSION=$(sing-box version 2>/dev/null | head -n1 | awk '{print $3}')

    if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
        success "sing-box 已是最新 ($CURRENT_VERSION)，跳过安装"
    else
        info "开始安装/更新至 $LATEST_VERSION..."
        local DL_URL="https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VERSION}/sing-box_${LATEST_VERSION}_linux_${ARCH}.deb"
        local PKG_FILE="/tmp/sing-box.deb"
        local USE_TAR=false

        if ! curl -L -o "$PKG_FILE" "$DL_URL"; then
            warn "Deb 包下载失败，尝试下载 Tar 包..."
            DL_URL="https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VERSION}/sing-box-${LATEST_VERSION}-linux-${ARCH}.tar.gz"
            PKG_FILE="/tmp/sing-box.tar.gz"
            curl -L -o "$PKG_FILE" "$DL_URL" || error "下载失败"
            USE_TAR=true
        fi

        if [ "$USE_TAR" = true ]; then
            tar -xzf "$PKG_FILE" -C /tmp
            # 查找解压出的二进制文件 (目录名可能带版本号)
            find /tmp -name "sing-box" -type f -exec cp {} /usr/bin/sing-box \;
            chmod +x /usr/bin/sing-box
            
            # 修复：手动创建 systemd 文件
            info "创建 systemd 服务文件..."
            cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/usr/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
            systemctl daemon-reload
        else
            dpkg -i "$PKG_FILE"
        fi
        success "sing-box 二进制文件就绪"
    fi

    # 3. 配置文件处理 (动态生成密钥)
    mkdir -p /etc/sing-box
    local CONFIG="/etc/sing-box/config.json"
    local USER_UUID PRIVATE_KEY SHORT_ID

    # 尝试从现有配置读取，保持幂等性
    if [ -f "$CONFIG" ]; then
        info "检测到现有配置，保留密钥..."
        USER_UUID=$(grep -oP '"uuid": "\K[^"]+' "$CONFIG" || echo "")
        PRIVATE_KEY=$(grep -oP '"private_key": "\K[^"]+' "$CONFIG" || echo "")
        SHORT_ID=$(grep -oP '"short_id": \[\s*"\K[^"]+' "$CONFIG" || echo "")
    fi

    # 如果读取失败或首次安装，则生成新的
    if [ -z "$PRIVATE_KEY" ]; then
        info "生成新的 Reality 密钥对..."
        local KEY_PAIR
        KEY_PAIR=$(sing-box generate reality-keypair)
        PRIVATE_KEY=$(echo "$KEY_PAIR" | grep "PrivateKey" | awk '{print $2}')
        # 这里实际上还需要 Public Key 给客户端用，但在服务器端配置只需要 Private
        # 为了方便用户，这里可以打印出来
        local PUB_KEY
        PUB_KEY=$(echo "$KEY_PAIR" | grep "PublicKey" | awk '{print $2}')
        echo -e "${YELLOW}>>> 请保存公钥 (Public Key): $PUB_KEY ${RESET}"
    fi

    [ -z "$USER_UUID" ] && USER_UUID=$(sing-box generate uuid)
    [ -z "$SHORT_ID" ] && SHORT_ID=$(openssl rand -hex 8)

    info "写入配置文件 (UUID: $USER_UUID)..."
    cat > "$CONFIG" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true,
    "output": "/var/log/sing-box.log"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": 52368,
      "users": [
        {
          "name": "auto-user",
          "uuid": "$USER_UUID",
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
          "private_key": "$PRIVATE_KEY",
          "short_id": ["$SHORT_ID"]
        }
      }
    }
  ]
}
EOF
    
    systemctl enable --now sing-box
    if systemctl restart sing-box; then
        success "sing-box 服务已启动"
        # 打印客户端参数
        echo ""
        echo -e "${GREEN}====== 客户端配置参数 ======${RESET}"
        echo -e "地址 (Address): $(curl -s https://ipv4.icanhazip.com)"
        echo -e "端口 (Port): 52368"
        echo -e "用户 ID (UUID): ${USER_UUID}"
        echo -e "流控 (Flow): xtls-rprx-vision"
        echo -e "SNI: www.amd.com"
        echo -e "公钥 (Public Key): $(sing-box generate reality-keypair | grep PublicKey | awk '{print $2}' 2>/dev/null || echo '请重新生成或查看日志')"
        echo -e "Short ID: $SHORT_ID"
        echo -e "${GREEN}==========================${RESET}"
        echo ""
    else
        error "sing-box 启动失败，请检查 /var/log/sing-box.log"
    fi
}

#############################################
# nftables 防火墙 (核心逻辑)
#############################################
NFT_MAIN="/etc/nftables.conf"
NFT_D_DIR="/etc/nftables.d"
NFT_FW_FILE="${NFT_D_DIR}/20-fw-rules.conf"

setup_nftables_only() {
    info "配置 nftables 防火墙..."

    # 清理旧防火墙
    safe_run "关闭 ufw" systemctl stop ufw 2>/dev/null || true
    safe_run "禁用 ufw" systemctl disable ufw 2>/dev/null || true
    safe_run "关闭 firewalld" systemctl stop firewalld 2>/dev/null || true
    safe_run "禁用 firewalld" systemctl disable firewalld 2>/dev/null || true
    iptables -F 2>/dev/null || true

    mkdir -p "$NFT_D_DIR"
    
    # 确保规则文件存在
    if [ ! -f "$NFT_FW_FILE" ]; then
        echo "# Custom Rules" > "$NFT_FW_FILE"
    fi

    # 写入主配置 (如果不存在)
    if [ ! -f "$NFT_MAIN" ]; then
        info "初始化 nftables 主配置..."
        cat > "$NFT_MAIN" <<EOF
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        iif lo accept
        ct state established,related accept

        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # SSH Ports (Dynamic)
EOF
        for p in "${SSH_PORTS[@]}"; do
            echo "        tcp dport $p accept" >> "$NFT_MAIN"
        done
        
        cat >> "$NFT_MAIN" <<EOF
        
        # Jump to custom chain
        jump user_input
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }

    chain user_input {
        # Default placeholder
    }
}

include "/etc/nftables.d/*.conf"
EOF
    fi

    systemctl enable --now nftables
    nft -f "$NFT_MAIN"
    success "nftables 已激活"
}

#############################################
# 安装 nft 命令层 (独立文件)
#############################################
install_nft_command_layer() {
    info "安装 nft 命令行工具..."
    local HELPER_SCRIPT="/usr/local/bin/nft-helper.sh"
    
    cat > "$HELPER_SCRIPT" <<'EOF'
#!/bin/bash
# nft 命令层辅助脚本
NFT_FW_FILE="/etc/nftables.d/20-fw-rules.conf"

nft_reload() {
    nft -f /etc/nftables.conf && echo -e "\033[32m规则重载成功\033[0m" || echo -e "\033[31m规则语法错误\033[0m"
}

nft_allow() {
    local port=$1
    local proto=${2:-tcp}
    [ -z "$port" ] && { echo "Usage: nft_allow <port> [tcp/udp]"; return; }
    
    if grep -q "dport $port accept" "$NFT_FW_FILE"; then
        echo "端口 $port 已存在"
    else
        echo "$proto dport $port accept" >> "$NFT_FW_FILE"
        echo "添加规则: 允许 $proto $port"
        nft_reload
    fi
}

nft_deny() {
    local port=$1
    local proto=${2:-tcp}
    [ -z "$port" ] && { echo "Usage: nft_deny <port> [tcp/udp]"; return; }
    
    sed -i "/dport $port accept/d" "$NFT_FW_FILE"
    echo "删除规则: 端口 $port"
    nft_reload
}

nft_list() {
    echo "--- 当前自定义规则 ---"
    cat "$NFT_FW_FILE"
    echo "----------------------"
}
EOF
    chmod +x "$HELPER_SCRIPT"

    # 注入 bashrc
    if ! grep -q "nft-helper.sh" ~/.bashrc; then
        echo "source $HELPER_SCRIPT" >> ~/.bashrc
        success "已将工具注入 ~/.bashrc"
    fi
}

#############################################
# 主流程
#############################################
main() {
    detect_system
    detect_ssh_ports
    enable_bbr
    set_apt_sources
    update_system
    setup_time_module
    setup_or_update_singbox
    setup_nftables_only
    install_nft_command_layer

    success "=============================="
    success " 系统初始化完成！"
    success " 请重新登录 SSH 以加载新命令"
    success "=============================="
}

main
