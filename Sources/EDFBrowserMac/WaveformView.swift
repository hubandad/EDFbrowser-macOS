import SwiftUI
import AppKit
import EDFCore

private struct WaveformRowGeometry {
    let trace: Trace
    let y: Double
    let height: Double
    var center: Double { y+height/2 }
}
private enum WaveformGeometry {
    static let top = 25.0
    static let hiddenHeight = 28.0
    static let visibleHeight = 66.0
    static func minimumHeight(_ traces:[Trace]) -> Double {
        top+traces.reduce(0) { $0+($1.visible ? visibleHeight : hiddenHeight) }
    }
    static func rows(_ traces:[Trace],height:Double) -> [WaveformRowGeometry] {
        let visible = traces.filter(\.visible).count, hidden = traces.count-visible
        let rowHeight = max(visibleHeight,(height-top-Double(hidden)*hiddenHeight)/Double(max(1,visible)))
        var y = top
        return traces.map { trace in
            let height = trace.visible ? rowHeight : hiddenHeight
            defer { y += height }
            return WaveformRowGeometry(trace:trace,y:y,height:height)
        }
    }
}

struct WaveformWorkspace: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                WaveformRepresentable(model:model)
                    .frame(height:max(geometry.size.height,WaveformGeometry.minimumHeight(model.displayTraces)))
            }
            .task(id:model.renderKey+"-\(Int(geometry.size.width))") { model.render(pixels:Int(geometry.size.width)) }
        }
    }
}

struct WaveformRepresentable: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeNSView(context:Context) -> WaveformNSView { WaveformNSView(model:model) }
    func updateNSView(_ view:WaveformNSView,context:Context) { view.model = model; view.syncControls(); view.needsDisplay = true }
}

