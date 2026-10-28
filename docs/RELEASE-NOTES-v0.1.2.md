# EDFBrowser Mac v0.1.2 · Apple Silicon

原生 SwiftUI/AppKit EDF/BDF 阅览、标注与分析应用，适用于 Apple Silicon，最低部署目标 macOS 14，提供简体中文与英文界面。

## 下载

- `EDFBrowserMac-0.1.2-arm64.zip`：应用软件包。解压后打开 EDFBrowser Mac.app，可拖到 Applications。
- `EDFBrowserMac-0.1.2-source.zip`：本版本的对应源码、构建脚本与许可。
- `SHA256SUMS.txt`：上述两个文件的 SHA-256 校验值。

## 功能

支持 EDF/EDF+/BDF/BDF+ 与 CSV 工作流、通道选择与导联、波形和游标、滤波与频谱、睡眠图及分期、标注编辑、事件平均、统计、QRS/RR/HRV、裁剪和重采样导出。详细范围及限制见仓库 `docs/FEATURES.md`。

本版将通道勾选与波形名称合并，支持隐藏睡眠图、上下键缩放，并统一将电压信号换算为 μV。“量程 100 μV”表示默认增益下零线上下各 50 μV；游标和分析显示同步换算，原始校准及记录导出保留源单位。

## 验证和发行状态

27 项核心/大文件检查全部通过；实际窗口验证 μV/mV/V 等幅显示、游标、功率谱与方向键量程。交付包已验证 arm64 架构、0.1.2 版本及 ZIP 解压后的本地代码签名，不包含用户记录。

这是开发版，使用本地 ad-hoc 签名，尚未使用 Apple Developer ID 签名或 Apple 公证。已在 macOS 27.0.1 上编译运行；macOS 14 等其他系统实体机兼容性尚需验收。原生应用以 GPL-3.0-only 发布，保留第三方许可声明。

---

Native SwiftUI/AppKit EDF/BDF viewer and analysis app for Apple Silicon, targeting macOS 14+, with Chinese and English interfaces. This release provides the arm64 application, corresponding source and SHA-256 checksums. Voltage display is normalized to μV, with cursor and PSD units converted consistently. All 27 core/large-file checks pass. Development release: ad-hoc signed, not Developer ID signed or notarized; tested on macOS 27.0.1. See the repository for compatibility limits, build instructions and GPL/third-party license notices.
