import SwiftUI
import AppKit
import EDFCore

@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var pendingURLs: [URL] = []
    weak var model: AppModel? {
        didSet { if let model, !pendingURLs.isEmpty { let urls = pendingURLs; pendingURLs = []; model.open(urls:urls) } }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let model { model.open(urls:urls) } else { pendingURLs += urls }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.recordings.contains(where: \.dirty) == true else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = L.t("Unsaved annotation changes","有尚未保存的标注修改")
        alert.informativeText = L.t("Save a recording copy or a session before quitting to preserve your work.","如需保留修改，请先保存记录副本或会话。")
        alert.addButton(withTitle:L.t("Cancel","取消")); alert.addButton(withTitle:L.t("Quit Without Saving","不保存并退出"))
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

@main struct EDFBrowserMacApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) var delegate
    @StateObject var model = AppModel()
    var body: some Scene {
        WindowGroup("EDFBrowser Mac") {
            MainView().environmentObject(model).onAppear {
                delegate.model = model
                if CommandLine.arguments.contains("--demo"), model.recordings.isEmpty { model.demo() }
                if let i = CommandLine.arguments.firstIndex(of:"--open"), CommandLine.arguments.count > i+1 { model.open(urls:[URL(fileURLWithPath:CommandLine.arguments[i+1])]) }
            }
        }
        .defaultSize(width:1440,height:900)
        .commands { AppCommands(model:model) }
        Settings { PreferencesView() }
    }
}

struct AppCommands: Commands {
    @ObservedObject var model: AppModel
    var body: some Commands {
        CommandGroup(replacing:.newItem) {
            Button(L.t("Open Recording…","打开记录…"),action:model.openPanel).keyboardShortcut("o")
            Button(L.t("Open Session…","打开会话…"),action:model.loadSession).keyboardShortcut("o",modifiers:[.command,.shift])
            Button(L.t("Import CSV…","导入 CSV…")) { model.tool = .csvImport }
            Button(L.t("Open Growing Recording…","打开增长中的记录…")) {
                let panel = NSOpenPanel(); if panel.runModal() == .OK { model.open(urls:panel.urls,monitor:true) }
            }
            Divider()
            Button(L.t("Open Synthetic Demo","打开合成演示"),action:model.demo)
        }
        CommandGroup(replacing:.saveItem) {
            Button(L.t("Save Annotated Copy…","保存带标注副本…"),action:model.saveAnnotations).keyboardShortcut("s").disabled(model.active == nil)
            Button(L.t("Save Session…","保存会话…"),action:model.saveSession).keyboardShortcut("s",modifiers:[.command,.shift])
            Button(L.t("Export / Crop / Resample…","导出 / 裁剪 / 重采样…")) { model.tool = .export }.keyboardShortcut("e").disabled(model.active == nil)
            Button(L.t("Export Waveforms as PDF…","导出波形 PDF…")) { NotificationCenter.default.post(name:.exportWavePDF,object:nil) }.keyboardShortcut("p")
            Button(L.t("Export Waveforms as PNG…","导出波形 PNG…")) { NotificationCenter.default.post(name:.exportWavePNG,object:nil) }
        }
        CommandGroup(after:.saveItem) {
            Button(L.t("Close Recording","关闭记录"),action:model.closeActive).keyboardShortcut("w",modifiers:[.command,.shift]).disabled(model.active == nil)
        }
        CommandGroup(after:.sidebar) {
            Toggle(L.t("Show Hypnogram","显示睡眠图"),isOn:$model.showHypnogram)
        }
        CommandMenu(L.t("Signals","信号")) {
            Button(L.t("Montage / Derivations…","导联 / 差分…")) { model.tool = .montage }
            Button(L.t("Load Montage…","载入导联…"),action:model.loadMontage)
            Button(L.t("Save Montage…","保存导联…"),action:model.saveMontage)
            Divider()
            Button(L.t("Show All","显示全部")) { for i in model.traces.indices { model.traces[i].visible = true } }
            Button(L.t("Invert Selected Trace","反转所选波形")) { if let id = model.focusedTrace?.id { model.updateTrace(id) { $0.inverted.toggle() } } }
        }
        CommandMenu(L.t("Analysis","分析")) {
            Button(L.t("Filters…","滤波器…")) { model.tool = .filters }.keyboardShortcut("f",modifiers:[.command,.shift])
            Button(L.t("Power Spectrum…","功率谱…")) { model.tool = .spectrum }.keyboardShortcut("k")
            Button("CDSA…") { model.tool = .cdsa }
            Button("aEEG / CFM…") { model.tool = .aeeg }
            Button("Z-EEG / Z-ratio…") { model.tool = .zeeg }
            Button(L.t("Event Averaging…","事件叠加平均…")) { model.tool = .average }
            Button(L.t("Signal Statistics…","信号统计…")) { model.tool = .statistics }
            Button(L.t("QRS / RR / HRV…","QRS / RR / HRV…")) { model.tool = .qrs }
        }
        CommandMenu(L.t("Navigate","导航")) {
            Button(L.t("Previous Page","上一页")) { model.navigate(-model.page) }.keyboardShortcut(.leftArrow,modifiers:[])
            Button(L.t("Next Page","下一页")) { model.navigate(model.page) }.keyboardShortcut(.rightArrow,modifiers:[])
            Button(L.t("Beginning","开头")) { model.jump(0) }.keyboardShortcut(.leftArrow,modifiers:.command)
            Button(L.t("End","结尾")) { model.jump(model.maximumTime-model.page) }.keyboardShortcut(.rightArrow,modifiers:.command)
            Divider()
            Button(L.t("Zoom In","放大")) { model.zoom(0.5) }.keyboardShortcut("+")
            Button(L.t("Zoom Out","缩小")) { model.zoom(2) }.keyboardShortcut("-")
            Button(L.t("Increase Waveform Amplitude (↑)","增大波形幅度（↑）")) { model.stepAmplitude(largerWaveform:true) }.disabled(model.active == nil)
            Button(L.t("Decrease Waveform Amplitude (↓)","减小波形幅度（↓）")) { model.stepAmplitude(largerWaveform:false) }.disabled(model.active == nil)
            Button(L.t("Play / Pause","播放 / 暂停"),action:model.togglePlayback).keyboardShortcut(.space,modifiers:[])
        }
        CommandMenu(L.t("Tools","工具")) {
            Button(L.t("Header Editor…","文件头编辑器…")) { model.tool = .header }
            Button(L.t("Compatibility Check…","兼容性检查…")) { model.tool = .validation }
            Button(L.t("Combine Recordings…","合并记录…")) { model.tool = .combine }
            Button(L.t("Synchronized Video…","同步视频…")) { model.tool = .video }
            Button(L.t("Local Remote Control…","本地远程控制…")) { model.tool = .remote }
            Button(L.t("Decode BioSemi Status Triggers","解析 BioSemi Status 触发器")) { model.decodeTriggers() }
        }
        CommandGroup(replacing:.help) { Button(L.t("EDFBrowser Mac Help","EDFBrowser Mac 帮助")) { model.tool = .help } }
    }
}

