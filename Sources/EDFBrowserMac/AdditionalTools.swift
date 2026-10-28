import SwiftUI
import AppKit
import AVKit
import Network
import EDFCore

struct VideoToolView: View {
    @EnvironmentObject var model: AppModel
    @ViewState var player: AVPlayer?
    @ViewState var offset = 0.0
    @ViewState var name = ""
    var body: some View {
        VStack(spacing:15) {
            HStack {
                Button(L.t("Open Video…","打开视频…")) {
                    let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie,.video]
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    player?.pause(); player = AVPlayer(url:url); name = url.lastPathComponent; sync()
                }
                Text(name).font(.caption).lineLimit(1); Spacer()
                TextField(L.t("Video starts at recording time (s)","视频起点对应记录时间（秒）"),value:$offset,format:.number).frame(width:275)
            }
            if let player { VideoPlayer(player:player).frame(maxWidth:.infinity,maxHeight:.infinity) }
            else { ContentUnavailableView(L.t("Choose a synchronized video","选择同步视频"),systemImage:"video").frame(maxWidth:.infinity,maxHeight:.infinity) }
            HStack {
                Button { model.navigate(-model.page); sync() } label: { Image(systemName:"backward.frame") }
                Button { model.togglePlayback(); sync() } label: { Image(systemName:model.isPlaying ? "pause.fill" : "play.fill") }
                Button { model.navigate(model.page); sync() } label: { Image(systemName:"forward.frame") }
                Slider(value:Binding(get:{model.position},set:{model.jump($0); sync()}),in:0...max(1,model.maximumTime-model.page))
                Text(EDFDate.clock(model.position)).font(.caption.monospacedDigit())
            }
            Text(L.t("Recording time drives video playback. Set the start offset when the video and EDF begin at different times. Supported codecs are provided by AVFoundation.","视频跟随记录时间播放。视频与 EDF 起点不同时，请设置偏移。编解码支持由 AVFoundation 提供。")).font(.caption).foregroundStyle(.secondary)
        }.padding(20).onChange(of:model.position) { _,_ in sync() }.onChange(of:offset) { _,_ in sync() }.onDisappear { player?.pause() }
    }
    func sync() {
        guard let player else { return }
        let target = max(0,model.position-offset)
        if abs(player.currentTime().seconds-target) > 0.2 { player.seek(to:CMTime(seconds:target,preferredTimescale:1000),toleranceBefore:.zero,toleranceAfter:.zero) }
        if model.isPlaying { player.play() } else { player.pause() }
    }
}

