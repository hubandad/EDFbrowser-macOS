# EDFBrowser Mac v0.1.4 · Icon and workflow improvements

- 全新 macOS 图标：平滑 EEG 波形与抽象字母 E，深蓝底板、珍珠白与青绿层次，支持完整 Dock/Retina 尺寸。
- 完整会话恢复：自动量程、游标、选区、搜索、检查器显示和分期偏好；兼容旧会话。替换会话前保护未保存的修改。
- 播放末尾自动停止，再次播放从头开始；按实际经过时间推进。
- 快速导航取消过时渲染；读取和长滤波处理中响应取消。
- 游标幅值异步读取实际样本，遵循当前导联、滤波和 μV 换算。

35 项自动检查全部通过；已实际验证保存/恢复、旧文件兼容、未保存修改保护、播放末尾和游标读数，并在原生“关于”窗口验证新图标。

## 下载

- `EDFBrowserMac-0.1.4-arm64.zip`：Apple Silicon 应用。
- `EDFBrowserMac-0.1.4-source.zip`：对应源码、图标原始素材、提示词与构建脚本。
- `SHA256SUMS.txt`：上述两个 ZIP 的 SHA-256 校验值。

macOS 14+ 部署目标，中英双语；本轮实际运行于 macOS 27.2。开发版，ad-hoc 签名，尚未使用 Developer ID 签名或 Apple 公证。GPL-3.0-only，保留第三方许可。用户记录、会话和测试截图未加入发行包。

---

Redesigned native icon, complete workspace-session restoration, safe session replacement, end-of-recording playback handling, cooperative cancellation of obsolete rendering and sample-based cursor measurements. All 35 automated checks pass, with actual-window workflow and icon verification. Includes the arm64 app, corresponding source, icon artwork and SHA-256 checksums. macOS 14+ deployment target; ad-hoc signed development release tested on macOS 27.2.
