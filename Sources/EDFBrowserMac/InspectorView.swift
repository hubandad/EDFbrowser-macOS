import SwiftUI
import AppKit
import EDFCore

struct InspectorView: View {
    @EnvironmentObject var model: AppModel
    @ViewState var tab = 0
    var body: some View {
        VStack(spacing:0) {
            Picker("",selection:$tab) { Text(L.t("Annotations","标注")).tag(0); Text(L.t("Signal","通道")).tag(1) }.pickerStyle(.segmented).padding(12)
            Divider()
            if tab == 0 { AnnotationInspector() } else { SignalInspector() }
        }.background(.background)
    }
}

struct AnnotationInspector: View {
    @EnvironmentObject var model: AppModel
    @ViewState var search = ""
    @ViewState var description = ""
    @ViewState var onset = 0.0
    @ViewState var duration = ""
    var body: some View {
        VStack(spacing:0) {
            TextField(L.t("Search annotations","搜索标注"),text:$search).textFieldStyle(.roundedBorder).padding(10)
            List(selection:$model.annotationSelection) {
                ForEach(model.active?.annotations.filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) } ?? []) { event in
                    VStack(alignment:.leading,spacing:3) {
                        Text(event.text).font(.system(size:11)).lineLimit(2)
                        HStack { Text(EDFDate.clock(event.onset)); if let d = event.duration { Text(String(format:"· %.3g s",d)) } }.font(.system(size:9,design:.monospaced)).foregroundStyle(.secondary)
                    }.padding(.vertical,3).tag(event.id)
                }
            }.listStyle(.inset).onChange(of:model.annotationSelection) { _,id in
                if let event = model.active?.annotations.first(where: { $0.id == id }) {
                    description = event.text; onset = event.onset; duration = event.duration.map { String($0) } ?? ""
                    model.jump(event.onset + model.offset(for:model.active!.id))
                }
            }
            HStack {
                Button { model.annotationSelection = nil; description = ""; onset = max(0,(model.cursorA ?? model.position) - model.offset(for:model.active?.id ?? UUID())); duration = model.selection.map { String($0.upperBound-$0.lowerBound) } ?? "" } label: { Image(systemName:"plus") }
                Button { remove() } label: { Image(systemName:"minus") }.disabled(model.annotationSelection == nil)
                Spacer()
                Text("\(model.active?.annotations.count ?? 0) \(L.t("events","事件"))").font(.caption2).foregroundStyle(.secondary)
                Menu { Button(L.t("Import CSV…","导入 CSV…"),action:importEvents); Button(L.t("Export CSV…","导出 CSV…"),action:exportEvents) } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).frame(width:18)
            }.padding(10)
            Divider()
            Form {
                TextField(L.t("Description","描述"),text:$description,axis:.vertical).lineLimit(2...4)
                TextField(L.t("Onset (s)","起点（秒）"),value:$onset,format:.number.precision(.fractionLength(0...6)))
                TextField(L.t("Duration (s)","时长（秒）"),text:$duration).help(L.t("Leave empty for point events","点事件请留空"))
                HStack {
                    Button(L.t("Use Cursors","使用游标")) { onset = (model.cursorA ?? model.position)-model.offset(for:model.active?.id ?? UUID()); if let a = model.cursorA, let b = model.cursorB { onset = min(a,b)-model.offset(for:model.active!.id); duration = String(abs(b-a)) } }
                    Spacer()
                    Button(model.annotationSelection == nil ? L.t("Add","添加") : L.t("Update","更新"),action:apply).buttonStyle(.borderedProminent).disabled(description.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }
            }.formStyle(.grouped).frame(height:255)
            Button(L.t("Save Annotated Copy…","保存带标注副本…"),action:model.saveAnnotations).buttonStyle(.bordered).padding(.bottom,12)
        }
    }
    func apply() {
        guard onset.isFinite else { return }
        let d = duration.trimmingCharacters(in:.whitespaces).isEmpty ? nil : Double(duration)
        if !duration.isEmpty && (d == nil || !d!.isFinite || d! < 0) { model.message = L.t("Duration must be a nonnegative number.","时长必须是非负数。"); return }
        if let index = model.activeIndex, let id = model.annotationSelection, let i = model.recordings[index].annotations.firstIndex(where:{$0.id == id}) {
            var events = model.recordings[index].annotations; events[i].onset = onset; events[i].duration = d; events[i].text = description; model.setAnnotations(events,index:index)
        } else { model.addAnnotation(text:description,onset:onset,duration:d) }
    }
    func remove() {
        guard let index = model.activeIndex, let id = model.annotationSelection else { return }
        model.setAnnotations(model.recordings[index].annotations.filter { $0.id != id },index:index); model.annotationSelection = nil
    }
    func importEvents() {
        let p = NSOpenPanel(); guard p.runModal() == .OK, let url = p.url, let index = model.activeIndex else { return }
        do { model.setAnnotations(model.recordings[index].annotations + (try CSV.annotations(from:url)),index:index) } catch { model.report(error) }
    }
    func exportEvents() {
        let p = NSSavePanel(); p.nameFieldStringValue = "Annotations.csv"
        guard p.runModal() == .OK, let url = p.url else { return }
        do { try CSV.writeAnnotations(model.active?.annotations ?? [],to:url) } catch { model.report(error) }
    }
}