struct PreferencesView: View {
    @AppStorage("language") var language = "system"
    @AppStorage("appearance") var appearance = "system"
    @AppStorage("grid") var grid = true
    @AppStorage("pointsPerCM") var pointsPerCM = 37.8
    var body: some View {
        Form {
            Picker(L.t("Language (reopen window)","语言（重开窗口生效）"),selection:$language) {
                Text("System / 跟随系统").tag("system"); Text("简体中文").tag("zh"); Text("English").tag("en")
            }
            Picker(L.t("Appearance","外观"),selection:$appearance) {
                Text(L.t("System","跟随系统")).tag("system"); Text(L.t("Light","浅色")).tag("light"); Text(L.t("Dark","深色")).tag("dark")
            }
            Toggle(L.t("Waveform Grid","波形网格"),isOn:$grid)
            TextField(L.t("Screen points per cm","每厘米屏幕点数"),value:$pointsPerCM,format:.number)
            Text(L.t("For physical mm/s and µV/cm calibration, measure a 10 cm ruler on this display and adjust this value.","若使用 mm/s 或 µV/cm 标尺，请在当前屏幕上测量 10 cm 标尺后调整此值。"))
                .font(.caption).foregroundStyle(.secondary)
            Text("EDFBrowser Mac · GPLv3\nSignal processing components © Teunis van Beelen, Jim Peters and contributors.").font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).frame(width:500,height:350)
    }
}

extension Notification.Name {
    static let exportWavePDF = Notification.Name("EDFExportWavePDF")
    static let exportWavePNG = Notification.Name("EDFExportWavePNG")
}
