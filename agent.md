# agent.md - Codex 项目执行指引

## 项目定位

壹加音乐是一个 Flutter Windows + Android 本地音乐同步播放器。Windows 是唯一主音乐库，负责导入、整理、歌单、播放和同步服务；Android 是只读随身库，只保存、搜索和离线播放已经同步到本机的内容。

V1 的核心闭环是：

```text
Windows 导入音乐 -> 创建歌单 -> 同一 Wi-Fi 扫码同步 -> Android 离线播放
```

## 权威文档

开始工作时按以下顺序读取：

1. `README.md`：公开运行、构建和使用说明。
2. `GOALS.md`、`BLOCKERS.md`、`CHECKPOINT.md`：当前状态与剩余验收。
3. `docs/product_requirements.md`：产品行为和 V1 验收标准。
4. `docs/technical_implementation.md`：当前代码结构与协议。
5. `docs/sync_safety_plan.md`：同步、恢复、删除和主端对账规则。

`DEV_LOG.md` 只记录历史，不用它覆盖当前状态。本文只保留 Agent 必须遵守的规则，不重复需求文档和开发记录。

## V1 硬边界

- 平台只做 Windows 和 Android，技术路线为 Flutter。
- 音频格式只要求 MP3、FLAC、M4A、WAV。
- 同步只在同一 Wi-Fi 内进行，方向只允许 Windows 到 Android。
- 同步粒度是整张歌单；Android 不能编辑歌单、导入音乐或同步回电脑。
- Android 只能展示已经完整同步到本地的歌曲和歌单。
- V1 不做云同步、公网远程播放、USB、蓝牙、封面、歌词、推荐、评论社交、多用户登录、在线识别或全网元数据匹配。

用户没有明确批准时，不得以“流行音乐软件通常都有”为理由扩展以上范围。

## 数据与文件规则

- Windows 导入必须复制音频到应用音乐库，不移动或删除用户选择的源文件。
- 音频二进制文件不写入 SQLite；数据库只保存元数据、关系、状态和本地路径。
- 使用 SHA-256 判断重复文件和同步文件是否一致，不用文件名判断。
- 优先读取可靠元数据；缺失时才使用保守的文件名规则。
- 数字、长编码、乱码或无意义名称必须进入待整理区，并使用 `未命名音频 001/002/...`。
- 删除歌单不得删除主音乐库歌曲。
- Windows “删除歌曲”只能删除应用管理的副本，不得删除最初导入的源文件。
- Android 删除本地缓存不得修改 Windows 主库或歌单。

## 同步安全规则

- Windows 同步模式必须由用户手动开启；每次生成新的临时会话 ID 和六位连接码，关闭后立即失效。
- 二维码只携带当前局域网地址、端口、会话 ID 和连接码，不放长期密钥。
- Android 的手动备用方式是粘贴完整连接信息，不能只靠六位连接码推测电脑地址。
- Windows 只允许按数据库登记的歌曲 ID 下载，不接受客户端任意文件路径。
- Android 必须限制下载地址属于当前主机、端口、会话和连接码。
- 新文件只有在大小和 SHA-256 都正确后才能替换正式缓存。
- 歌曲、歌单关系、缓存状态和已同步快照必须在同一个 SQLite 事务中提交。
- 同步失败或被强制中断时，原有可播放快照必须保留并可恢复。
- Windows 删除歌单后，Android 下次连接应移除旧快照；共用歌曲仍被其他歌单引用时不得删除文件。
- 网络超时和重试必须有限；格式、权限、路径或校验错误不得盲目重试。

## 工程边界

```text
apps/windows_app/       Windows 主音乐库、播放和同步服务
apps/android_app/       Android 同步客户端和离线播放器
packages/core/          共享歌曲、歌单和错误模型
packages/database/      SQLite、仓库、搜索和已同步快照
packages/player/        共享播放状态与播放器契约
packages/sync_protocol/ 二维码和连接协议模型
docs/                   产品、技术和同步安全说明
scripts/                本地验证脚本
```

Windows 当前使用 `ffplay`/`ffprobe` 适配层，Android 使用 `audioplayers`。`packages/player` 提供共享契约，但两个应用暂未强制接入该接口。

## 工作纪律

1. 开始前检查 `git status`，保留用户已有改动，不覆盖、不回滚无关文件。
2. 只在项目目录和用户明确给出的路径内工作，不扫描桌面、下载、文档、聊天软件、浏览器或系统音乐库。
3. 不下载版权音乐，不提交真实音乐、数据库、连接信息、密钥、SDK、缓存或构建产物。
4. 新依赖必须常见、维护状态良好且确有必要；安装 FFmpeg、SDK 或其他大型工具前先征得用户同意。
5. 修改数据、同步、删除或恢复逻辑时，必须添加能复现风险的测试。
6. 每个有意义的改动都要形成独立 Git 提交；提交前显式检查暂存内容，不能用构建产物凑提交。
7. Windows 或 Android 用户可见代码改变后，要重建对应平台并更新本地验收产物；文档改动不需要重复全量构建。
8. 不重复运行 `flutter doctor -v` 或无关平台的完整构建来确认已经验证过的环境。
9. 构建、模拟器或组件测试不能冒充实体设备验收；未真机验证的事项要明确写出。
10. 遇到需求冲突、破坏性迁移、删除权威文件或改变 V1 边界时，先停下并让用户拍板。

## 验证要求

按修改范围运行最小但足够的检查：

```powershell
# 全仓分析与测试
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1

# Windows 用户可见或平台代码改动
cd apps/windows_app
flutter analyze
flutter test
flutter build windows

# Android 用户可见或平台代码改动
cd apps/android_app
flutter analyze
flutter test
flutter build apk --debug
```

涉及真实文件选择器、相机二维码、实体 Wi-Fi、覆盖安装或断网播放时，自动测试通过后仍要保留人工验收项。

## Git 与交付

- 源码仓库不得跟踪 `build/`、`release/`、`.dart_tool/`、`.gradle/`、APK、EXE、ZIP、SDK、缓存、数据库或 `manual_test_audio/`。
- 公开二进制文件通过 GitHub Releases 分发，不放进源码分支。
- Windows 交付必须保留完整 Release 运行目录，不能只交付 `YijiaMusic.exe`。
- Android 当前交付为 Debug APK，不能描述成应用商店正式签名包。
- 本地固定验收目录可以更新，但其内容保持 Git 忽略。

## 面向用户的说明

用普通中文说明：这次做了什么、用户在哪里看到变化、怎样验证、还有什么没确认。少用术语；必须使用术语时顺手解释它的作用。

如果缺少环境或依赖，要写清楚缺什么、用来做什么、如何检查、会影响哪一步。不能把未执行的构建、真机扫码或离线播放写成已经通过。
