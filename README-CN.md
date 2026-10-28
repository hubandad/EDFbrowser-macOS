# EDFBrowser Mac

[English](README.md) · [下载 v0.1.3](https://github.com/hubandad/EDFbrowser-macOS/releases/tag/v0.1.3)

Apple Silicon 专用的原生 EDF/BDF 阅览、标注与分析应用。SwiftUI + AppKit 界面，最低部署目标 macOS 14，支持简体中文与英文，跟随系统浅色/深色外观。

这是可运行的 **0.1.3 开发版**。核心工作流已经实现并验证；与 Windows 版的具体对应关系和限制见 [功能对照](docs/FEATURES.md)。原项目许可、来源与校验值见 [第三方说明](THIRD_PARTY_NOTICES.md)。

0.1.3 修复了播放波形时左下角状态文字闪烁、左右跳动的问题，见 [更新与验证说明](docs/RELEASE-0.1.3.md)。

## 运行

从 [v0.1.3 Release](https://github.com/hubandad/EDFbrowser-macOS/releases/tag/v0.1.3) 下载 `EDFBrowserMac-0.1.3-arm64.zip`，解压后双击 **EDFBrowser Mac.app**。可将应用拖到 Applications。应用内点击“查看演示”，即可打开 12 通道合成 PSG 记录，无需联网或准备数据。

应用使用本地 ad-hoc 签名，尚未使用 Apple Developer ID 签名或 Apple 公证；对外正式发行前需要补上这两项。已在当前 Apple Silicon / macOS 27.0.1 机器上编译运行，最低系统 14 的实体机兼容性还需实际验收。

## 常用操作

- `⌘O` 打开 EDF/EDF+/BDF/BDF+，支持多文件和拖放；按开始日期时间同步，也可切换到相对时间。
- 通道选择与波形名称合并，直接在名称旁勾选；隐藏通道折叠成紧凑行，可重新勾选恢复。右键名称可上移、下移或反转。通道检查器可改名称、颜色、增益和极性。
- `↑` 放大波形（量程减小），`↓` 缩小波形（量程增大），采用 1–2–5 步进；在文本框编辑时保留方向键原有行为。
- 电压波形统一显示为 **μV**，自动将源文件的 mV ×1000、V ×1,000,000。工具栏明确标示“量程 100 μV”：默认增益下表示零线上下各 50 μV。每条波形名称下显示实际量程，游标、事件平均和频谱同步换算；非电压通道保留自己的单位。源文件校准及记录导出仍保持原单位。
- 睡眠图可用右上角关闭按钮或工具栏“睡眠图”按钮隐藏/恢复，显示状态会记忆，也可随会话保存。
- 记录文件通过上方文件名菜单切换；通道搜索位于记录栏。导联面板支持参考相减及 EEG 平均参考。
- 在波形上拖动放大；`Shift` 拖动选区；单击设置游标 A，`Option` 单击设置 B；`Esc` 清除。左右键或 Page Up/Down 翻页。
- 睡眠分期快捷键 `1=W, 2=N1, 3=N2, 4=N3, 5=REM, 6=未评分`；支持 20/30 秒 epoch 和自动前进。标注支持撤销/重做、搜索、编辑和 CSV 导入导出。
- `⌘S` 保存带标注副本，保留原始数字样本和时间间隙；`⇧⌘S` 保存会话；`⌘E` 裁剪、选通道、重采样及导出 EDF+/BDF+/CSV。
- 分析菜单提供滤波、功率谱、CDSA、aEEG、Z-ratio、事件平均、信号/睡眠统计以及 QRS/RR/HRV。
- 文件菜单支持导出当前波形 PDF/PNG；工具菜单提供文件头编辑、校验、合并、视频同步、BioSemi 触发器和本地 TCP 控制。

界面语言在 Settings 中选择 System、简体中文或 English，重开窗口生效。设置中的屏幕点数/cm 用于导入 `.mtg` 后的物理尺度校准。

## 构建

不需要 Qt、Python 运行时、第三方包管理器或联网依赖。构建使用 Apple 的 Swift 和 Command Line Tools；完整 Xcode 也可使用。

```bash
./scripts/check.sh
./scripts/build.sh release
```

构建脚本将缓存保存在项目 `.build` 中，输出 arm64 应用和 ZIP 到 `dist`。为避开当前 Command Line Tools 中的 SwiftUI `@State` 宏插件缺失，项目使用显式的 property-wrapper 类型别名；不依赖该新宏。

`EDFCoreCheck` 是不依赖 XCTest 的可执行校验器。`Tests/EDFCoreTests` 另外保留了 XCTest 用例，需完整 Xcode/XCTest 环境。具体复现方式见 [测试说明](docs/TESTING.md)。

## License

GPL-3.0-only，允许按许可条款商业使用和发行。发行修改版二进制时，应按 GPL 提供相应源代码、构建脚本和许可信息。第三方组件的原始许可和声明均予以保留。本项目未向任何外部服务上传记录数据。

---

Native Apple Silicon EDF/BDF viewer, annotator and analysis workspace for macOS 14+. Built with SwiftUI/AppKit and reusable GPL/BSD/LGPL signal-processing components. The app runs fully locally. See the feature matrix for implemented capabilities, compatibility boundaries and the verification status of this development release.

## 历史 Qt 版本

仓库原有的 [英文编译指南](docs/legacy/README-Qt-en.md)、[中文编译指南](docs/legacy/README-Qt-zh-CN.md) 和对应的 [Apache-2.0 文档许可](docs/legacy/LICENSE-Apache-2.0.txt) 已保留。历史 `EDFbrowser.dmg` 可在仓库历史中查看；本次原生 SwiftUI/AppKit 版本请从 Release 下载。历史文件的保留不表示对其中第三方软件重新授权。
