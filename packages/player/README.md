# music_player

这是预留的播放器抽象位置，当前未被 Windows 或 Android 运行时使用。

当前 V1 使用平台适配：Windows 通过 `ffplay`，Android 通过 `audioplayers`。不要把本包中的模板 `Calculator` 当作播放器 API；将来真正抽取共享播放器契约时，应先替换该模板并补充单元测试。
