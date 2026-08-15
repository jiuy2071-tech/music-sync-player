# 阻塞问题

## 当前无阻塞

### 已解决问题

- Windows 构建链曾因包含非 ASCII 字符的工作目录出现乱码。项目现在要求使用不含特殊字符的本地检出路径。
- Gradle wrapper 自动下载的 `gradle-9.1.0-all.zip` 曾出现不完整 zip。已手动下载官方 zip 并放入 D 盘 Gradle 缓存。
