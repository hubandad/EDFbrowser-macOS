import SwiftUI
import AppKit
import EDFCore

struct AnalysisResult: Sendable {
    var x: [Double] = []
    var y: [Double] = []
    var lower: [Double] = []
    var heat: [[Double]] = []
    var frequency: [Double] = []
    var binWidths: [Double] = []
    var rows: [(String,String)] = []
    var csv = ""
    var annotations: [EDFAnnotation] = []
    var xLabel = "Time (s)"
    var yLabel = ""
    var note = ""
}

struct AnalysisToolView: View {
    let kind: Tool
    @EnvironmentObject var model: AppModel
    @ViewState var traceID: UUID?
    @ViewState var whole = false
    @ViewState var block = 1024
    @ViewState var segment = 30.0
    @ViewState var window = "Hann"
    @ViewState var maxFrequency = 40.0
    @ViewState var trigger = ""
    @ViewState var pre = 0.2
    @ViewState var post = 0.8
    @ViewState var crossover = 7.5
    @ViewState var result = AnalysisResult()
    @ViewState var running = false
    @ViewState var error: String?
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Picker(L.t("Signal","信号"),selection:$traceID) { ForEach(model.traces) { Text($0.label).tag(Optional($0.id)) } }.frame(maxWidth:340)
                Toggle(L.t("Whole recording","整个记录"),isOn:$whole).toggleStyle(.checkbox)
                Spacer()
                Button(L.t("Analyze","分析"),action:run).buttonStyle(.borderedProminent).disabled(running || traceID == nil)
            }
            if kind == .spectrum || kind == .cdsa {
                HStack {
                    Picker("FFT",selection:$block) { ForEach([128,256,512,1024,2048,4096,8192,16384],id:\.self) { Text("\($0)").tag($0) } }.frame(width:140)
                    Picker(L.t("Window","窗函数"),selection:$window) { ForEach(["Hann","Hamming","Blackman","Rectangular"],id:\.self) { Text($0) } }.frame(width:190)
                    TextField("Max Hz",value:$maxFrequency,format:.number).frame(width:120)
                    if kind == .cdsa { TextField(L.t("Segment (s)","分段（秒）"),value:$segment,format:.number).frame(width:140) }
                }
            }
            if kind == .aeeg { TextField(L.t("Segment length (s)","分段时长（秒）"),value:$segment,format:.number).frame(width:230) }
            if kind == .zeeg { TextField(L.t("Crossover (5–9.5 Hz)","交叉频率（5–9.5 Hz）"),value:$crossover,format:.number).frame(width:260) }
            if kind == .average {
                HStack {
                    Picker(L.t("Trigger","触发事件"),selection:$trigger) { ForEach(Array(Set(model.active?.annotations.map(\.text) ?? [])).sorted(),id:\.self) { Text($0).tag($0) } }
                    TextField(L.t("Before (s)","事件前（秒）"),value:$pre,format:.number).frame(width:125)
                    TextField(L.t("After (s)","事件后（秒）"),value:$post,format:.number).frame(width:125)
                }
            }
            if running { ProgressView().controlSize(.small) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if !result.heat.isEmpty { HeatmapPlot(result:result).frame(maxWidth:.infinity,maxHeight:.infinity).background(.quaternary.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius:8)) }
            else if !result.x.isEmpty { LinePlot(x:result.x,y:result.y,lower:result.lower,xLabel:result.xLabel,yLabel:result.yLabel).frame(maxWidth:.infinity,maxHeight:.infinity).background(.quaternary.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius:8)) }
            else if result.rows.isEmpty { ContentUnavailableView(L.t("Ready to analyze","准备分析"),systemImage:"waveform.path",description:Text(L.t("Choose a signal and analyze the current selection or recording.","选择通道后，可分析当前选区或整段记录。"))).frame(maxWidth:.infinity,maxHeight:.infinity) }
            if !result.rows.isEmpty {
                ScrollView { LazyVGrid(columns:[GridItem(.flexible(),alignment:.leading),GridItem(.flexible(),alignment:.trailing)],spacing:7) { ForEach(Array(result.rows.enumerated()),id:\.offset) { _,row in Text(row.0).foregroundStyle(.secondary); Text(row.1).monospacedDigit().textSelection(.enabled) } }.font(.caption).padding(10) }.frame(maxHeight:kind == .statistics ? .infinity : 105)
            }
            if !result.note.isEmpty { Text(result.note).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Text(L.t("Analysis uses physical samples and active derivations/filters. Plot results can be exported as CSV.","分析基于物理样本及当前导联/滤波；图表结果可导出为 CSV。")).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if !result.annotations.isEmpty { Button(L.t("Add Beat Annotations","添加心搏标注")) { if let i = model.activeIndex { model.setAnnotations(model.recordings[i].annotations+result.annotations,index:i) } } }
                Button(L.t("Export CSV…","导出 CSV…"),action:export).disabled(result.csv.isEmpty)
            }
        }.padding(20).onAppear {
            traceID = model.focusedTrace?.id; whole = kind == .cdsa || kind == .aeeg || kind == .qrs || kind == .zeeg
            trigger = model.active?.annotations.first(where:{$0.sleepStage == nil})?.text ?? ""
            if kind == .aeeg { segment = 15 }
        }
    }
    func run() {
        guard let trace = model.traces.first(where:{$0.id == traceID}), let entry = model.recordings.first(where:{$0.id == trace.sourceID}) else { return }
        let offset = model.offset(for:entry.id), file = entry.file, events = entry.annotations
        let begin = whole ? 0 : max(0,model.selectedInterval.lowerBound-offset), end = whole ? file.duration : min(file.duration,model.selectedInterval.upperBound-offset)
        let size = block, length = segment, wnd = window, maximum = kind == .zeeg ? crossover : maxFrequency, event = trigger, before = pre, after = post, type = kind
        guard end > begin, segment > 0, segment.isFinite, maxFrequency > 0, maxFrequency.isFinite, pre >= 0,post > 0 else { error = L.t("Invalid analysis interval or parameters","分析范围或参数无效"); return }
        running = true; error = nil
        Task {
            do { result = try await Task.detached(priority:.userInitiated) { try calculateAnalysis(kind:type,file:file,trace:trace,events:events,start:begin,end:end,block:size,segment:length,window:wnd,maxFrequency:maximum,trigger:event,pre:before,post:after) }.value }
            catch { self.error = error.localizedDescription }; running = false
        }
    }
    func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "\(kind.rawValue).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try result.csv.write(to:url,atomically:true,encoding:.utf8) } catch { model.report(error) }
    }
}

