# music_player

壹加音乐的共享播放契约包，定义播放状态快照和平台播放器接口。

V1 的 Windows 与 Android 仍分别使用 `ffplay` 和 `audioplayers`，暂未强制接入该接口；这里保留的是后续统一播放器行为时可复用的正式契约，不再包含 Flutter 模板代码。

```powershell
flutter analyze
flutter test
```
