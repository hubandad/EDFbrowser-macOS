import SwiftUI
import AppKit
import EDFCore

let traceColors: [Color] = [.blue,.teal,.purple,.indigo,.cyan,.mint,.orange,.pink]

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.undoManager) var undoManager
    @AppStorage("appearance") var appearance = "system"
    var body: some View {
        HStack(spacing:0) {
            workspace.frame(maxWidth:.infinity,maxHeight:.infinity)
            if model.inspector && !model.recordings.isEmpty { Divider(); InspectorView().frame(width:295) }
        }
        .frame(minWidth:1080,minHeight:700)
        .toolbar { toolbar }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .sheet(item:$model.tool) { tool in ToolSheet(tool:tool).environmentObject(model) }
        .alert(L.t("Operation could not be completed","操作未能完成"),isPresented:Binding(get:{model.message != nil},set:{ if !$0 { model.message = nil } })) {
            Button(L.t("OK","好")) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .onAppear { model.undoManager = undoManager; model.installScaleKeyboardShortcuts() }
        .onDrop(of:[.fileURL],isTargeted:nil) { providers in
            for provider in providers { _ = provider.loadObject(ofClass:URL.self) { url,_ in if let url { Task { @MainActor in model.open(urls:[url]) } } } }; return true
        }
    }
    @ViewBuilder var workspace: some View {
        if model.recordings.isEmpty {
            VStack(spacing:22) {
                Image(systemName:"waveform.path.ecg.rectangle").font(.system(size:70,weight:.ultraLight)).foregroundStyle(.tint)
                VStack(spacing:8) { Text("EDFBrowser Mac").font(.largeTitle.weight(.semibold)); Text(L.t("A native workspace for physiological signals","原生生理信号分析工作台")).font(.title3).foregroundStyle(.secondary) }
                HStack { Button(L.t("Open EDF / BDF…","打开 EDF / BDF…"),action:model.openPanel).buttonStyle(.borderedProminent).keyboardShortcut("o"); Button(L.t("Explore Demo","查看演示"),action:model.demo).buttonStyle(.bordered) }
                Text(L.t("EDF · EDF+ · BDF · BDF+  |  Drop a recording here","EDF · EDF+ · BDF · BDF+  |  拖入记录文件即可打开")).font(.caption).foregroundStyle(.secondary)
                if model.busy { ProgressView().controlSize(.small) }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(.background)
        } else {
            VStack(spacing:0) {
                recordingBar
                Divider()
                WaveformWorkspace()
                if model.showHypnogram {
                    Divider()
                    HStack(alignment:.top,spacing:4) {
                        HypnogramView().frame(height:76)
                        Button { model.showHypnogram = false } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).help(L.t("Hide Hypnogram","隐藏睡眠图")).accessibilityLabel(L.t("Hide Hypnogram","隐藏睡眠图"))
                    }.padding(.horizontal,16).padding(.vertical,7)
                }
                Divider()
                navigationBar
                Divider()
                statusBar
            }
        }
    }
    var recordingBar: some View {
        HStack {
            VStack(alignment:.leading,spacing:3) {
                Menu {
                    ForEach(model.recordings) { entry in
                        Button { model.activeFileID = entry.id } label: { if entry.id == model.active?.id { Label(entry.file.url.lastPathComponent,systemImage:"checkmark") } else { Text(entry.file.url.lastPathComponent) } }
                    }
                    Divider(); Button(L.t("Open Recording…","打开记录…"),action:model.openPanel)
                } label: { Text(model.active?.file.url.lastPathComponent ?? "").font(.headline).lineLimit(1) }
                    .menuStyle(.borderlessButton).fixedSize(horizontal:false,vertical:true)
                Text("\(model.active?.file.header.format ?? "")  ·  \(model.active?.file.signalChannels.count ?? 0) \(L.t("signals","通道"))  ·  \(EDFDate.clock(model.active?.file.duration ?? 0))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing:5) { Image(systemName:"magnifyingglass").foregroundStyle(.secondary); TextField(L.t("Find signal","搜索通道"),text:$model.channelSearch).textFieldStyle(.plain) }
                .padding(.horizontal,8).padding(.vertical,5).background(.quaternary.opacity(0.35),in:RoundedRectangle(cornerRadius:6)).frame(width:160)
            Menu {
                Button(L.t("Show All Signals","显示全部通道")) { for i in model.traces.indices { model.traces[i].visible = true } }
                Button(L.t("Hide All Signals","隐藏全部通道")) { for i in model.traces.indices { model.traces[i].visible = false } }
            } label: { Text("\(model.traces.filter(\.visible).count)/\(model.traces.count)").monospacedDigit() }.help(L.t("Signal Visibility","通道显示"))
            if model.isMonitoring { Label(L.t("Monitoring","监测中"),systemImage:"dot.radiowaves.left.and.right").font(.caption).foregroundStyle(.green); Button(L.t("Stop","停止"),action:model.stopMonitoring) }
            if model.active?.dirty == true { Label(L.t("Unsaved annotations","标注未保存"),systemImage:"circle.fill").font(.caption).foregroundStyle(.orange) }
            Menu { Button(L.t("Header & Metadata","文件头与元数据")) { model.tool = .header }; Button(L.t("Compatibility Check","兼容性检查")) { model.tool = .validation }; Button(L.t("Close Recording","关闭记录"),action:model.closeActive) } label: { Image(systemName:"ellipsis.circle") }.menuStyle(.borderlessButton).frame(width:25)
        }.padding(.horizontal,18).padding(.vertical,12).background(.bar)
    }
    var navigationBar: some View {
        VStack(spacing:8) {
            HStack(spacing:12) {
                Button { model.jump(0) } label: { Image(systemName:"backward.end") }
                Button { model.navigate(-model.page) } label: { Image(systemName:"chevron.left") }
                Button(action:model.togglePlayback) { Image(systemName:model.isPlaying ? "pause.fill" : "play.fill") }
                Button { model.navigate(model.page) } label: { Image(systemName:"chevron.right") }
                Button { model.jump(model.maximumTime-model.page) } label: { Image(systemName:"forward.end") }
                Text(EDFDate.clock(model.position)).font(.system(.body,design:.monospaced)).textSelection(.enabled)
                Slider(value:Binding(get:{ model.position },set:{ model.jump($0) }),in:0...max(0.001,model.maximumTime-model.page))
                Text(EDFDate.clock(model.maximumTime)).font(.system(.caption,design:.monospaced)).foregroundStyle(.secondary)
            }.buttonStyle(.borderless)
            HStack(spacing:6) {
                Text(L.t("Sleep stage","睡眠分期")).font(.caption).foregroundStyle(.secondary)
                ForEach(Array(["W","N1","N2","N3","R","?"] .enumerated()),id:\.offset) { i,stage in
                    Button { model.score(stage) } label: { Text("\(i+1)  \(stage)").font(.system(.caption,design:.monospaced).weight(.medium)).frame(minWidth:38) }
                        .keyboardShortcut(KeyEquivalent(Character(String(i+1))),modifiers:[])
                }
                Spacer()
                Picker(L.t("Epoch","分期长度"),selection:$model.epoch) { Text("20 s").tag(20.0); Text("30 s").tag(30.0) }.frame(width:130).controlSize(.small)
                Toggle(L.t("Advance","自动前进"),isOn:$model.scrollWithScoring).toggleStyle(.checkbox).font(.caption)
            }
        }.padding(12).background(.bar)
    }
    var statusBar: some View {
        HStack {
            if model.busy || model.rendering { ProgressView().controlSize(.mini) }
            Text(model.status.isEmpty ? L.t("↑/↓ amplitude · Drag to zoom · Shift-drag to select","↑/↓ 调整幅度 · 拖动放大 · Shift 拖动选区") : model.status).lineLimit(1)
            Spacer()
            if let a = model.cursorA { Text("A \(EDFDate.clock(a))") }
            if let b = model.cursorB { Text("B \(EDFDate.clock(b))") }
            if let a = model.cursorA, let b = model.cursorB { Text(String(format:"Δt %.4f s",abs(a-b))) }
        }.font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary).padding(.horizontal,12).frame(height:25)
    }
    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement:.navigation) {
            Button(action:model.openPanel) { Label(L.t("Open","打开"),systemImage:"folder") }.help(L.t("Open recording (⌘O)","打开记录（⌘O）"))
            Button { model.tool = .montage } label: { Label(L.t("Montage","导联"),systemImage:"point.3.connected.trianglepath.dotted") }
        }
        ToolbarItemGroup(placement:.principal) {
            Picker(L.t("Time scale","时基"),selection:$model.page) {
                ForEach([1.0,2,5,10,15,20,30,60,120,300,600,1800,3600],id:\.self) { seconds in Text(seconds < 60 ? "\(Int(seconds)) s" : "\(Int(seconds/60)) min").tag(seconds) }
                if ![1.0,2,5,10,15,20,30,60,120,300,600,1800,3600].contains(model.page) { Text(String(format:"%.2f s",model.page)).tag(model.page) }
            }.frame(width:115).help(L.t("Seconds per page","每页秒数"))
            Picker(L.t("Amplitude Range","幅度量程"),selection:Binding(get:{model.autoScale ? -1 : model.amplitude},set:{ if $0 < 0 { model.autoScale = true } else { model.setAmplitudeSpan($0) } })) {
                Text(L.t("Range: Auto","量程：自适应")).tag(-1.0)
                ForEach(AppModel.amplitudeSteps,id:\.self) { Text("\(L.t("Range","量程")) \(Int($0)) \(model.amplitudeUnit)").tag($0) }
                if !AppModel.amplitudeSteps.contains(model.amplitude) { Text(String(format:"%@ %.3g %@",L.t("Range","量程"),model.amplitude,model.amplitudeUnit)).tag(model.amplitude) }
            }.frame(width:180).help(L.t("Voltage traces display in μV. At default gain, a 100 μV range spans −50 to +50 μV around zero. Smaller ranges enlarge the waveform. ↑/↓ adjusts the range; individual gain or calibrated montages can override it.","电压信号统一以 μV 显示。默认增益下，量程 100 μV 表示零线上下各 50 μV；量程越小，波形越大。↑/↓ 调节量程；单独增益或已校准的导联可能覆盖基础量程。"))
            Button { model.autoScale.toggle() } label: { Label(L.t("Fit","适应"),systemImage:"arrow.up.and.down.righttriangle.up.righttriangle.down") }.help(L.t("Fit each trace independently","各通道独立适应高度"))
        }
        ToolbarItemGroup(placement:.primaryAction) {
            Button { model.tool = .filters } label: { Label(L.t("Filters","滤波"),systemImage:"slider.horizontal.3") }
            Button { model.tool = .spectrum } label: { Label(L.t("Spectrum","频谱"),systemImage:"chart.bar.xaxis") }
            Button { model.tool = .export } label: { Label(L.t("Export","导出"),systemImage:"square.and.arrow.up") }
            Button { model.showHypnogram.toggle() } label: { Label(L.t("Hypnogram","睡眠图"),systemImage:"chart.xyaxis.line") }
                .help(model.showHypnogram ? L.t("Hide Hypnogram","隐藏睡眠图") : L.t("Show Hypnogram","显示睡眠图"))
                .accessibilityLabel(model.showHypnogram ? L.t("Hide Hypnogram","隐藏睡眠图") : L.t("Show Hypnogram","显示睡眠图"))
            Button { model.inspector.toggle() } label: { Label(L.t("Inspector","检查器"),systemImage:"sidebar.right") }
        }
    }
}