func calculateAnalysis(kind:Tool,file:EDFFile,trace:Trace,events:[EDFAnnotation],start:Double,end:Double,block:Int,segment:Double,window:String,maxFrequency:Double,trigger:String,pre:Double,post:Double) throws -> AnalysisResult {
    var output = AnalysisResult()
    let rate = file.header.signals[trace.channel].sampleRate(file.header.recordDuration)
    let displayUnit = SignalDisplayUnit(sourceUnit:file.header.signals[trace.channel].unit), unit = displayUnit.symbol
    func read(_ a:Double,_ b:Double) throws -> SampleSeries { try SignalEngine.read(trace:trace,file:file,start:a,duration:b-a) }
    func ensureContinuous(_ s:SampleSeries) throws {
        guard s.times.count >= 4 else { throw EDFError.invalid("Not enough recorded samples in the selected interval") }
        guard zip(s.times,s.times.dropFirst()).allSatisfy({ $1-$0 < 1.5/s.rate }) else { throw EDFError.invalid("Selection crosses recording gaps; choose a continuous interval") }
    }
    if kind == .zeeg {
        output.csv = "time_s,z_ratio\n"; output.yLabel = "Z-ratio (−1…1)"
        var t = start
        while t+2 <= end {
            let s = try read(t,t+2)
            if s.values.count >= Int(rate*2)-1 && s.gapStarts.isEmpty {
                let value = try DSP.zRatio(s.values,rate:rate,crossover:maxFrequency)
                output.x.append(t+1); output.y.append(value); output.csv += "\(t+1),\(value)\n"
            }
            t += 2
        }
        output.note = "2 s rectangular FFT · Z = (power 0.5–\(maxFrequency) Hz − power \(maxFrequency)–25 Hz) / total power 0.5–25 Hz. Gaps are excluded."
    } else if kind == .spectrum {
        let s = try read(start,end); try ensureContinuous(s)
        let spectrum = try DSP.spectrum(displayUnit.series(s).values,rate:rate,blockSize:block,window:window)
        let indices = spectrum.frequency.indices.filter { spectrum.frequency[$0] <= maxFrequency }
        output.x = indices.map { spectrum.frequency[$0] }; output.y = indices.map { 10*log10(max(1e-20,spectrum.power[$0])) }
        output.xLabel = "Hz"; output.yLabel = "dB \(unit)²/Hz"; output.csv = "frequency_hz,psd_\(unit)2_per_hz\n" + spectrum.frequency.indices.map { "\(spectrum.frequency[$0]),\(spectrum.power[$0])" }.joined(separator:"\n")
        let bands = [("Delta",0.5,4.0),("Theta",4.0,8.0),("Alpha",8.0,13.0),("Sigma",13.0,16.0),("Beta",16.0,30.0)]
        for (label,a,b) in bands { let power = spectrum.frequency.indices.filter { spectrum.frequency[$0] >= a && spectrum.frequency[$0] < b }.reduce(0.0) { $0+spectrum.power[$1]*spectrum.resolution }; output.rows.append(("\(label) \(a)–\(b) Hz",String(format:"%.5g %@²",power,unit))) }
        output.note = "Welch PSD · \(window) · 50% overlap · Δf \(spectrum.resolution) Hz"
    } else if kind == .cdsa || kind == .aeeg {
        guard (end-start)/segment <= 20000 else { throw EDFError.invalid("Increase segment length (maximum 20,000 segments)") }
        output.csv = kind == .cdsa ? "time_s,frequency_hz,psd_db\n" : "time_s,minimum_uV,maximum_uV\n"
        var t = start
        while t < end {
            let stop = min(end,t+segment)
            if kind == .cdsa {
                let s = try read(t,stop)
                if s.values.count < 4 { t += segment; continue }
                try ensureContinuous(s)
                let spec = try DSP.spectrum(displayUnit.series(s).values,rate:rate,blockSize:block,window:window)
                let indices = spec.frequency.indices.filter { spec.frequency[$0] <= maxFrequency }
                output.frequency = indices.map { spec.frequency[$0] }
                let values = indices.map { 10*log10(max(1e-20,spec.power[$0])) }
                output.x.append((t+stop)/2); output.binWidths.append(stop-t); output.heat.append(values)
                for i in indices.indices { output.csv += "\((t+stop)/2),\(output.frequency[i]),\(values[i])\n" }
            } else {
                guard let scale = file.header.signals[trace.channel].microvoltScale else { throw EDFError.invalid("aEEG requires a calibrated voltage signal") }
                let s = try read(max(0,t-30),stop); if s.values.count < 4 { t += segment; continue }; try ensureContinuous(s)
                let envelope = try DSP.aEEG(s.values.map { $0*scale },rate:rate)
                let values = zip(s.times,envelope).filter { $0.0 >= t }.map(\.1)
                if let low = values.min(), let high = values.max() {
                    output.x.append((t+stop)/2); output.y.append(high); output.lower.append(low)
                    output.csv += "\((t+stop)/2),\(low),\(high)\n"
                }
            }
            t += segment
        }
        output.yLabel = kind == .aeeg ? "μV" : "Hz"
        output.note = kind == .aeeg ? "2–15 Hz, 8th-order Butterworth bandpass → rectification → 0.5 Hz, 4th-order lowpass → segment minimum / maximum. Segment warm-up: 30 s." : "Welch PSD · \(window) · 50% overlap · \(segment) s segments · dB \(unit)²/Hz"
    } else if kind == .average {
        guard (pre+post)*rate < 1_000_000 else { throw EDFError.invalid("Averaging window is too large") }
        let count = Int(((pre+post)*rate).rounded()), baselineCount = Int((pre*rate).rounded())
        var sum = [Double](repeating:0,count:count), accepted = 0, rejected = 0
        for event in events where event.text == trigger && event.onset >= start && event.onset < end {
            if event.onset-pre < 0 || event.onset+post > file.duration { rejected += 1; continue }
            let s = try read(event.onset-pre,event.onset+post)
            if s.values.count != count || zip(s.times,s.times.dropFirst()).contains(where:{$1-$0 > 1.5/rate}) { rejected += 1; continue }
            let baseline = baselineCount > 0 ? s.values.prefix(baselineCount).reduce(0,+)/Double(baselineCount) : 0
            for i in sum.indices { sum[i] += s.values[i]-baseline }; accepted += 1
        }
        guard accepted > 0 else { throw EDFError.invalid("No complete epochs for this trigger") }
        output.x = sum.indices.map { Double($0)/rate-pre }; output.y = sum.map { displayUnit.value($0/Double(accepted)) }; output.yLabel = unit
        output.rows = [("Accepted epochs","\(accepted)"),("Rejected epochs","\(rejected)")]
        output.note = "Baseline corrected using the pre-event interval. Trigger: \(trigger)"
        output.csv = "time_s,average_\(unit)\n" + output.x.indices.map { "\(output.x[$0]),\(output.y[$0])" }.joined(separator:"\n")
    } else if kind == .qrs {
        guard let scale = file.header.signals[trace.channel].microvoltScale else { throw EDFError.invalid("QRS detector requires a voltage signal") }
        var t = start, beats: [Double] = []
        while t < end {
            let stop = min(end,t+300), series = try read(max(start,t-10),stop)
            let found = try DSP.qrs(series,microvoltScale:scale).filter { $0 >= t && $0 < stop }
            beats.append(contentsOf:found); t = stop
        }
        output.annotations = beats.map { EDFAnnotation(onset:$0,text:"R-peak") }
        var rr: [Double] = []
        for i in 1..<max(1,beats.count) {
            let delta = beats[i]-beats[i-1]
            if delta > 0.2 && delta < 3 {
                output.x.append(beats[i]); output.y.append(60/delta); rr.append(delta*1000)
            }
        }
        let differences = zip(rr,rr.dropFirst()).map { $1-$0 }
        let mean = rr.isEmpty ? 0 : rr.reduce(0,+)/Double(rr.count)
        let sdnn = rr.count > 1 ? sqrt(rr.reduce(0) { $0+pow($1-mean,2) }/Double(rr.count-1)) : 0
        let rmssd = differences.isEmpty ? 0 : sqrt(differences.reduce(0) { $0+$1*$1 }/Double(differences.count))
        output.rows = [("Detected beats","\(beats.count)"),("Mean HR",String(format:"%.2f bpm",mean > 0 ? 60000/mean : 0)),("SDNN",String(format:"%.3f ms",sdnn)),("RMSSD",String(format:"%.3f ms",rmssd)),("pNN50",String(format:"%.2f %%",differences.isEmpty ? 0 : 100*Double(differences.filter { abs($0)>50 }.count)/Double(differences.count)))]
        output.yLabel = "bpm"; output.note = "Pan–Tompkins · RR retained only in 200–3000 ms range. HRV uses retained intervals; ectopic-beat correction is not applied."
        output.csv = "onset_s,rr_ms,heart_rate_bpm\n" + output.x.indices.map { "\(output.x[$0]),\(rr[$0]),\(output.y[$0])" }.joined(separator:"\n")
    } else {
        let s = try read(start,end)
        let stats = DSP.statistics(displayUnit.series(s).values)
        output.rows = stats.keys.sorted().map { ($0 == "Count" ? $0 : "\($0) (\(unit))",String(format:"%.7g",stats[$0]!)) }
        for (stage,label) in [(0,"W"),(1,"REM"),(2,"N1"),(3,"N2"),(4,"N3")] {
            let seconds = events.filter { $0.sleepStage == stage }.reduce(0.0) { partial,event in partial+max(0,min(end,event.onset+(event.duration ?? 30))-max(start,event.onset)) }
            output.rows.append(("Sleep stage \(label)",String(format:"%.2f min (%.1f%%)",seconds/60,seconds/(end-start)*100)))
        }
        output.csv = "metric,value\n" + output.rows.map { CSV.escape($0.0)+","+CSV.escape($0.1) }.joined(separator:"\n")
        output.note = "Signal statistics use recorded samples only; sleep-stage percentages use the selected wall-clock interval."
    }
    return output
}