struct SignalInspector: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            if let trace = model.focusedTrace, let file = model.recordings.first(where:{$0.id == trace.sourceID})?.file {
                let signal = file.header.signals[trace.channel]
                let displayUnit = SignalDisplayUnit(sourceUnit:signal.unit).symbol
                Form {
                    Section(L.t("DISPLAY","显示")) {
                        TextField(L.t("Label","名称"),text:binding(trace.id,\.label))
                        Toggle(L.t("Visible","显示"),isOn:binding(trace.id,\.visible))
                        Toggle(L.t("Invert polarity","反转极性"),isOn:binding(trace.id,\.inverted))
                        Picker(L.t("Color","颜色"),selection:binding(trace.id,\.colorIndex)) { ForEach(0..<8) { i in Text("● \(i+1)").foregroundStyle(traceColors[i]).tag(i) } }
                        Slider(value:binding(trace.id,\.gain),in:0.1...10) { Text(L.t("Gain","增益")) }
                        Text(String(format:"× %.2f",trace.gain)).font(.caption.monospacedDigit())
                    }
                    Section(L.t("SOURCE","源数据")) {
                        LabeledContent(L.t("Sample rate","采样率"),value:String(format:"%.5g Hz",signal.sampleRate(file.header.recordDuration)))
                        LabeledContent(L.t("Source unit","源文件单位"),value:signal.unit)
                        LabeledContent(L.t("Display unit","显示单位"),value:displayUnit)
                        LabeledContent(L.t("Source physical range","源物理范围"),value:"\(signal.physicalMin)…\(signal.physicalMax) \(signal.unit)")
                        LabeledContent(L.t("Digital range","数字范围"),value:"\(signal.digitalMin)…\(signal.digitalMax)")
                        Text(signal.transducer).font(.caption); Text(signal.prefilter).font(.caption)
                    }
                    Section(L.t("PROCESSING","处理")) {
                        Text(trace.filters.isActive ? trace.filters.summary : L.t("Original signal","原始信号")).font(.caption)
                        Button(L.t("Configure Filters…","配置滤波器…")) { model.tool = .filters }
                        Button(L.t("Power Spectrum…","功率谱…")) { model.tool = .spectrum }
                    }
                    Section(L.t("CURSOR MEASUREMENTS","游标测量")) {
                        if let a = model.cursorA { LabeledContent("A",value:EDFDate.clock(a)); if let v = value(at:a,trace:trace) { LabeledContent(L.t("A amplitude","A 幅度"),value:String(format:"%.5g %@",v,displayUnit)) } }
                        if let b = model.cursorB { LabeledContent("B",value:EDFDate.clock(b)); if let v = value(at:b,trace:trace) { LabeledContent(L.t("B amplitude","B 幅度"),value:String(format:"%.5g %@",v,displayUnit)) } }
                        if let a = model.cursorA, let b = model.cursorB {
                            LabeledContent("Δt",value:String(format:"%.6f s",abs(b-a)))
                            if abs(b-a) > 0 { LabeledContent("1/Δt",value:String(format:"%.4f Hz",1/abs(b-a))) }
                            if let va = value(at:a,trace:trace), let vb = value(at:b,trace:trace) { LabeledContent(L.t("Δ amplitude","幅度差"),value:String(format:"%.5g %@",vb-va,displayUnit)) }
                        }
                        Button(L.t("Clear Cursors & Selection","清除游标与选区")) { model.cursorA = nil; model.cursorB = nil; model.selection = nil }
                    }
                    if model.recordings.count > 1 { Toggle(L.t("Synchronize by start date/time","按开始日期时间同步"),isOn:$model.absoluteTime) }
                }.formStyle(.grouped)
            }
        }
    }
    func binding<T>(_ id:UUID,_ key:WritableKeyPath<Trace,T>) -> Binding<T> {
        Binding(get:{model.traces.first { $0.id == id }![keyPath:key]},set:{ value in model.updateTrace(id) { $0[keyPath:key] = value } })
    }
    func value(at time:Double,trace:Trace) -> Double? {
        guard let series = model.rendered.first(where:{$0.id == trace.id})?.series, !series.times.isEmpty else { return nil }
        let i = series.times.indices.min { abs(series.times[$0]-time) < abs(series.times[$1]-time) }!
        return abs(series.times[i]-time) <= max(0.02,1/series.rate) ? series.values[i] : nil
    }
}
