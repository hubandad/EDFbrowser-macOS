# 图标设计

以 EEG 的连续波形构成抽象字母 E：深蓝圆角底板，珍珠白与青绿色信号线，采用克制的立体层次，保持 Dock 小尺寸辨识度。

原始素材为 `Resources/IconArtwork.png`，由内置 `image_gen` 工具为本项目生成，使用透明背景。生产资源为 `Resources/AppIcon.png`（1024 px）及包含 16–1024 px 尺寸的 `Resources/AppIcon.icns`。

以下命令从已随源码提供的原始素材重建图标，不需要联网或再次生成图像：

```bash
swift scripts/make-icon.swift Resources
```

## 生成提示词

```text
Use case: logo-brand
Asset type: production macOS application icon for EDFBrowser Mac, an Apple Silicon EEG and sleep recording viewer.
Primary request: Create a completely new, distinctive, beautifully crafted native macOS app icon. One icon only, centered and front-on, not a mockup sheet.
Subject: An elegant geometric E-like monogram built from three parallel smooth EEG signal ribbons. Three horizontal strokes clearly suggest an E at small size; the middle ribbon gently rises and falls in a single fluid EEG oscillation. Balanced, confident scientific instrument identity. No generic ECG heartbeat zigzag.
Style: premium macOS icon with restrained sculptural depth, precision rounded edges and subtle layered ceramic/glass material, polished professional design, not a busy illustration.
Composition: 1024 x 1024 square image. The rounded-square icon tile occupies approximately x=92..932, y=92..932; the design is centered with a clean transparent margin. Dominant simple silhouette readable at 32 pixels. Do not add surrounding scenery, lettering, small details, graph paper, grid, circles, brains or medical crosses.
Palette: deep midnight ink-blue tile, luminous pearl-white and cool turquoise signal monogram, tiny restrained cobalt highlights; refined soft top-left studio lighting. Crisp edges, no excessive bloom.
Background: actual transparent outside the rounded-square tile. Subtle contained contact shadow only. No perspective tilt, no pedestal, no border caption, no watermark.
Text: none. The E is an abstract mark, not rendered text.
```