struct LinePlot: View {
    let x:[Double], y:[Double], lower:[Double]
    let xLabel:String, yLabel:String
    var body: some View {
        Canvas { context,size in
            guard x.count == y.count, !x.isEmpty else { return }
            let minX = x.min()!, maxX = max(minX+1e-9,x.max()!), minY = min(0,(y+lower).min() ?? 0), maxY = max(minY+1e-9,(y+lower).max() ?? 1)
            let plot = CGRect(x:67,y:25,width:max(1,size.width-88),height:max(1,size.height-65))
            func point(_ i:Int,_ v:Double) -> CGPoint { CGPoint(x:plot.minX+(x[i]-minX)/(maxX-minX)*plot.width,y:plot.maxY-(v-minY)/(maxY-minY)*plot.height) }
            for i in 0...5 {
                let y = plot.minY+Double(i)*plot.height/5
                var line = Path(); line.move(to:CGPoint(x:plot.minX,y:y)); line.addLine(to:CGPoint(x:plot.maxX,y:y)); context.stroke(line,with:.color(.secondary.opacity(0.18)),lineWidth:0.5)
                context.draw(Text(String(format:"%.3g",maxY-Double(i)/5*(maxY-minY))).font(.system(size:9,design:.monospaced)).foregroundColor(.secondary),at:CGPoint(x:32,y:y))
                let tx = minX+Double(i)/5*(maxX-minX)
                context.draw(Text(String(format:"%.4g",tx)).font(.system(size:9,design:.monospaced)).foregroundColor(.secondary),at:CGPoint(x:plot.minX+Double(i)*plot.width/5,y:plot.maxY+14))
            }
            var path = Path(); path.move(to:point(0,y[0])); for i in 1..<x.count { path.addLine(to:point(i,y[i])) }
            if lower.count == x.count { var band = path; for i in x.indices.reversed() { band.addLine(to:point(i,lower[i])) }; band.closeSubpath(); context.fill(band,with:.color(.teal.opacity(0.3))) }
            context.stroke(path,with:.color(.accentColor),lineWidth:1.2)
            context.draw(Text(yLabel).font(.system(size:10)).foregroundColor(.secondary),at:CGPoint(x:100,y:10))
            context.draw(Text(xLabel).font(.system(size:10)).foregroundColor(.secondary),at:CGPoint(x:plot.midX,y:size.height-9))
        }
    }
}