@MainActor final class WaveformNSView: NSView {
    var model: AppModel
    var dragStart: NSPoint?
    var dragEnd: NSPoint?
    private var visibilityButtons: [UUID:NSButton] = [:]
    let labelWidth = 190.0
    let top = WaveformGeometry.top
    private var rowGeometry: [WaveformRowGeometry] { WaveformGeometry.rows(model.displayTraces,height:bounds.height) }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(model:AppModel) {
        self.model = model; super.init(frame:.zero)
        NotificationCenter.default.addObserver(self,selector:#selector(exportPDF),name:.exportWavePDF,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(exportPNG),name:.exportWavePNG,object:nil)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:)") }
    override func layout() { super.layout(); syncControls() }
    func syncControls() {
        let rows = rowGeometry, ids = Set(rows.map { $0.trace.id })
        for id in Array(visibilityButtons.keys) where !ids.contains(id) { visibilityButtons.removeValue(forKey:id)?.removeFromSuperview() }
        for row in rows {
            let trace = row.trace
            let button: NSButton
            if let existing = visibilityButtons[trace.id] { button = existing }
            else {
                button = NSButton(checkboxWithTitle:"",target:self,action:#selector(toggleVisibility(_:)))
                button.controlSize = .small
                button.identifier = NSUserInterfaceItemIdentifier(trace.id.uuidString)
                visibilityButtons[trace.id] = button; addSubview(button)
            }
            button.state = trace.visible ? .on : .off
            button.frame = NSRect(x:9,y:row.center-9,width:18,height:18)
            button.setAccessibilityLabel(L.t("Show signal ","显示通道 ")+trace.label)
            button.toolTip = L.t("Show / hide ","显示 / 隐藏 ")+trace.label
        }
    }
    @objc private func toggleVisibility(_ sender:NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString:raw), let trace = model.traces.first(where:{$0.id == id}) else { return }
        model.selectedTrace = id; model.activeFileID = trace.sourceID
        model.updateTrace(id) { $0.visible.toggle() }
    }
    func x(_ time:Double) -> Double { labelWidth + (time-model.position)/model.page*max(1,bounds.width-labelWidth-15) }
    func time(_ point:NSPoint) -> Double { model.position + max(0,min(1,(point.x-labelWidth)/max(1,bounds.width-labelWidth-15)))*model.page }
    func text(_ string:String,at point:NSPoint,size:Double = 10,color:NSColor = .secondaryLabelColor,mono:Bool = false) {
        let font = mono ? NSFont.monospacedDigitSystemFont(ofSize:size,weight:.regular) : NSFont.systemFont(ofSize:size)
        (string as NSString).draw(at:point,withAttributes:[.font:font,.foregroundColor:color])
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.textBackgroundColor.setFill(); bounds.fill()
        let plot = NSRect(x:labelWidth,y:top,width:max(1,bounds.width-labelWidth-15),height:bounds.height-top)
        let rows = rowGeometry
        let rendered = Dictionary(uniqueKeysWithValues:model.rendered.map { ($0.id,$0) })
        NSColor.windowBackgroundColor.withAlphaComponent(0.6).setFill(); NSRect(x:0,y:0,width:labelWidth,height:bounds.height).fill()
        text(L.t("SIGNAL","通道"),at:NSPoint(x:33,y:7),size:9)
        text("\(model.displayTraces.filter(\.visible).count)/\(model.displayTraces.count)",at:NSPoint(x:labelWidth-42,y:7),size:9,mono:true)
        if rows.isEmpty { text(L.t("No matching signals","没有匹配的通道"),at:NSPoint(x:labelWidth+16,y:45),size:13) }
        if UserDefaults.standard.object(forKey:"grid") as? Bool ?? true {
            let stepCandidates = [0.01,0.02,0.05,0.1,0.2,0.5,1,2,5,10,15,30,60,120,300,600,1800,3600.0]
            let step = stepCandidates.first { model.page / $0 <= 16 } ?? 7200
            let path = NSBezierPath(); path.lineWidth = 0.5
            for t in stride(from:ceil(model.position/step)*step,through:model.position+model.page,by:step) {
                let p = x(t); path.move(to:NSPoint(x:p,y:top)); path.line(to:NSPoint(x:p,y:bounds.height))
                text(model.page < 5 ? String(format:"%.2f",t) : EDFDate.clock(t).replacingOccurrences(of:".000",with:""),at:NSPoint(x:p+3,y:6),size:9,mono:true)
            }
            NSColor.separatorColor.withAlphaComponent(0.6).setStroke(); path.stroke()
        }
        NSGraphicsContext.saveGraphicsState(); plot.clip()
        if let entry = model.active {
            let offset = model.offset(for:entry.id)
            for event in entry.annotations {
                let onset = event.onset+offset, end = onset+(event.duration ?? 0)
                guard end >= model.position, onset <= model.position+model.page else { continue }
                let color = event.sleepStage != nil ? NSColor.systemIndigo : NSColor.systemOrange
                if let duration = event.duration, duration > 0 {
                    color.withAlphaComponent(0.045).setFill(); NSRect(x:x(onset),y:top,width:max(1,x(end)-x(onset)),height:plot.height).fill()
                }
                let path = NSBezierPath(); path.move(to:NSPoint(x:x(onset),y:top)); path.line(to:NSPoint(x:x(onset),y:bounds.height)); color.withAlphaComponent(0.35).setStroke(); path.lineWidth = 0.6; path.stroke()
                if event.sleepStage == nil { text(String(event.text.prefix(35)),at:NSPoint(x:x(onset)+4,y:top+2),size:9,color:color) }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        for geometry in rows {
            let trace = geometry.trace, y = geometry.y, center = geometry.center, rowHeight = geometry.height
            if trace.id == model.selectedTrace { NSColor.controlAccentColor.withAlphaComponent(0.065).setFill(); NSRect(x:0,y:y,width:bounds.width,height:rowHeight).fill() }
            let line = NSBezierPath(); line.move(to:NSPoint(x:0,y:y+rowHeight)); line.line(to:NSPoint(x:bounds.width,y:y+rowHeight)); NSColor.separatorColor.withAlphaComponent(0.45).setStroke(); line.lineWidth = 0.5; line.stroke()
            let color = NSColor(traceColors[trace.colorIndex%8])
            color.withAlphaComponent(trace.visible ? 0.9 : 0.25).setFill(); NSRect(x:30,y:y+6,width:2,height:rowHeight-12).fill()
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            (trace.label as NSString).draw(in:NSRect(x:38,y:trace.visible ? center-15 : center-7,width:labelWidth-46,height:17),withAttributes:[.font:NSFont.systemFont(ofSize:11,weight:trace.id == model.selectedTrace ? .semibold : .regular),.foregroundColor:trace.visible ? NSColor.labelColor : NSColor.tertiaryLabelColor,.paragraphStyle:paragraph])
            guard trace.visible else { continue }
            guard let row = rendered[trace.id] else { continue }
            let units = row.unit.isEmpty ? "a.u." : row.unit
            let minV = row.series.values.min() ?? -1, maxV = row.series.values.max() ?? 1
            let calibratedSpan = trace.physicalPerCM.map { $0*row.sourceToDisplay*rowHeight/max(1,UserDefaults.standard.double(forKey:"pointsPerCM") == 0 ? 37.8 : UserDefaults.standard.double(forKey:"pointsPerCM")) }
            let span = model.autoScale ? max(1e-12,(maxV-minV)*1.25) : max(1e-9,(calibratedSpan ?? model.amplitude)/trace.gain)
            let baseline = model.autoScale ? (maxV+minV)/2 : 0
            text(String(format:"%@ %.3g %@",L.t("Range","量程"),span,units),at:NSPoint(x:38,y:center+2),size:9,color:color)
            if let error = row.error { text(error,at:NSPoint(x:labelWidth+12,y:center),size:10,color:.systemOrange); continue }
            NSGraphicsContext.saveGraphicsState(); NSRect(x:labelWidth,y:y,width:plot.width,height:rowHeight).clip()
            let zero = NSBezierPath(); zero.move(to:NSPoint(x:labelWidth,y:center)); zero.line(to:NSPoint(x:bounds.width-15,y:center)); NSColor.separatorColor.withAlphaComponent(0.3).setStroke(); zero.lineWidth = 0.4; zero.stroke()
            let path = NSBezierPath(); path.lineWidth = 0.85
            var started = false, lastT = -Double.infinity
            for k in row.series.values.indices {
                let t = row.series.times[k], v = row.series.values[k]
                if t < model.position || t > model.position+model.page { continue }
                let point = NSPoint(x:x(t),y:center-(v-baseline)/span*rowHeight)
                if !started || row.series.gapStarts.contains(where: { $0 > lastT && $0 <= t }) { path.move(to:point); started = true }
                else { path.line(to:point) }; lastT = t
            }
            color.setStroke(); path.stroke()
            // Amplitude calibration: quarter-row scale bar, expressed in the signal's unit.
            let bar = NSBezierPath(); bar.move(to:NSPoint(x:bounds.width-11,y:center)); bar.line(to:NSPoint(x:bounds.width-11,y:center-rowHeight/4)); bar.line(to:NSPoint(x:bounds.width-7,y:center-rowHeight/4)); color.setStroke(); bar.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        if let range = model.selection { NSColor.controlAccentColor.withAlphaComponent(0.1).setFill(); NSRect(x:x(range.lowerBound),y:top,width:x(range.upperBound)-x(range.lowerBound),height:plot.height).fill() }
        for (cursor,label) in [(model.cursorA,"A"),(model.cursorB,"B")] {
            if let cursor, cursor >= model.position, cursor <= model.position+model.page {
                let path = NSBezierPath(); path.move(to:NSPoint(x:x(cursor),y:top)); path.line(to:NSPoint(x:x(cursor),y:bounds.height)); NSColor.labelColor.withAlphaComponent(0.6).setStroke(); path.lineWidth = 0.7; path.setLineDash([3,3],count:2,phase:0); path.stroke(); text(label,at:NSPoint(x:x(cursor)+3,y:top+14),color:.labelColor)
            }
        }
        if let a = dragStart, let b = dragEnd { NSColor.controlAccentColor.withAlphaComponent(0.15).setFill(); NSRect(x:min(a.x,b.x),y:top,width:abs(a.x-b.x),height:plot.height).fill() }
    }
    override func mouseDown(with event:NSEvent) {
        window?.makeFirstResponder(self); let point = convert(event.locationInWindow,from:nil)
        guard let row = rowGeometry.first(where: { point.y >= $0.y && point.y < $0.y+$0.height }) else { return }
        model.selectedTrace = row.trace.id; model.activeFileID = row.trace.sourceID
        guard row.trace.visible else { return }
        guard point.x >= labelWidth else { return }; dragStart = point; dragEnd = nil
        if event.modifierFlags.contains(.option) { model.cursorB = time(point) } else { model.cursorA = time(point) }
        needsDisplay = true
    }
    override func mouseDragged(with event:NSEvent) { guard dragStart != nil else { return }; dragEnd = convert(event.locationInWindow,from:nil); needsDisplay = true }
    override func mouseUp(with event:NSEvent) {
        defer { dragStart = nil; dragEnd = nil; needsDisplay = true }
        guard let a = dragStart, let b = dragEnd, abs(a.x-b.x) > 8 else { return }
        let range = min(time(a),time(b))...max(time(a),time(b))
        if event.modifierFlags.contains(.shift) { model.selection = range; model.cursorA = range.lowerBound; model.cursorB = range.upperBound }
        else { model.page = max(0.05,range.upperBound-range.lowerBound); model.jump(range.lowerBound) }
    }
    override func scrollWheel(with event:NSEvent) {
        if event.modifierFlags.contains(.command) { model.zoom(event.scrollingDeltaY > 0 ? 0.9 : 1.1) }
        else if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) { model.navigate(event.scrollingDeltaX/300*model.page) }
        else { super.scrollWheel(with:event) }
    }
    override func keyDown(with event:NSEvent) {
        switch event.keyCode { case 116: model.navigate(-model.page); case 121: model.navigate(model.page); case 115: model.jump(0); case 119: model.jump(model.maximumTime-model.page); case 53: model.selection = nil; model.cursorA = nil; model.cursorB = nil; default: super.keyDown(with:event) }
    }
    override func rightMouseDown(with event:NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        guard point.x < labelWidth, let row = rowGeometry.first(where: { point.y >= $0.y && point.y < $0.y+$0.height }) else { super.rightMouseDown(with:event); return }
        model.selectedTrace = row.trace.id; model.activeFileID = row.trace.sourceID
        let menu = NSMenu()
        for (title,tag) in [(L.t("Signal Properties","通道属性"),0),(L.t("Invert Polarity","反转极性"),1),(L.t("Move Up","上移"),2),(L.t("Move Down","下移"),3),(L.t("Remove Trace","移除波形"),4)] {
            let item = NSMenuItem(title:title,action:#selector(channelAction(_:)),keyEquivalent:"")
            item.target = self; item.tag = tag; item.representedObject = row.trace.id; menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu,with:event,for:self)
    }
    @objc private func channelAction(_ sender:NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let i = model.traces.firstIndex(where:{$0.id == id}) else { return }
        switch sender.tag {
        case 0: model.inspector = true
        case 1: model.updateTrace(id) { $0.inverted.toggle() }
        case 2: if i > 0 { model.traces.swapAt(i,i-1) }
        case 3: if i+1 < model.traces.count { model.traces.swapAt(i,i+1) }
        case 4: model.traces.remove(at:i)
        default: break
        }
    }
    @objc func exportPDF() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Waveforms.pdf"
        if panel.runModal() == .OK, let url = panel.url { do { try dataWithPDF(inside:bounds).write(to:url) } catch { model.report(error) } }
    }
    @objc func exportPNG() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Waveforms.png"
        guard panel.runModal() == .OK, let url = panel.url, let rep = bitmapImageRepForCachingDisplay(in:bounds) else { return }
        cacheDisplay(in:bounds,to:rep)
        if let data = rep.representation(using:.png,properties:[:]) { do { try data.write(to:url) } catch { model.report(error) } }
    }
}

struct HypnogramView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        GeometryReader { geometry in
            Canvas { context,size in
                let left = 44.0, width = max(1,size.width-left), height = size.height-16, maximum = max(1,model.maximumTime)
                for (i,label) in ["W","R","N1","N2","N3"].enumerated() { context.draw(Text(label).font(.system(size:9,design:.monospaced)).foregroundColor(.secondary),at:CGPoint(x:15,y:Double(i)*height/4+3)) }
                var path = Path(); var previousEnd: Double?
                if let entry = model.active {
                    let offset = model.offset(for:entry.id)
                    let stages = entry.annotations.filter { $0.sleepStage != nil }.sorted { $0.onset < $1.onset }
                    for (i,event) in stages.enumerated() {
                        let a = left+(event.onset+offset)/maximum*width
                        let end = event.onset+(event.duration ?? (i+1 < stages.count ? stages[i+1].onset-event.onset : model.epoch))
                        let b = left+(end+offset)/maximum*width, y = Double(event.sleepStage!)*height/4+3
                        if let previousEnd, abs(previousEnd-event.onset) < 0.01 { path.addLine(to:CGPoint(x:a,y:y)) } else { path.move(to:CGPoint(x:a,y:y)) }
                        path.addLine(to:CGPoint(x:b,y:y)); previousEnd = end
                    }
                }
                context.stroke(path,with:.color(.indigo),lineWidth:1.5)
                let viewport = CGRect(x:left+model.position/maximum*width,y:0,width:max(2,model.page/maximum*width),height:size.height)
                context.fill(Path(viewport),with:.color(.accentColor.opacity(0.09))); context.stroke(Path(viewport),with:.color(.accentColor.opacity(0.4)),lineWidth:1)
                context.draw(Text(L.t("HYPNOGRAM","睡眠图")).font(.system(size:8)).foregroundColor(.secondary),at:CGPoint(x:size.width-38,y:size.height-5))
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { v in model.jump(max(0,(v.location.x-44)/max(1,geometry.size.width-44))*model.maximumTime) })
        }
    }
}
