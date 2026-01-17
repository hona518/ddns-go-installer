# ddns-go Installer

一个为 **ddns-go** 打造的一键安装器，支持自动安装、更新、卸载、端口管理、防火墙处理、网络诊断等高级功能。

本项目旨在让 ddns-go 的部署体验变得 **更简单、更可靠、更智能**。

---

## ✨ 功能亮点

- **一键安装**：自动检测架构、下载最新版本、安装 systemd 服务  
- **交互式端口选择**：安装时可自定义端口  
- **智能端口占用检测**：区分 ddns-go 自占端口与其他程序占用  
- **自动防火墙处理**：支持 UFW / firewalld / iptables  
- **自动更新**：一键更新到最新版本，可选择修改端口  
- **一键卸载**：可选删除配置文件，并提示防火墙清理  
- **网络诊断**：自动检测公网 IP、NAT、ASN、国家等信息  
- **彩色输出 + 日志系统**：所有操作均记录到 `/var/log/ddns-go-installer.log`  
- **完全兼容 systemd**：自动安装、修复、重启服务  

---

## 🚀 一键安装

适用于 Debian / Ubuntu / CentOS / AlmaLinux / RockyLinux 等 systemd 系统。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hona518/ddns-go-installer/main/install.sh)
```

安装过程中你将看到：

- 交互式端口选择  
- 自动检测架构  
- 自动下载最新 ddns-go  
- 自动安装 systemd 服务  
- 自动防火墙处理  
- 网络诊断报告  
- 最终访问地址展示  

安装完成后访问：

```
http://<你的公网IP>:<端口>
```

---

## 🔄 一键更新

更新 ddns-go 到最新版本，并可选择是否修改端口。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hona518/ddns-go-installer/main/scripts/update.sh)
```

更新脚本会自动：

- 检测当前端口  
- 询问是否修改端口  
- 智能检测端口占用  
- 下载最新版本  
- 修复 systemd 服务  
- 显示访问地址  

---

## 🗑 一键卸载

支持删除程序、systemd 服务、配置文件，并提示防火墙清理。

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hona518/ddns-go-installer/main/scripts/uninstall.sh)
```

卸载脚本会自动：

- 停止并禁用 systemd 服务  
- 删除 ddns-go 程序文件  
- 可选删除配置文件  
- 提示清理 UFW / firewalld / iptables 规则  

---

## 🛠 systemctl 常用命令（四件套）

安装器会自动为 ddns-go 创建 systemd 服务，你可以使用以下命令管理它：

### 查看状态
```bash
systemctl status ddns-go
```

### 重启服务
```bash
systemctl restart ddns-go
```

### 停止服务
```bash
systemctl stop ddns-go
```

### 设置开机自启（安装脚本已自动启用）
```bash
systemctl enable ddns-go
```

服务文件路径：

```
/etc/systemd/system/ddns-go.service
```

查看实时日志：

```bash
journalctl -u ddns-go -f
```

---

## 🔥 防火墙说明

脚本会自动检测并处理以下防火墙：

| 防火墙 | 自动放行端口 | 自动清理提示 |
|--------|--------------|--------------|
| UFW | ✔ | ✔ |
| firewalld | ✔ | ✔ |
| iptables | 检测提示 | ✔ |

如果你使用云服务器（如阿里云、腾讯云、AWS），请确保 **安全组** 也放行对应端口。

---

## 📂 目录结构

```
ddns-go-installer/
├── install.sh
├── scripts/
│   ├── update.sh
│   └── uninstall.sh
└── README.md
```

---

## 🧩 系统要求

- Linux（必须支持 systemd）  
- curl / tar / systemctl / ss  
- root 权限  

---

## ❓ 常见问题（FAQ）

### 1. 安装后访问不了？

可能原因：

- 防火墙未放行端口  
- 云服务器安全组未放行  
- NAT / CGNAT 环境导致公网不可达  

脚本会自动检测并提示解决方案。

---

### 2. 如何修改端口？

执行更新脚本：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hona518/ddns-go-installer/main/scripts/update.sh)
```

---

### 3. 配置文件在哪里？

```
/opt/ddns-go/.ddns_go_config.yaml
```

---

### 4. 日志在哪里？

```
/var/log/ddns-go-installer.log
```

---

## 📜 许可证

本项目使用 MIT License。

欢迎提交 PR、Issue，一起让 ddns-go 的部署体验更丝滑。

---

## ❤️ 致谢

感谢 ddns-go 作者提供优秀的开源项目。  
本安装器旨在让更多用户轻松使用 ddns-go。
