# 🤝 Contributing to ddns-go Installer

欢迎你为本项目贡献代码、文档或建议！

---

## 🧱 项目结构

```
.
├── install.sh
├── scripts/
│   ├── update.sh
│   └── uninstall.sh
├── examples/
│   └── systemd-service.md
├── FAQ.md
└── README.md
```

---

## 🛠 开发环境要求

- Linux 系统（推荐 Debian / Ubuntu）
- bash 4.0+
- curl / wget
- systemd

---

## 🧪 如何测试脚本

```bash
./install.sh --debug
./scripts/update.sh --debug
./scripts/uninstall.sh --debug
```

---

## 📝 提交规范

- 使用清晰的 commit message  
- 每次修改请确保脚本可执行  
- 新增功能请附带说明文档  
- PR 请保持简洁、可读、可维护  

---

## 📬 联系方式

欢迎通过 Issue 或 PR 参与讨论。