struct CombineToolView: View {
    @EnvironmentObject var model: AppModel
    @ViewState var mode = "channels"
    @ViewState var bdf = false
    var body: some View {
        Form {
            Text(L.t("Combines recordings in the order they were opened.","按打开顺序合并当前记录。"))
            Picker(L.t("Mode","方式"),selection:$mode) { Text(L.t("Stack channels (same start time)","叠加通道（相同起点）")).tag("channels"); Text(L.t("Concatenate time (same channel layout)","按时间拼接（相同通道布局）")).tag("time") }
            Toggle(L.t("BDF+ 24-bit output","BDF+ 24 位输出"),isOn:$bdf)
            ForEach(model.recordings) { entry in LabeledContent(entry.file.url.lastPathComponent,value:"\(entry.file.signalChannels.count) ch · \(entry.file.duration) s") }
            Text(L.t("Channel stacking requires matching start times and durations. Time concatenation explicitly places each recording immediately after the preceding one; annotations record the source boundaries. Gaps and fractional sample rates must be handled before combining.","通道叠加要求起点与时长一致。时间拼接会将记录依次紧接放置，并用标注保留源文件边界。合并前需处理时间间隙和非整数采样率。")).font(.caption).foregroundStyle(.secondary)
            Button(L.t("Combine & Save…","合并并保存…"),action:combine).buttonStyle(.borderedProminent).disabled(model.recordings.count < 2 || model.busy)
            if model.busy { ProgressView() }
        }.formStyle(.grouped)
    }
    func combine() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = bdf ? "Combined.bdf" : "Combined.edf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let entries = model.recordings, concatenate = mode == "time", useBDF = bdf
        model.perform {
            let files = entries.map(\.file), first = files[0]
            guard !files.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { throw EDFError.invalid("Choose a new output file") }
            for f in files {
                guard f.recordOnsets.first == 0, zip(f.recordOnsets,f.recordOnsets.dropFirst()).allSatisfy({ abs($1-$0-f.header.recordDuration)<1e-6 }) else { throw EDFError.invalid("Combine requires continuous records starting at time 0") }
            }
            let outputSignals: [EDFOutputSignal]
            var events: [EDFAnnotation] = [], duration = 0.0
            var mapping: [(Int,EDFSignal)] = []
            if concatenate {
                for (i,f) in files.enumerated() {
                    guard f.signalChannels.count == first.signalChannels.count, zip(f.signalChannels,first.signalChannels).allSatisfy({ $0.label == $1.label && $0.unit == $1.unit && abs($0.sampleRate(f.header.recordDuration)-$1.sampleRate(first.header.recordDuration))<1e-6 }), abs(f.duration-f.duration.rounded())<1e-6 else { throw EDFError.invalid("Time concatenation requires identical channel labels, units and rates, with integer-second duration") }
                    for event in entries[i].annotations { events.append(EDFAnnotation(onset:duration+event.onset,duration:event.duration,text:event.text)) }
                    events.append(EDFAnnotation(onset:duration,text:"Source: \(f.url.lastPathComponent)")); duration += f.duration
                }
                mapping = first.signalChannels.map { (0,$0) }
                outputSignals = try first.signalChannels.enumerated().map { index,s in
                    let rate = s.sampleRate(first.header.recordDuration)
                    guard abs(rate-rate.rounded())<1e-6 else { throw EDFError.invalid("Fractional sample rate") }
                    return EDFOutputSignal(label:s.label,unit:s.unit,rate:Int(rate),minimum:files.map { $0.signalChannels[index].physicalMin }.min()!,maximum:files.map { $0.signalChannels[index].physicalMax }.max()!)
                }
            } else {
                guard files.allSatisfy({ abs($0.header.startDate.timeIntervalSince(first.header.startDate))<1e-6 && abs($0.duration-first.duration)<1e-6 }) else { throw EDFError.invalid("Channel stacking requires equal recording start time and duration") }
                duration = first.duration
                mapping = files.enumerated().flatMap { index,f in f.signalChannels.map { (index,$0) } }
                outputSignals = try mapping.map { index,s in
                    let rate = s.sampleRate(files[index].header.recordDuration)
                    guard abs(rate-rate.rounded())<1e-6 else { throw EDFError.invalid("Fractional sample rate") }
                    return EDFOutputSignal(label:s.label,unit:s.unit,rate:Int(rate),minimum:s.physicalMin,maximum:s.physicalMax,prefilter:s.prefilter)
                }
                events = entries.flatMap(\.annotations)
            }
            try EDFWriter.write(to:url,signals:outputSignals,duration:duration,bdf:useBDF,patient:first.header.patient,recording:first.header.recording,date:first.header.startDate,annotations:events) { channel,record,count in
                var sourceIndex = mapping[channel].0, time = Double(record)
                if concatenate { sourceIndex = 0; while sourceIndex+1 < files.count && time >= files[sourceIndex].duration { time -= files[sourceIndex].duration; sourceIndex += 1 } }
                let f = files[sourceIndex], s = f.signalChannels[channel < f.signalChannels.count && concatenate ? channel : f.signalChannels.firstIndex(where:{$0.id == mapping[channel].1.id})!]
                return Array(try f.samples(channel:s.id,start:time,duration:Double(count)/Double(outputSignals[channel].rate)).values.prefix(count))
            }
        }
    }
}

