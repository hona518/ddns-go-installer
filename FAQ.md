# ❓ FAQ（常见问题）

---

## 1. 如何修改 ddns-go 的端口？

编辑配置文件：

```
/opt/ddns-go/.ddns_go_config.yaml
```

然后重启服务：

```bash
systemctl restart ddns-go
```

---

## 2. 如何查看 ddns-go 的日志？

```bash
journalctl -u ddns-go -n 50 --no-pager
```

---

## 3. 如何确认 NAT 状态？

install.sh 会自动检测：

- 是否私网 IP  
- 是否运营商 CGNAT  
- 是否 IPv6-only / NAT64  
- 出口 ASN / 国家 / 城市  

---

## 4. 防火墙是否需要放行端口？

```bash
ufw allow 9876
```

---

## 5. 如何更新 ddns-go？

```bash
./scripts/update.sh
```

---

## 6. 如何卸载 ddns-go？

```bash
./scripts/uninstall.sh
```

---

## 7. 配置文件在哪里？

```
/opt/ddns-go/.ddns_go_config.yaml
```

---

## 8. systemd 服务文件在哪里？

```
/etc/systemd/system/ddns-go.service
```
