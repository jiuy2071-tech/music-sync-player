# 开发记录

## 2026-07-07：基础工程到同步闭环

- 确认 Windows 检出路径不含特殊字符，避免构建链编码问题。
- 配置 Flutter、Android SDK、Pub 与 Gradle 缓存到 D 盘。
- 完成共享模型、SQLite、Windows 导入/歌单/播放、Windows 同步服务和 Android 歌单同步/离线播放。
- 建立 Git 忽略规则，排除 SDK、缓存、构建产物、APK、EXE、release 和生成测试音频。

## 2026-07-18：验收、交付与体验整理

- 使用项目内生成的 MP3、FLAC、M4A、WAV 验证导入、待整理命名、重复检测和 Windows 播放探测。
- 完成 Windows 同步服务与 Android 同步客户端自动测试；真实扫码、同一 Wi-Fi 和离线播放保留给真机人工确认。
- Windows 播放器更新为居中的上一首/播放/下一首、播放队列、播放模式、快捷键和可拖动进度条。
- Windows 视觉整理为浅色雾灰绿主题，修正导航字重与播放队列提示；应用品牌改为壹加音乐，正式 EXE 为 `YijiaMusic.exe`。
- Android 更新为音乐库、歌单、同步音乐三页导航；同步完成后自动刷新本地库并返回音乐库；增加迷你播放器、完整播放面板、切歌、进度跳转与缓存删除确认。
- Android 应用名称、启动图标和应用内品牌资源改为壹加音乐。
- 最后一次自动验证通过：Windows 和 Android 的 `flutter analyze`、`flutter test` 及对应构建命令。

## 2026-07-26：Android 原子同步安全加固

- 修复同步开始后立即清空本地歌单的问题：歌曲、歌单关系和缓存记录现在放在同一个 SQLite 事务中提交。
- 新文件先下载到 APP 私有临时目录，检查文件大小和 SHA-256 后才替换正式缓存。
- 替换正式文件前保留旧文件备份；数据库或文件操作失败时回滚数据库并恢复旧缓存。
- 增加同步清单安全检查，拒绝危险歌曲 ID、错误 Hash、越界路径和指向其他主机或旧会话的下载地址。
- 新增不完整下载、错误 Hash、成功升级、路径越界和数据库事务回滚测试。
- 同步前通过 Android 系统接口检查 APP 私有目录可用空间，预留 16 MB 安全余量；空间不足时不会开始音频下载或修改本地数据。
- 连接、清单和文件读取增加 20 秒无响应超时；断连、超时、HTTP 408/429/5xx 最多尝试 3 次，权限错误、危险地址和校验错误不会重试。
- 新增空间不足提前停止和服务器临时失败后重试成功的自动测试。
- Android `flutter analyze`、完整 `flutter test` 和 `flutter build apk --debug` 已通过；新的 APK 已更新到本地交付目录。
- Windows `/playlists` 增加权威清单 SHA-256 和每张歌单内容版本；manifest 返回对应版本，Android 会拒绝同步期间发生变化的清单。
- SQLite 增加 `synced_playlists` 快照表，空歌单同步后可正常显示，并兼容补录旧数据库中的已有非空歌单。
- Android 连接后会移除 Windows 已删除的本地歌单；孤儿清理按 `playlist_items` 引用判断，共用歌曲保留，最后引用消失后才删除。
- 孤儿音频先移动到 APP 私有临时回收目录，数据库删除失败会恢复文件。
- Windows 与 Android 的完整 `flutter analyze`、`flutter test` 和对应构建再次通过；两个固定交付位置均已覆盖为本次版本。
- Windows 启动前会检测 `ffplay` 与 `ffprobe`：底部播放器直接显示可播放、只能播放但无法预读时长，或本地播放不可用。
- 缺少 `ffplay` 时播放操作会被明确阻止，但导入、歌单管理和 Wi-Fi 同步不受影响。
- 新增播放能力检测自动测试；Windows `flutter analyze`、完整 `flutter test` 和 `flutter build windows` 再次通过。
- Windows 交付目录已整体镜像更新，并核对 `data\app.so` 与构建目录 Hash 一致，保证固定 EXE 加载本次业务代码。
- 最新 Android APK 已通过 `adb install -r` 保留模拟器现有 APP 数据覆盖安装；启动后进程正常，近期日志没有 Android 或 Flutter 崩溃。
- 模拟器覆盖升级不能替代实体手机覆盖安装后的显示、播放和断网验收，这些继续保留为人工确认。

