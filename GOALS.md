# 壹加音乐 V1 目标状态

## 总目标

完成 Windows + Android 双端个人音乐同步播放器 V1 可用闭环：

1. Windows 端导入本地音频并复制进 APP 音乐库。
2. Windows 端管理歌曲、待整理音频和歌单。
3. Windows 端本地播放音乐。
4. Windows 端开启同一 Wi-Fi 下的扫码同步模式。
5. Android 端扫码连接 Windows 端。
6. Android 端按整个歌单同步音乐到本地。
7. Android 端离线播放已同步歌曲。
8. 最终交付 Windows 可运行目录和 Android APK。

## 阶段状态

- [x] Phase 1：工程初始化、Windows/Android 基础工程、共享包骨架。
- [x] Phase 2：核心数据模型和 SQLite 数据库。
- [ ] Phase 3：Windows 端音频导入。
- [ ] Phase 4：Windows 端歌单和播放。
- [ ] Phase 5：Windows 端同步模式。
- [ ] Phase 6：Android 端同步和本地播放。
- [ ] Phase 7：验收、修复和 release 交付。

## 范围边界

V1 不做云同步、远程在线播放、USB 同步、蓝牙同步、封面、歌词、推荐算法、评论社交、多用户登录、手机端编辑歌单、手机端导入音乐、手机端同步回电脑、自动匹配全网歌曲信息。