struct HeatmapPlot: View {
    let result:AnalysisResult
    var body: some View {
        Canvas { context,size in
            guard !result.x.isEmpty, !result.frequency.isEmpty else { return }
            let plot = CGRect(x:50,y:20,width:size.width-100,height:size.height-55)
            let values = result.heat.flatMap { $0 }.sorted(), lo = values[values.count/20], hi = max(lo+1,values[values.count*19/20])
            let widths = result.binWidths.count == result.x.count ? result.binWidths : result.x.map { _ in 1.0 }
            let start = zip(result.x,widths).map { $0-$1/2 }.min() ?? 0
            let end = max(start+1e-6,zip(result.x,widths).map { $0+$1/2 }.max() ?? 1)
            for i in result.heat.indices {
                for j in result.heat[i].indices {
                    let f = max(0,min(1,(result.heat[i][j]-lo)/(hi-lo)))
                    let rect = CGRect(x:plot.minX+(result.x[i]-widths[i]/2-start)/(end-start)*plot.width,y:plot.maxY-Double(j+1)*plot.height/Double(result.frequency.count),width:widths[i]/(end-start)*plot.width+0.5,height:plot.height/Double(result.frequency.count)+0.5)
                    context.fill(Path(rect),with:.color(Color(hue:(1-f)*0.69,saturation:0.85,brightness:0.3+0.7*f)))
                }
            }
            for i in 0...4 {
                context.draw(Text(String(format:"%.3g Hz",Double(i)/4*(result.frequency.last ?? 0))).font(.system(size:9)).foregroundColor(.secondary),at:CGPoint(x:24,y:plot.maxY-Double(i)/4*plot.height))
                context.draw(Text(EDFDate.clock(start+Double(i)/4*(end-start)).replacingOccurrences(of:".000",with:"")).font(.system(size:9,design:.monospaced)).foregroundColor(.secondary),at:CGPoint(x:plot.minX+Double(i)/4*plot.width,y:plot.maxY+17))
            }
            context.draw(Text(String(format:"%.1f dB",hi)).font(.system(size:9)).foregroundColor(.secondary),at:CGPoint(x:size.width-28,y:25))
            context.draw(Text(String(format:"%.1f dB",lo)).font(.system(size:9)).foregroundColor(.secondary),at:CGPoint(x:size.width-28,y:plot.maxY))
        }
    }
}