@MainActor final class RemoteServer: ObservableObject {
    @Published var running = false
    @Published var status = ""
    var listener: NWListener?
    func stop() { listener?.cancel(); listener = nil; running = false }
    func start(port:UInt16,model:AppModel) {
        stop()
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:port)!)
            let listener = try NWListener(using:params)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in Task { @MainActor in
                switch state { case .ready: self?.running = true; self?.status = "127.0.0.1:\(port)"; case .failed(let error): self?.status = error.localizedDescription; self?.running = false; default: break }
            } }
            listener.newConnectionHandler = { connection in
                connection.start(queue:.global(qos:.utility))
                connection.receive(minimumIncompleteLength:1,maximumLength:4096) { data,_,_,_ in
                    Task { @MainActor in
                        let command = String(data:data ?? Data(),encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
                        let parts = command.split(separator:" ")
                        var answer: [String:Any] = ["ok":true]
                        switch parts.first {
                        case "status": answer["position"] = model.position; answer["page"] = model.page; answer["duration"] = model.maximumTime
                        case "seek": if parts.count == 2, let v = Double(parts[1]), v.isFinite { model.jump(v) } else { answer = ["ok":false,"error":"seek SECONDS"] }
                        case "page": if parts.count == 2, let v = Double(parts[1]), v.isFinite, v >= 0.05, v <= 86400 { model.page = v } else { answer = ["ok":false,"error":"page SECONDS (0.05...86400)"] }
                        case "next": model.navigate(model.page)
                        case "prev": model.navigate(-model.page)
                        default: answer = ["ok":false,"error":"Commands: status, seek SECONDS, page SECONDS, next, prev"]
                        }
                        let output = (try? JSONSerialization.data(withJSONObject:answer,options:[.sortedKeys])) ?? Data("{}".utf8)
                        connection.send(content:output+Data([10]),completion:.contentProcessed { _ in connection.cancel() })
                    }
                }
            }
            listener.start(queue:.global(qos:.utility))
        } catch { status = error.localizedDescription }
    }
}

struct RemoteToolView: View {
    @EnvironmentObject var model: AppModel
    @StateObject var server = RemoteServer()
    @ViewState var port = 32999
    var body: some View {
        Form {
            Text(L.t("Control navigation over a local TCP connection. The listener binds only to 127.0.0.1 and remains active while this panel is open.","通过本地 TCP 连接控制导航。仅监听 127.0.0.1；面板关闭时停止服务。"))
            TextField("Port",value:$port,format:.number)
            HStack { Button(L.t("Start","启动")) { if (1024...65535).contains(port) { server.start(port:UInt16(port),model:model) } }; Button(L.t("Stop","停止"),action:server.stop) }
            Text(server.status).font(.caption.monospaced())
            Text("printf 'status\\n' | nc 127.0.0.1 \(port)\nprintf 'seek 120\\n' | nc 127.0.0.1 \(port)\nprintf 'page 30\\n' | nc 127.0.0.1 \(port)").font(.system(.body,design:.monospaced)).textSelection(.enabled)
            Text(L.t("One command per connection; JSON response. This is the Mac edition's protocol.","每次连接执行一条命令并返回 JSON。本接口使用 Mac 版协议。")).font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped).onDisappear { server.stop() }
    }
}

