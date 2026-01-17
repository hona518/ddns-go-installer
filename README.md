# ddns-go Installer

<p align="center">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" />
  <img src="https://img.shields.io/badge/Platform-Linux-blue.svg" />
  <img src="https://img.shields.io/badge/Installer-ddns--go-orange.svg" />
  <img src="https://img.shields.io/github/stars/hona518/ddns-go-installer?style=social" />
</p>

## 📚 目录

- [项目简介](#ddns-go-installer)
- [一键安装](#-一键安装)
- [安装完成后访问 Web UI](#-安装完成后访问-web-ui)
- [systemd 管理命令](#-systemd-管理命令每条都带注释适合新手)
- [安装目录结构](#-安装目录结构)
- [脚本执行流程](#-脚本执行流程)
- [示例截图](#-示例截图)
- [更新日志](#-更新日志)
- [许可证](#-许可证)

---

一个用于在 Linux 服务器上自动安装最新版本 ddns-go 的一键脚本。

本脚本适用于 Debian / Ubuntu 系列系统，具备以下特性：

- 自动检测 CPU 架构（x86_64 / arm64）
- 自动获取 ddns-go 最新版本（GitHub API）
- 自动下载并解压到 `/opt/ddns-go`
- 自动安装 systemd 服务
- 自动启动 ddns-go
- 支持用户自定义端口
- 自动显示 IPv4 + IPv6 访问地址
- 自动检测 NAT（如 Oracle、部分国内云）
- 自动检测 UFW 防火墙是否放行端口

---

## 🚀 一键安装

将以下命令复制到终端即可：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hona518/ddns-go-installer/main/install.sh)
```

---

## 🌐 安装完成后访问 Web UI

脚本会自动显示你的 IPv4 / IPv6 地址，例如：

IPv4: http://203.0.113.45:51004  
IPv6: http://[2408:1234:abcd::1]:51004

首次访问需要进行初始化配置，保存后会自动生成：

```bash
/opt/ddns-go/.ddns_go_config.yaml
```

---

## 🔧 systemd 管理命令（每条都带注释，适合新手）

查看 ddns-go 的运行状态（最常用）：
```bash
systemctl status ddns-go
```

重启 ddns-go（修改配置后使用）：
```bash
systemctl restart ddns-go
```

停止 ddns-go（不想运行时使用）：
```bash
systemctl stop ddns-go
```

设置开机自启（推荐开启）：
```bash
systemctl enable ddns-go
```

---

## 📂 安装目录结构

```bash
/opt/ddns-go/
├── ddns-go
├── .ddns_go_config.yaml（首次保存设置后生成）
└── systemd 服务文件（自动安装）
```

---

## 📜 脚本执行流程

1. 检查 wget / curl 是否存在  
2. 自动检测 CPU 架构  
3. 调用 GitHub API 获取最新版本号  
4. 下载对应架构的 tar.gz  
5. 解压到 `/opt/ddns-go`  
6. 调用 ddns-go 内置的 systemd 安装命令  
7. 显示 IPv4 / IPv6、NAT 状态、防火墙状态  

---

## 🖼 示例截图

> 以下为示例截图占位符，后续可替换为真实图片。

![ddns-go 示例截图](https://via.placeholder.com/800x400?text=ddns-go+Installer+Screenshot)

---

## 📝 更新日志

### v1.0.0 - 2026-01-17
- 初始版本发布
- 支持自动安装 ddns-go 最新版本
- 支持 systemd 自动安装与启动
- 支持 IPv4 / IPv6 自动检测
- 支持 NAT 检测与防火墙检测
- 支持用户自定义端口

---

## 📝 许可证

MIT License

Copyright (c) 2026

---

