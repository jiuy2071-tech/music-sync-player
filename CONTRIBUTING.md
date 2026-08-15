# 参与贡献

感谢你关注壹加音乐。这个项目优先保证本地音乐不会丢失、同步失败可以恢复，以及 Windows 与 Android 的核心流程容易验证。

## 开始之前

1. 先阅读 [README.md](README.md) 和 [docs/product_requirements.md](docs/product_requirements.md)。
2. 功能改动必须保持 V1 边界，不要把局域网同步扩展成云服务或公网远程播放。
3. 不要提交真实音乐、个人数据库、连接码、密钥、SDK、缓存或构建产物。
4. 修复数据、同步或删除逻辑时，请同时添加能够复现问题的测试。

## 本地检查

在仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1
```

涉及平台行为时还应运行对应构建：

```powershell
cd apps/windows_app
flutter build windows

cd ../android_app
flutter build apk --debug
```

相机、真实 Wi-Fi、系统文件选择器和实体设备离线播放无法只靠组件测试证明。提交说明中请明确区分“自动测试通过”和“已在真实设备验证”。

## 提交建议

- 一次提交只解决一个清晰问题。
- 提交信息使用简短的 Conventional Commit 风格，例如 `fix: reject oversized sync downloads`。
- Pull Request 说明应包含问题、修改内容、验证命令和仍需人工确认的部分。
- UI 改动请附 Windows 或 Android 的实际截图。

## 报告问题

普通错误和功能建议可以使用 GitHub Issues。涉及会暴露本地文件、会话信息或可造成数据破坏的问题，请不要先公开利用细节，改用 [SECURITY.md](SECURITY.md) 中的私密报告方式。