struct HelpToolView: View {
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text(L.t("Open EDF, EDF+, BDF or BDF+ recordings with ⌘O or drag-and-drop. Open multiple files to compare synchronized signals.","使用 ⌘O 或拖放打开 EDF、EDF+、BDF、BDF+ 记录。可打开多个文件同步比较。"))
                Text(L.t("Select and toggle signals beside their waveform labels. Hidden signals collapse to a compact row and can be enabled again. Right-click a label to reorder or invert a trace. ↑ increases waveform amplitude and ↓ decreases it; text editors retain their arrow-key behavior. The Hypnogram toolbar button shows or hides the sleep plot and remembers your choice.","在波形名称旁选择、勾选通道。隐藏通道会折叠为紧凑行，可随时重新勾选；右键名称可调整顺序或反转波形。↑ 放大波形，↓ 缩小波形；编辑文本时方向键仍用于光标移动。工具栏“睡眠图”按钮可显示或隐藏睡眠图，并记住选择。"))
                Text(L.t("Voltage traces and cursor amplitudes display in μV, converting mV × 1000 and V × 1,000,000. Range 100 μV means a total vertical span of 100 μV (±50 μV around zero at default gain). Auto range is identified explicitly. The source unit and calibration remain visible in the inspector; recording exports keep their original physical units. Displayed voltage PSD uses μV²/Hz.","电压波形与游标幅度统一使用 μV：mV ×1000、V ×1,000,000。“量程 100 μV”表示默认增益下零线上下各 50 μV 的总范围；自动适应时会明确显示“自适应”。检查器仍显示源文件单位与校准；记录导出保留原物理单位。电压功率谱使用 μV²/Hz。"))
                Text(L.t("Drag over the waveform to zoom, Shift-drag for an analysis selection, click for cursor A and Option-click for cursor B. Clear cursors in the Signal inspector or press Escape.","拖动波形可放大；Shift 拖动选择分析区间；单击设置游标 A，Option 单击设置游标 B。在通道检查器中或按 Escape 清除游标。"))
                Text(L.t("Sleep scoring: 1=W, 2=N1, 3=N2, 4=N3, 5=REM, 6=unscored. Choose epoch length and auto-advance below the hypnogram. Annotation edits support ⌘Z / ⇧⌘Z.","睡眠分期：1=W，2=N1，3=N2，4=N3，5=REM，6=未评分。在睡眠图下方选择分期长度与自动前进。标注编辑支持 ⌘Z / ⇧⌘Z。"))
                Text(L.t("Save Annotated Copy preserves original digital samples and the record time axis. Export can crop, select channels, apply derivations/filters and resample. Sessions preserve open paths, montage and unsaved annotations.","“保存带标注副本”保留原数字样本与记录时间轴；“导出”可裁剪、选择通道、应用导联与滤波并重采样。会话保存文件路径、导联及未保存的标注。"))
                Text(L.t("Analysis includes Welch PSD, CDSA, aEEG, event averages, signal/sleep statistics and Pan–Tompkins QRS with RR/HRV. Main-view filters are causal, with pre-roll when browsing. Display gain never changes exported physical values.","分析包含 Welch 功率谱、CDSA、aEEG、事件平均、信号/睡眠统计，以及 Pan–Tompkins QRS 和 RR/HRV。主视图使用因果滤波，浏览时预读一段数据。显示增益不会改变导出的物理值。"))
                Text(L.t("Native montages and sessions use .edfmontage/.edfsession. EDFBrowser .mtg import supports linear derivations, common IIR/FIR filters and low-pass moving average; unsupported imported stages produce an explicit error. Legacy .esf sessions and device-specific file converters are outside this build.","原生导联和会话使用 .edfmontage/.edfsession。支持导入原版 .mtg 的线性导联、常用 IIR/FIR 和低通移动平均；遇到暂不支持的处理级会明确提示。旧版 .esf 会话和设备专用格式转换暂不包含在此版本中。"))
                Divider()
                Text("EDFBrowser Mac · GPL-3.0-only").font(.headline)
                Text("Derived signal-processing code © 2007–2026 Teunis van Beelen. Fidlib © Jim Peters (LGPL-2.1). KISS FFT © Mark Borgerding (BSD). Full notices and source provenance are included with the project.").font(.caption).foregroundStyle(.secondary)
                Link(L.t("Original EDFBrowser manual","原版 EDFBrowser 手册"),destination:URL(string:"https://www.teuniz.net/edfbrowser/EDFbrowser%20manual.html")!)
            }.padding(24)
        }
    }
}