## 2026-07-27：同步强制中断恢复

- Android 在替换正式缓存前写入 APP 私有恢复清单，并在同一个 SQLite 事务中记录同步是否已经提交。
- APP 启动时会检查 `.sync_staging`：数据库未提交时恢复旧文件或移除未提交的新文件；数据库已提交时保留新文件并清理备份。
- 恢复清单只接受安全的音频文件名和备份文件名，不能借恢复流程访问 APP 音乐目录之外的路径。
- 新增三项强制中断残留测试：恢复旧文件、移除未提交的新文件、保留已提交的新文件。
- 新增真实磁盘旧数据库升级测试，确认原有歌曲、歌单、歌单成员和同步状态不会因新增表而丢失。
- 数据库 10 项测试、Android 14 项测试，以及两处 `flutter analyze` 均通过。
- Android `flutter build apk --debug` 通过，固定交付 APK 已更新；构建文件与交付文件 SHA-256 均为 `F56501F300A51BFBDCEC8D26B47F2FABBC1BD33946DE70A486F5EAB7A2392986`。
- 本轮没有修改 Windows 代码，因此没有无意义地重复 Windows 全量构建。
- 使用正式 `YijiaMusic.exe` 与 `emulator-5554` 完成跨进程联调：手动粘贴完整连接信息成功、显示电脑歌单、整张歌单同步成功。
- 重复同步后 Android 仍只有 1 首歌曲、1 张歌单和 1 个正式音频文件，`.sync_staging` 为空，没有重复记录或半成品。
- 关闭 Windows 同步端口并完全退出 EXE 后，Android 仍取得本地音频焦点，暂停按钮保持可用，播放进度持续前进。
- 在正式 Windows EXE 中创建 0 首歌曲的 `emulator_empty_playlist`，Android 重新连接后显示 2 张电脑歌单，并能把空歌单保存到本地歌单页。
- Windows 删除该临时歌单后，Android 再次连接明确移除 1 张旧歌单和 0 首孤立缓存；原 `新歌单`、`回声_master` 与 37,446,236 字节本地 WAV 均保持不变。
- 把 `回声_master` 同时加入原歌单和 `shared_reference_test` 并同步到 Android；删除临时歌单后，Android 移除旧快照但保留共用歌曲和同一个正式音频文件。
- 把 `member_change_test` 从 1 首改为 0 首后重新同步，Android 正确把该歌单更新为空歌单，同时原歌单仍可见、共用 WAV 未被当作孤儿删除。
- 两项测试结束后删除全部临时歌单并再次对账；Windows 与 Android 均恢复为 1 首歌曲、1 张歌单和 1 个正式音频文件。
- 模拟器已证明正式 EXE 与 APK 的局域网同步和离线播放链路；实体手机相机权限、二维码扫描和真实 Wi-Fi 体感仍需人工验收。

## 2026-08-14：审查修复与回归

