import SwiftUI
import AppKit
import EDFCore

struct ToolSheet: View {
    let tool: Tool
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing:0) {
            HStack { Text(title).font(.title2.weight(.semibold)); Spacer(); Button { dismiss() } label: { Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).keyboardShortcut(.cancelAction) }.padding(20)
            Divider()
            Group {
                switch tool {
                case .filters: FilterToolView()
                case .export: ExportToolView()
                case .header: HeaderToolView()
                case .montage: MontageToolView()
                case .validation: ValidationToolView()
                case .csvImport: CSVImportView()
                case .video: VideoToolView()
                case .combine: CombineToolView()
                case .remote: RemoteToolView()
                case .help: HelpToolView()
                default: AnalysisToolView(kind:tool)
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(width:[Tool.cdsa,.spectrum,.aeeg,.average,.qrs].contains(tool) ? 960 : 720,height:700)
    }
    var title: String {
        switch tool {
        case .filters: return L.t("Signal Filters","信号滤波器")
        case .export: return L.t("Export · Crop · Resample","导出 · 裁剪 · 重采样")
        case .header: return L.t("Header & Metadata","文件头与元数据")
        case .montage: return L.t("Montage & Derivations","导联与差分")
        case .validation: return L.t("Compatibility Check","兼容性检查")
        case .csvImport: return L.t("Import CSV Signals","导入 CSV 信号")
        case .spectrum: return L.t("Power Spectrum","功率谱")
        case .cdsa: return L.t("Color Density Spectral Array","压缩谱阵列 CDSA")
        case .aeeg: return "Amplitude-integrated EEG / CFM"
        case .zeeg: return "Z-EEG / Z-ratio"
        case .average: return L.t("Event-triggered Averaging","事件触发叠加平均")
        case .qrs: return "QRS · RR · HRV"
        case .statistics: return L.t("Signal Statistics","信号统计")
        case .video: return L.t("Synchronized Video","同步视频")
        case .combine: return L.t("Combine Recordings","合并记录")
        case .remote: return L.t("Local Remote Control","本地远程控制")
        case .help: return L.t("Using EDFBrowser Mac","使用 EDFBrowser Mac")
        }
    }
}

struct FilterToolView: View {
    @EnvironmentObject var model: AppModel
    @ViewState var settings = FilterSettings()
    @ViewState var scope = "selected"
    @ViewState var firText = ""
    @ViewState var firLow = 0.5
    @ViewState var firHigh = 30.0
    @ViewState var taps = 129
    @ViewState var firMethod = "sinc"
    @ViewState var transition = 2.0
    @ViewState var designing = false
    @ViewState var error: String?
    var body: some View {
        Form {
            Section {
                Picker(L.t("Apply to","应用到"),selection:$scope) { Text(L.t("Selected signal","所选通道")).tag("selected"); Text(L.t("EEG signals","EEG 通道")).tag("eeg"); Text(L.t("Visible signals","所有可见通道")).tag("visible") }
                HStack {
                    Button(L.t("EEG preset","EEG 预设")) { settings = FilterSettings(); settings.highPass = 0.3; settings.lowPass = 70; settings.notch = 50 }
                    Button(L.t("Sleep preset","睡眠预设")) { settings = FilterSettings(); settings.highPass = 0.3; settings.lowPass = 35; settings.notch = 50 }
                    Button(L.t("Clear All","全部清除")) { settings = FilterSettings(); firText = "" }
                }
            }
            Section(L.t("IIR FILTERS · 0 DISABLES A STAGE","IIR 滤波器 · 0 表示关闭该级")) {
                Picker(L.t("Family","类型"),selection:$settings.family) { ForEach(["Butterworth","Chebyshev","Bessel"],id:\.self) { Text($0) } }
                Stepper(L.t("Order: ","阶数：")+"\(settings.order)",value:$settings.order,in:1...8)
                HStack { TextField("High-pass (Hz)",value:$settings.highPass,format:.number); TextField("Low-pass (Hz)",value:$settings.lowPass,format:.number) }
                HStack { TextField("Notch (Hz)",value:$settings.notch,format:.number); TextField("Q",value:$settings.notchQ,format:.number) }
                if settings.family == "Chebyshev" { TextField("Ripple (dB)",value:$settings.ripple,format:.number) }
                TextField(L.t("Moving-average samples","移动平均样本数"),value:$settings.movingAverage,format:.number)
                Toggle(L.t("High-pass moving average","高通移动平均"),isOn:Binding(get:{settings.movingAverageHighPass ?? false},set:{settings.movingAverageHighPass = $0}))
                Picker(L.t("EEG powerline subtraction","EEG 工频减法滤波"),selection:$settings.powerline) { Text(L.t("Off","关闭")).tag(0); Text("50 Hz").tag(50); Text("60 Hz").tag(60) }
            }
            Section("FIR") {
                Picker(L.t("Designer","设计方法"),selection:$firMethod) { Text("Windowed sinc").tag("sinc"); Text("Parks–McClellan").tag("remez") }
                HStack { TextField("Low (Hz)",value:$firLow,format:.number); TextField("High (Hz)",value:$firHigh,format:.number); TextField("Taps",value:$taps,format:.number)
                    Button(L.t("Design","设计")) { design() }
                }
                if firMethod == "remez" { TextField(L.t("Transition width (Hz)","过渡带宽度（Hz）"),value:$transition,format:.number); Text("Passband ripple 1 dB · Stopband 60 dB").font(.caption) }
                if designing { ProgressView().controlSize(.small) }
                TextField(L.t("Coefficients (comma separated)","系数（逗号分隔）"),text:$firText,axis:.vertical).lineLimit(2...3).font(.system(.caption,design:.monospaced))
                Text(L.t("Hamming-windowed sinc designer; custom coefficients are also accepted. FIR is causal and introduces a group delay.","使用 Hamming 窗 sinc 设计，也可输入自定义系数。FIR 为因果滤波，会引入群延迟。")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L.t("SPIKE SUPPRESSION · ≥4000 Hz","尖峰抑制 · ≥4000 Hz")) {
                TextField(L.t("Velocity threshold (0 = off)","斜率阈值（0 = 关闭）"),value:Binding(get:{settings.spikeVelocity ?? 0},set:{settings.spikeVelocity = $0}),format:.number)
                TextField(L.t("Holdoff (ms)","抑制间隔（毫秒）"),value:Binding(get:{settings.spikeHoldoff ?? 100},set:{settings.spikeHoldoff = $0}),format:.number)
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Button(L.t("Apply Filters","应用滤波器"),action:apply).buttonStyle(.borderedProminent)
        }.formStyle(.grouped).onAppear { if let t = model.focusedTrace { settings = t.filters; firText = t.filters.firTaps.map(String.init(describing:)).joined(separator:",") } }
    }
    func design() {
        guard let trace = model.focusedTrace, let f = model.recordings.first(where:{$0.id == trace.sourceID})?.file else { return }
        let low = firLow, high = firHigh, rate = f.header.signals[trace.channel].sampleRate(f.header.recordDuration), count = taps, width = transition, method = firMethod
        designing = true
        Task {
            do { let values = try await Task.detached { try method == "remez" ? DSP.parksMcClellan(low:low,high:high,rate:rate,transition:width) : DSP.fir(low:low,high:high,rate:rate,taps:count) }.value; firText = values.map(String.init(describing:)).joined(separator:","); error = nil }
            catch { self.error = error.localizedDescription }; designing = false
        }
    }
    func apply() {
        do {
            if !firText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                let items = firText.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
                let values = items.compactMap { Double($0) }
                guard values.count == items.count, values.count <= 4095, values.allSatisfy(\.isFinite) else { throw EDFError.invalid("Invalid FIR coefficients (max 4095)") }; settings.firTaps = values
            } else { settings.firTaps = [] }
            let targets = model.traces.filter { t in scope == "visible" ? t.visible : scope == "eeg" ? t.label.uppercased().contains("EEG") : t.id == model.focusedTrace?.id }
            for t in targets {
                guard let f = model.recordings.first(where:{$0.id == t.sourceID})?.file else { continue }
                let rate = f.header.signals[t.channel].sampleRate(f.header.recordDuration)
                _ = try DSP.filter(SampleSeries(times:(0..<32).map { Double($0)/rate },values:[Double](repeating:0,count:32),rate:rate),settings:settings)
            }
            for t in targets { model.updateTrace(t.id) { $0.filters = settings } }
            error = nil; model.status = L.t("Filters applied","已应用滤波器"); model.tool = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct ExportToolView: View {
    @EnvironmentObject var model: AppModel
    @ViewState var format = "EDF+"
    @ViewState var start = 0.0
    @ViewState var duration = 30.0
    @ViewState var rate = 0
    @ViewState var filtered = false
    @ViewState var onlyVisible = true
    @ViewState var physicalLimit = 0.0
    var body: some View {
        Form {
            Picker(L.t("Format","格式"),selection:$format) { Text("EDF+ (16-bit)").tag("EDF+"); Text("BDF+ (24-bit)").tag("BDF+"); Text("CSV (time, signal, value, unit)").tag("CSV") }
            HStack { TextField(L.t("Start (s)","起点（秒）"),value:$start,format:.number); TextField(L.t("Duration (s)","时长（秒）"),value:$duration,format:.number) }
            HStack { Button(L.t("Current Selection / Page","当前选区 / 页面"),action:useSelection); Button(L.t("Whole Recording","整个记录")) { start = model.active?.file.recordOnsets.first ?? 0; duration = (model.active?.file.duration ?? 0)-start } }
            Toggle(L.t("Visible signals only","仅导出可见通道"),isOn:$onlyVisible)
            if format != "CSV" {
                TextField(L.t("Resample to Hz (0 = original)","重采样至 Hz（0 = 原采样率）"),value:$rate,format:.number)
                Toggle(L.t("Apply montage and filters","应用导联与滤波"),isOn:$filtered)
                TextField(L.t("Physical amplitude limit ± (0 = auto)","物理幅度上限 ±（0 = 自动）"),value:$physicalLimit,format:.number)
                Text(L.t("Resampling uses an anti-aliasing windowed-sinc kernel. Partial final records are padded and annotated. For lossless annotation editing, use Save Annotated Copy.","重采样使用带抗混叠处理的窗函数 sinc 核。最后不足一个记录的样本将补齐并注明。无损编辑标注请使用“保存带标注副本”。")).font(.caption).foregroundStyle(.secondary)
            } else { Text(L.t("CSV exports original physical samples and retains individual sample timestamps/rates.","CSV 导出原始物理值，保留各通道的时间戳与采样率。")).font(.caption).foregroundStyle(.secondary) }
            Button(L.t("Export…","导出…"),action:export).buttonStyle(.borderedProminent).disabled(model.busy || model.active == nil)
            if model.busy { ProgressView() }
        }.formStyle(.grouped).onAppear(perform:useSelection)
    }
    func useSelection() { let offset = model.offset(for:model.active?.id ?? UUID()); start = max(0,model.selectedInterval.lowerBound-offset); duration = min(model.active?.file.duration ?? 0,model.selectedInterval.upperBound-offset)-start }
    func export() {
        guard let entry = model.active else { return }
        guard start.isFinite, duration.isFinite, start >= 0, duration > 0, start+duration <= entry.file.duration+1e-5, rate >= 0, rate <= 1_000_000, physicalLimit.isFinite, physicalLimit >= 0 else { model.message = L.t("Invalid range, amplitude or sample rate","无效的时间、幅度范围或采样率"); return }
        let ext = format == "CSV" ? "csv" : format == "BDF+" ? "bdf" : "edf"
        let panel = NSSavePanel(); panel.nameFieldStringValue = entry.file.url.deletingPathExtension().lastPathComponent+"_export."+ext
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let chosen = model.traces.filter { $0.sourceID == entry.id && (!onlyVisible || $0.visible) }
        let file = entry.file, begin = start, length = duration, target = rate == 0 ? nil : rate, useFilters = filtered, bdf = format == "BDF+", csv = format == "CSV", events = entry.annotations, limit = physicalLimit > 0 ? physicalLimit : nil
        let outputTraces = useFilters ? chosen : chosen.map { t -> Trace in var out = Trace(sourceID:t.sourceID,channel:t.channel,label:file.header.signals[t.channel].label); out.filters = FilterSettings(); return out }
        model.perform {
            if csv { try CSV.export(file,channels:Array(Set(chosen.map(\.channel))).sorted(),range:begin..<(begin+length),to:url) }
            else { try ExportEngine.export(file:file,traces:outputTraces,annotations:events,start:begin,duration:length,targetRate:target,bdf:bdf,filtered:useFilters,physicalLimit:limit,to:url) }
        }
    }
}

struct HeaderToolView: View {
    @EnvironmentObject var model: AppModel
    @ViewState var selectedChannel = 0
    @ViewState var signal: EDFSignal?
    var body: some View {
        Form {
            if let index = model.activeIndex {
                let entry = model.recordings[index], h = entry.file.header
                Section(L.t("IDENTIFICATION", "记录标识")) {
                    TextField(L.t("Patient (ASCII, 80 bytes)","患者标识（ASCII，80 字节）"),text:Binding(get:{model.recordings[index].patient},set:{model.recordings[index].patient = $0; model.recordings[index].dirty = true}))
                    TextField(L.t("Recording (ASCII, 80 bytes)","记录标识（ASCII，80 字节）"),text:Binding(get:{model.recordings[index].recording},set:{model.recordings[index].recording = $0; model.recordings[index].dirty = true}))
                    DatePicker(L.t("Recorded local date/time", "记录中的本地日期时间"),selection:Binding(get:{model.recordings[index].startDate ?? h.startDate},set:{model.recordings[index].startDate = $0; model.recordings[index].dirty = true})).environment(\.timeZone,TimeZone(secondsFromGMT:0)!)
                    Button(L.t("De-identify Patient","去除患者身份信息")) { model.recordings[index].patient = "X X X X"; model.recordings[index].recording = "Startdate X X X X"; model.recordings[index].dirty = true }
                    Text("\(h.format) · \(h.recordCount) records · \(h.recordDuration) s/record").font(.caption).foregroundStyle(.secondary)
                }
                Section(L.t("SIGNAL HEADER", "通道文件头")) {
                    Picker(L.t("Signal", "通道"),selection:$selectedChannel) { ForEach(entry.file.signalChannels) { Text($0.label).tag($0.id) } }
                    if signal != nil {
                        TextField(L.t("Label", "名称"),text:signalBinding(\.label))
                        TextField(L.t("Physical unit", "物理单位"),text:signalBinding(\.unit))
                        HStack { TextField(L.t("Physical minimum", "物理最小值"),value:signalBinding(\.physicalMin),format:.number); TextField(L.t("Physical maximum", "物理最大值"),value:signalBinding(\.physicalMax),format:.number) }
                        HStack { TextField(L.t("Digital minimum", "数字最小值"),value:signalBinding(\.digitalMin),format:.number); TextField(L.t("Digital maximum", "数字最大值"),value:signalBinding(\.digitalMax),format:.number) }
                        TextField(L.t("Transducer", "传感器"),text:signalBinding(\.transducer))
                        TextField(L.t("Prefilter description", "预滤波描述"),text:signalBinding(\.prefilter))
                        Button(L.t("Stage Signal Header Changes", "暂存通道文件头修改")) { if let signal { model.recordings[index].signalEdits[selectedChannel] = signal; model.recordings[index].dirty = true } }
                    }
                    Text(L.t("Header edits are saved to a new copy. Changing calibration reinterprets digital samples; it does not filter or resample them. Reopen the saved copy to view the new calibration.","文件头修改将保存到新副本。更改校准会重新解释数字样本，不会进行滤波或重采样。请重新打开保存的副本查看新校准结果。")).font(.caption).foregroundStyle(.secondary)
                }
                Button(L.t("Save Edited Copy…","保存编辑后的副本…"),action:model.saveAnnotations).buttonStyle(.borderedProminent)
            } else { Text(L.t("Open a recording first","请先打开记录")) }
        }.formStyle(.grouped).onAppear { selectedChannel = model.active?.file.signalChannels.first?.id ?? 0; loadSignal() }
            .onChange(of:selectedChannel) { _,_ in loadSignal() }
    }
    func loadSignal() { guard let entry = model.active else { return }; signal = entry.signalEdits[selectedChannel] ?? entry.file.signalChannels.first { $0.id == selectedChannel } }
    func signalBinding<T>(_ key:WritableKeyPath<EDFSignal,T>) -> Binding<T> { Binding(get:{signal![keyPath:key]},set:{signal![keyPath:key] = $0}) }
}

struct MontageToolView: View {
    @EnvironmentObject var model: AppModel
    @ViewState var positive = 0
    @ViewState var negative = -1
    @ViewState var alias = ""
    var body: some View {
        Form {
            if let entry = model.active {
                Picker(L.t("Signal (+)","信号（+）"),selection:$positive) { ForEach(entry.file.signalChannels) { Text($0.label).tag($0.id) } }
                Picker(L.t("Reference (−)","参考（−）"),selection:$negative) { Text(L.t("None","无")).tag(-1); Text(L.t("Common average (EEG)","EEG 平均参考")).tag(-2); ForEach(entry.file.signalChannels) { Text($0.label).tag($0.id) } }
                TextField(L.t("Alias (optional)","别名（可选）"),text:$alias)
                Button(L.t("Add Derivation","添加导联")) {
                    guard let s = entry.file.header.signals.first(where:{$0.id == positive}), !s.isAnnotation else { return }
                    let label = alias.isEmpty ? s.label + (negative >= 0 ? " − "+entry.file.header.signals[negative].label : negative == -2 ? " − AVG" : "") : alias
                    var t = Trace(sourceID:entry.id,channel:positive,reference:negative >= 0 ? negative : nil,label:label,colorIndex:model.traces.count%8); t.averageReference = negative == -2
                    model.traces.append(t); model.selectedTrace = t.id; model.revision += 1
                }.buttonStyle(.borderedProminent)
                Divider()
                HStack { Button(L.t("Save Montage…","保存导联…"),action:model.saveMontage); Button(L.t("Load Montage…","载入导联…"),action:model.loadMontage) }
                Text(L.t("Montages include trace order, derivations, colors, inversion, gain and filters. Right-click waveform labels to reorder. Saved montages use the native .edfmontage format.","导联保存通道顺序、差分、颜色、反转、增益和滤波器。右键波形名称可调整顺序。导联文件使用原生 .edfmontage 格式。")).font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).onAppear { positive = model.focusedTrace?.channel ?? 0 }
    }
}

struct ValidationToolView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                if let f = model.active?.file {
                    Label(L.t("Header and data records parsed successfully","文件头与数据记录解析成功"),systemImage:"checkmark.seal.fill").font(.title3).foregroundStyle(.green)
                    Text("\(f.header.format) · \(f.header.recordCount) records · \(f.header.signals.count) signals")
                    Text(L.t("Checks: EDF/BDF signature, field sizes, digital and physical scaling, complete records, sample counts, TAL UTF-8, annotation timestamps, chronological record order.","已检查：EDF/BDF 标识、字段长度、数字及物理缩放、记录完整性、样本数、TAL UTF-8、标注时间戳与记录时间顺序。"))
                    ForEach(f.warnings,id:\.self) { Label($0,systemImage:"exclamationmark.triangle").foregroundStyle(.orange) }
                    Text(L.t("This checker reports the validations implemented in this build; it does not certify every EDF+ specification requirement.","本检查器报告此版本实现的验证项，不代表对 EDF+ 全部规范要求进行认证。")).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(24).frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}

struct CSVImportView: View {
    @EnvironmentObject var model: AppModel
    @ViewState var rate = 256
    @ViewState var unit = "uV"
    var body: some View {
        Form {
            Text(L.t("Supports wide CSV (time,C3,C4,…) and long CSV (time,signal,value,unit). Time is in seconds. Sample rates must be uniform integer Hz, and signals must share the same duration.","支持宽表 CSV（time,C3,C4,…）和长表 CSV（time,signal,value,unit）。时间单位为秒；采样率需为均匀整数 Hz，各信号需具有相同时长。"))
            TextField(L.t("Sample rate if no time column","无时间列时的采样率"),value:$rate,format:.number)
            TextField(L.t("Default unit","默认单位"),text:$unit)
            Button(L.t("Choose CSV & Save EDF+…","选择 CSV 并保存 EDF+…")) {
                let p = NSOpenPanel(); guard p.runModal() == .OK, let source = p.url else { return }
                let s = NSSavePanel(); s.nameFieldStringValue = source.deletingPathExtension().lastPathComponent+".edf"
                guard s.runModal() == .OK, let destination = s.url else { return }
                let inputRate = rate, inputUnit = unit
                model.perform { try CSV.importSignals(from:source,to:destination,defaultRate:inputRate,unit:inputUnit) }
            }.buttonStyle(.borderedProminent)
            if model.busy { ProgressView() }
        }.formStyle(.grouped)
    }
}
