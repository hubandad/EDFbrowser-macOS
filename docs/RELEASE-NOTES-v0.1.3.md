# EDFBrowser Mac v0.1.3 · Apple Silicon

修复播放波形时左下角“已打开记录”文字闪烁、左右跳动的问题。

每次波形渲染的进度指示器曾反复插入、移除并推动文字布局。现在指示器有固定宽度的位置，播放期间持续显示，暂停后隐藏时文字位置也保持稳定。

已用用户当前打开的同一份官方合成 EDF 数据及两通道配置实测连续播放、暂停和翻页；不同状态截图中的状态文字逐像素一致，波形正常更新。

## 下载

- `EDFBrowserMac-0.1.3-arm64.zip`：Apple Silicon 应用，解压后用于替换旧版应用。
- `EDFBrowserMac-0.1.3-source.zip`：本版本对应源码和构建脚本。
- `SHA256SUMS.txt`：两个 ZIP 文件的 SHA-256 校验值。

最低部署目标 macOS 14；简体中文/英文。开发版，使用本地 ad-hoc 签名，尚未使用 Apple Developer ID 签名或公证。GPL-3.0-only，保留第三方许可。用户记录、会话和测试截图不包含在发布附件中。

---

Fix the lower-left “Recording opened” status text flickering during playback. A permanently reserved activity-indicator slot prevents layout shifts, and the indicator stays visible throughout playback. Verified with the same open EDF and two-channel configuration: status-text pixels match across paused, playing and paged views while waveforms update normally. Includes the arm64 app, corresponding source and SHA-256 checksums. macOS 14+ deployment target; ad-hoc signed development release, not notarized.
