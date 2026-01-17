# ddns-go systemd 服务说明

本文件介绍 ddns-go 的 systemd 服务文件结构、管理方式以及常见问题。

---

## 📄 服务文件路径

```
/etc/systemd/system/ddns-go.service
```

---

## 📦 服务文件内容（由 ddns-go 自动生成）

```ini
[Unit]
Description=ddns-go Service
After=network.target

[Service]
Type=simple
ExecStart=/opt/ddns-go/ddns-go
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

---

## 🔧 常用 systemd 命令

```bash
systemctl status ddns-go
systemctl restart ddns-go
systemctl stop ddns-go
systemctl enable ddns-go
```

---

## ❗ 常见问题

### 服务无法启动？
```bash
journalctl -u ddns-go -n 50 --no-pager
```

### 修改端口后不生效？
```bash
systemctl restart ddns-go
```

### 配置文件在哪里？
```
/opt/ddns-go/.ddns_go_config.yaml
```
