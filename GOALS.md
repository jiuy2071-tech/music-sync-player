# 壹加音乐 V1 状态

## 总目标

完成“Windows 导入音乐和管理歌单 -> 同一 Wi-Fi 扫码同步 -> Android 离线播放”的个人音乐库闭环，并交付可直接启动的 Windows 运行目录和 Android debug APK。

## 阶段状态

- [x] Phase 1：工程初始化、Windows/Android 基础工程、共享包骨架。
- [x] Phase 2：核心数据模型和 SQLite 数据库。
- [x] Phase 3：Windows 音频导入、命名规则和去重。
- [x] Phase 4：Windows 歌单、搜索和本地播放。
- [x] Phase 5：Windows Wi-Fi 同步模式、二维码与下载服务。
- [x] Phase 6：Android 扫码、歌单同步、本地库和离线播放。
- [x] Phase 7：项目内生成音频的自动验收、修复和回归测试。
- [x] Phase 8：Windows/Android 交付产物、播放器体验和品牌整理。

## 当前剩余工作

V1 主流程已经成形，当前暂停扩展新功能，优先完成同步数据安全闭环。

- [x] Android 临时下载、文件大小与 Hash 校验、SQLite 事务和正式文件备份替换。
- [x] 存储空间预检、网络超时重试和会话下载地址安全回归。
- [x] Windows 权威歌单清单与 Android 主端对账。
- [x] Android 引用判断、失效歌单和孤儿文件清理。
- [x] Windows 启动时检测 `ffplay` 与 `ffprobe`，在播放器区域显示能力状态。
- [ ] 真实 Windows + Android 设备的断网、坏包、删除对账和离线播放验收。

## 不变边界

V1 不做云同步、远程在线播放、USB、蓝牙、封面、歌词、推荐算法、评论社交、多用户登录、Android 编辑歌单、Android 导入音乐、Android 同步回电脑或自动匹配全网歌曲信息。
