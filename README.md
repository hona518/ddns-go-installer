ddns-go Installer
一个用于在 Linux 服务器上自动安装最新版本 ddns-go 的一键脚本。

本脚本适用于 Debian / Ubuntu 系列系统，具备以下特性：

自动检测 CPU 架构（x86_64 / arm64）

自动获取 ddns-go 最新版本（GitHub API）

自动下载并解压到 /opt/ddns-go

自动安装 systemd 服务

自动启动 ddns-go

支持用户自定义端口

自动显示 IPv4 + IPv6 访问地址

自动检测 NAT（如 Oracle、部分国内云）

自动检测 UFW 防火墙是否放行端口

🚀 一键安装
将以下命令复制到终端即可：

代码
bash <(curl -fsSL https://raw.githubusercontent.com/hona518/ddns-go-installer/main/install.sh)
🌐 安装完成后访问 Web UI
脚本会自动显示你的 IPv4 / IPv6 地址，例如：

代码
IPv4: http://203.0.113.45:51004
IPv6: http://[2408:1234:abcd::1]:51004
首次访问需要进行初始化配置，保存后会自动生成：

代码
/opt/ddns-go/.ddns_go_config.yaml
🔧 systemd 管理命令
代码
systemctl status ddns-go
systemctl restart ddns-go
systemctl stop ddns-go
systemctl enable ddns-go
📂 安装目录结构
代码
/opt/ddns-go/
├── ddns-go
├── .ddns_go_config.yaml（首次保存设置后生成）
└── systemd 服务文件（自动安装）
📜 脚本执行流程
检查 wget / curl 是否存在

自动检测 CPU 架构

调用 GitHub API 获取最新版本号

下载对应架构的 tar.gz

解压到 /opt/ddns-go

调用 ddns-go 内置的 systemd 安装命令

显示 IPv4 / IPv6、NAT 状态、防火墙状态

📝 许可证
MIT License

⭐ Star 支持
如果这个项目对你有帮助，欢迎 Star 支持一下！