- 修复搜索关键词含 `%` 或 `_` 时结果错误：所有 LIKE 查询补充 `ESCAPE '\'` 子句，`%` 与 `_` 现在按字面匹配，并新增转义回归测试。
- 重写 MP3 ID3v2 元数据解析：正确处理 UTF-16（含 BOM）、Latin-1 与 UTF-8 文本编码；支持 v2.4 syncsafe 帧长和 10 字节帧头；跳过扩展头并处理 unsynchronisation；帧 ID 校验允许 A-Z 与 0-9。新增 UTF-16 中文标签、Latin-1、v2.4 大帧、扩展头和文件名回退共 5 项测试。
- Windows 导入时数据库写入失败会删除刚复制的孤儿文件，不再在音乐库目录残留无记录音频。
- Android 播放器增加文件存在检查与错误流订阅：文件缺失或播放中出错会在界面明确提示，而不是无声停留在"正在播放"。
- Android 启动恢复会清理 `.sync_trash` 遗留的回收文件，避免崩溃窗口残留占空间。
- 验证：database 11 项、Windows 15 项、Android 15 项、core 与 sync_protocol 各 3 项测试全部通过；两端 `flutter analyze` 无告警；Windows EXE 与 Android debug APK 已重建并更新到交付目录。

## 2026-08-14：整库删除歌曲与桌面快捷方式

- Windows 端新增"删除歌曲"操作：确认后从全部歌曲、待整理和所有歌单中彻底移除，删除本应用音乐库中的音频副本（不删原始导入文件），并从播放队列清除；待整理列表与全部歌曲列表都有该入口。
- 修复歌单面板与歌曲列表里 ListTile 直接嵌在带背景 DecoratedBox 中导致的 Flutter 调试断言（点击水波纹不可见）。
- 新增删除流程 widget 回归测试；修复测试中双击手势竞技场持有导致的点击不生效问题。
- 在桌面创建 `壹加音乐.lnk` 快捷方式，指向 Windows 交付目录的 `YijiaMusic.exe`。
- 验证：Windows 16 项测试全部通过，`flutter analyze` 无告警；Windows EXE 已重建并更新到交付目录（Android 无代码改动，APK 不变）。

## 当前交付

- Windows 本地构建：`apps/windows_app/build/windows/x64/runner/Release/`
- Android 本地构建：`apps/android_app/build/app/outputs/flutter-apk/app-debug.apk`
- 详细安装、同步和人工确认清单：`RELEASE_NOTES.md` 与 `testing_notes.md`。

## 2026-08-15：开源仓库整理与安全审查

- README 改为面向公开仓库的克隆、运行、构建和 GitHub Releases 说明，移除本机绝对路径交付方式。
- 增加 MIT License、`CONTRIBUTING.md`、`SECURITY.md`、GitHub Actions CI 和 `scripts/verify.ps1`。
- 清理各包模板描述和占位许可证，把 `packages/player` 的 `Calculator` 模板替换为正式播放状态与播放器契约。
- 升级 `sqlite3` 到 `3.5.1`、`mobile_scanner` 到 `7.4.0`，移除已经无实际作用的 `sqlite3_flutter_libs`。
- 修复反斜杠搜索、Android 超量下载、同步 JSON 格式检查、连接请求大小限制和服务端内部错误暴露。
- Windows 整库删除改为先删除应用管理副本、再删除数据库记录；增加受管目录内外文件删除测试。
- 四个共享包与两个应用的 `flutter analyze` 全部通过，共 54 项测试通过。
- Windows 与 Android Debug APK 重新构建成功，固定验收目录已覆盖并核对 Hash；固定 Windows EXE 启动成功。
- 固定 APK 已在现有 Android Studio 模拟器上覆盖安装，原有本地歌曲保留，应用进入音乐库且无启动崩溃；实体手机扫码与离线播放仍保留人工验收。
- 收敛项目知识库：将冗长的阶段计划从 `agent.md` 精简为当前执行规则，增加标准 `AGENTS.md` 入口，并修正数据库、播放器和人工验收说明中的过时描述。
- 根据 GitHub Actions 的 Node.js 运行时提醒，将官方 `actions/checkout` 从 v4 更新到 v6，消除已淘汰 Node.js 20 的 CI 警告。
