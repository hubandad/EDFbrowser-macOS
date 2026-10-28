# EDFBrowser Mac

A native EDF/BDF viewer, annotator and signal-analysis application for **Apple Silicon Macs running macOS 14 or later**. Built with SwiftUI and AppKit, with Simplified Chinese and English interfaces and system light/dark appearance.

[简体中文](README-CN.md) · [Download v0.1.2](https://github.com/hubandad/EDFbrowser-macOS/releases/tag/v0.1.2) · [Feature matrix](docs/FEATURES.md)

## Download and install

Download **[EDFBrowserMac-0.1.2-arm64.zip](https://github.com/hubandad/EDFbrowser-macOS/releases/download/v0.1.2/EDFBrowserMac-0.1.2-arm64.zip)**, extract it and open **EDFBrowser Mac.app**. You may move the app to Applications. Choose the built-in demonstration to open synthetic PSG data without a recording file or network connection.

The release also includes a corresponding source archive and `SHA256SUMS.txt`. This is a **development release**, signed locally with an ad-hoc signature. It is not yet signed with an Apple Developer ID or notarized. The arm64 build has been run on macOS 27.0.1; the macOS 14 deployment target still needs testing on physical machines running that version.

## Main workflows

- Open EDF, EDF+, BDF and BDF+ recordings, including mixed sampling rates and discontinuities. Import and export signal/annotation CSV files.
- Select channels beside their waveform labels, search channels, change color/gain/polarity and use reference or average-reference montages.
- Display voltage signals in **μV**, converting source mV and V values correctly. A **100 μV range** spans −50 to +50 μV at default gain. Press **↑** to enlarge a waveform and **↓** to reduce it. Non-voltage channels retain their own units.
- Show or hide the hypnogram; navigate and score sleep epochs, search/edit annotations, and undo/redo changes.
- Use cursors and interval selections; apply filters; analyze Welch PSD, CDSA, aEEG, Z-ratio, event averages, signal/sleep statistics and QRS/RR/HRV.
- Save annotated copies while retaining original digital samples and time gaps. Crop, select channels, resample and export recordings; export waveform PDF/PNG.
- Use header validation/editing, legacy montage import, file combination, video synchronization and BioSemi trigger decoding.

See the [feature matrix and compatibility limits](docs/FEATURES.md), [v0.1.2 changes](docs/RELEASE-0.1.2.md) and [verification record](docs/TESTING.md). The application processes recording data locally. User recordings are not included in this repository or release assets.

## Build from source

Requires Apple Silicon macOS and Apple Command Line Tools or Xcode with Swift 5.10 or later. No Qt, Python runtime, package manager or downloaded package dependency is required for the app.

```bash
git clone https://github.com/hubandad/EDFbrowser-macOS.git
cd EDFbrowser-macOS
git checkout v0.1.2
./scripts/check.sh --large
./scripts/build.sh release
```

The build script targets `arm64-apple-macosx14.0` and writes the application and ZIP to `dist/`. Build caches remain in `.build/`. `EDFCoreCheck` provides executable checks without XCTest; additional XCTest cases are under `Tests/EDFCoreTests` for full Xcode environments. This release has 27 passing core/large-file checks and an actual-window unit-conversion check with equivalent μV/mV/V signals.

## Source and license

The native application is **GPL-3.0-only**; see [LICENSE](LICENSE) and [third-party notices](THIRD_PARTY_NOTICES.md). Original GPL, LGPL and BSD component notices and license texts are retained. Source and build scripts corresponding to the distributed native application are included in this repository and the release source archive.

This is an independently developed macOS application and is not an official release by Teunis van Beelen.

## Legacy Qt package and guides

The original [English Qt build guide](docs/legacy/README-Qt-en.md), [Chinese Qt build guide](docs/legacy/README-Qt-zh-CN.md) and their [Apache-2.0 documentation license](docs/legacy/LICENSE-Apache-2.0.txt) are preserved. The root `EDFbrowser.dmg` is the historical Qt package. Use the Release downloads above for the native SwiftUI/AppKit application. Preserving the historical files does not relicense any third-party software they contain.
