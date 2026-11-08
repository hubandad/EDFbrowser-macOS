import SwiftUI
import AppKit
import UniformTypeIdentifiers
import EDFCore

struct RecordingEntry: Identifiable {
    let file: EDFFile
    var annotations: [EDFAnnotation]
    var patient: String
    var recording: String
    var dirty = false
    var signalEdits: [Int:EDFSignal] = [:]
    var startDate: Date?
    var id: UUID { file.id }
}
struct RenderedTrace: Identifiable {
    var trace: Trace
    var series: SampleSeries
    var unit: String
    var error: String?
    var sourceToDisplay: Double = 1
    var id: UUID { trace.id }
}
enum Tool: String, Identifiable {
    case filters, spectrum, cdsa, aeeg, zeeg, average, statistics, qrs, export, header, validation, montage, video, help, csvImport, combine, remote
    var id: String { rawValue }
}
struct Montage: Codable { var version = 1; var traces: [Trace] }

@MainActor final class AppModel: ObservableObject {
    @Published var recordings: [RecordingEntry] = []
    @Published var traces: [Trace] = []
    @Published var selectedTrace: UUID?
    @Published var activeFileID: UUID?
    @Published var position = 0.0
    @Published var page = 30.0
    @Published var amplitude = 100.0
    static let amplitudeSteps: [Double] = [1,2,5,10,20,50,100,200,500,1000,2000,5000,10000,20000,50000,100000]
    @Published var channelSearch = ""
    @Published var showHypnogram = UserDefaults.standard.object(forKey:"showHypnogram") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showHypnogram,forKey:"showHypnogram") }
    }
    @Published var autoScale = false
    @Published var absoluteTime = true
    @Published var rendered: [RenderedTrace] = []
    @Published var rendering = false
    @Published var busy = false
    @Published var message: String?
    @Published var status = ""
    @Published var tool: Tool?
    @Published var inspector = true
    @Published var cursorA: Double?
    @Published var cursorB: Double?
    @Published var selection: ClosedRange<Double>?
    @Published var annotationSelection: UUID?
    @Published var epoch = 30.0
    @Published var scrollWithScoring = true
    @Published var isPlaying = false
    @Published var isMonitoring = false
    @Published var revision = 0
    private var playTimer: Timer?
    private var playbackClock: PlaybackClock?
    private var monitorTimer: Timer?
    private var renderTask: Task<Void,Never>?
    private var renderWorker: Task<[RenderedTrace],Never>?
    private var scaleKeyMonitor: Any?
    var undoManager: UndoManager?
    var activeIndex: Int? { recordings.firstIndex { $0.id == activeFileID } ?? (recordings.isEmpty ? nil : 0) }
    var active: RecordingEntry? { activeIndex.map { recordings[$0] } }
    var focusedTrace: Trace? { traces.first { $0.id == selectedTrace } ?? traces.first }
    var amplitudeUnit: String {
        guard let trace = focusedTrace, let file = recordings.first(where:{$0.id == trace.sourceID})?.file else { return "μV" }
        return SignalDisplayUnit(sourceUnit:file.header.signals[trace.channel].unit).symbol
    }
    var displayTraces: [Trace] { traces.filter { channelSearch.isEmpty || $0.label.localizedCaseInsensitiveContains(channelSearch) } }
    var maximumTime: Double { recordings.map { $0.file.duration + offset(for:$0.id) }.max() ?? 0 }
    var selectedInterval: Range<Double> { selection.map { $0.lowerBound..<$0.upperBound } ?? position..<min(maximumTime,position+page) }
    var renderKey: String { "\(position)-\(page)-\(revision)-\(absoluteTime)-\(channelSearch)-" + traces.map { "\($0.id)\($0.visible)\($0.inverted)\($0.filters)\($0.reference ?? -1)\($0.averageReference)" }.joined() }
    func offset(for id: UUID) -> Double {
        guard absoluteTime, let origin = recordings.map({$0.file.header.startDate}).min(), let file = recordings.first(where: { $0.id == id }) else { return 0 }
        return file.file.header.startDate.timeIntervalSince(origin)
    }
    func report(_ error: Error) { message = error.localizedDescription; status = error.localizedDescription }
    func openPanel() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension:"edf"), UTType(filenameExtension:"bdf")].compactMap { $0 }
        if panel.runModal() == .OK { open(urls:panel.urls) }
    }
    func open(urls: [URL], monitor: Bool = false) {
        busy = true
        Task {
            do {
                let loaded = try await Task.detached(priority:.userInitiated) { try urls.map { try EDFFile(url:$0,allowGrowing:monitor) } }.value
                for f in loaded {
                    if recordings.contains(where: { $0.file.url == f.url }) { continue }
                    recordings.append(RecordingEntry(file:f,annotations:f.annotations,patient:f.header.patient,recording:f.header.recording))
                    activeFileID = f.id
                    for (i,s) in f.signalChannels.enumerated() {
                        traces.append(Trace(sourceID:f.id,channel:s.id,label:s.label,colorIndex:i%8))
                    }
                    NSDocumentController.shared.noteNewRecentDocumentURL(f.url)
                }
                selectedTrace = traces.first?.id; revision += 1
                if monitor { startMonitoring() }
                status = L.t("Recording opened","已打开记录")
            } catch { report(error) }
            busy = false
        }
    }
    func demo() {
        busy = true
        Task {
            do {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("EDFBrowser-Synthetic-PSG.edf")
                try await Task.detached { try Demo.generate(to:url) }.value
                busy = false; open(urls:[url])
            } catch { busy = false; report(error) }
        }
    }
    func navigate(_ delta: Double) { position = max(0,min(max(0,maximumTime-page),position+delta)) }
    func jump(_ time: Double) { position = max(0,min(max(0,maximumTime-page),time)) }
    func zoom(_ factor: Double) { page = min(86400,max(0.05,page*factor)); jump(position) }
    func setAmplitudeSpan(_ value: Double) {
        guard value.isFinite, value > 0 else { return }
        let ratio = value/amplitude
        for i in traces.indices where traces[i].physicalPerCM != nil { traces[i].physicalPerCM! *= ratio }
        amplitude = value; autoScale = false
    }
    func stepAmplitude(largerWaveform: Bool) {
        let next = largerWaveform ? Self.amplitudeSteps.last(where: { $0 < amplitude-1e-9 }) : Self.amplitudeSteps.first(where: { $0 > amplitude+1e-9 })
        if let next { setAmplitudeSpan(next) }
    }
    func installScaleKeyboardShortcuts() {
        guard scaleKeyMonitor == nil else { return }
        scaleKeyMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, !self.recordings.isEmpty, self.tool == nil,
                      event.window === NSApp.mainWindow, NSApp.keyWindow?.attachedSheet == nil,
                      event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty,
                      event.keyCode == 125 || event.keyCode == 126 else { return false }
                if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable { return false }
                self.stepAmplitude(largerWaveform:event.keyCode == 126)
                return true
            }
            return handled ? nil : event
        }
    }
    func updateTrace(_ id: UUID, _ body: (inout Trace) -> Void) {
        guard let i = traces.firstIndex(where: { $0.id == id }) else { return }; body(&traces[i]); revision += 1
    }
    func render(pixels: Int) {
        renderTask?.cancel(); renderWorker?.cancel()
        let visible = displayTraces.filter(\.visible), files = recordings.map(\.file), start = position, duration = page
        let offsets = Dictionary(uniqueKeysWithValues:files.map { ($0.id,offset(for:$0.id)) })
        rendering = true
        let worker = Task.detached(priority:.userInitiated) {
                var result: [RenderedTrace] = []
                for trace in visible {
                    guard !Task.isCancelled else { break }
                    guard let f = files.first(where: { $0.id == trace.sourceID }) else { continue }
                    do {
                        let offset = offsets[f.id] ?? 0
                        var series = try SignalEngine.read(trace:trace,file:f,start:start-offset,duration:duration,envelopePixels:pixels)
                        let display = SignalDisplayUnit(sourceUnit:f.header.signals[trace.channel].unit)
                        series = display.series(series)
                        series.times = series.times.map { $0+offset }
                        series.gapStarts = series.gapStarts.map { $0+offset }
                        result.append(RenderedTrace(trace:trace,series:series,unit:display.symbol,sourceToDisplay:display.multiplier))
                    } catch is CancellationError { break }
                      catch { result.append(RenderedTrace(trace:trace,series:.empty,unit:"",error:error.localizedDescription)) }
                }
                return result
        }
        renderWorker = worker
        renderTask = Task {
            let result = await worker.value
            guard !Task.isCancelled else { return }
            rendered = result; rendering = false; renderWorker = nil
        }
    }
    func setAnnotations(_ events: [EDFAnnotation], index: Int, registerUndo: Bool = true) {
        guard recordings.indices.contains(index) else { return }
        let previous = recordings[index].annotations
        let fileID = recordings[index].id
        if registerUndo { undoManager?.registerUndo(withTarget:self) { target in MainActor.assumeIsolated { if let current = target.recordings.firstIndex(where:{$0.id == fileID}) { target.setAnnotations(previous,index:current) } } } }
        recordings[index].annotations = events.sorted { $0.onset < $1.onset }; recordings[index].dirty = true
    }
    func addAnnotation(text: String, onset: Double, duration: Double?) {
        guard let index = activeIndex else { return }
        let event = EDFAnnotation(onset:onset,duration:duration,text:text)
        var events = recordings[index].annotations; events.append(event); setAnnotations(events,index:index); annotationSelection = event.id
    }
    func score(_ stage: String) {
        guard let index = activeIndex else { return }
        let onset = floor((position-offset(for:recordings[index].id))/epoch)*epoch
        var events = recordings[index].annotations
        events.removeAll { $0.sleepStage != nil && abs($0.onset-onset) < 1e-6 }
        events.append(EDFAnnotation(onset:onset,duration:epoch,text:"Sleep stage \(stage)")); setAnnotations(events,index:index)
        if scrollWithScoring { page = epoch; navigate(epoch) }
    }
    func saveAnnotations() {
        guard let entry = active else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = entry.file.url.deletingPathExtension().lastPathComponent + "_annotated." + (entry.file.header.isBDF ? "bdf" : "edf")
        if panel.runModal() != .OK { return }; guard let url = panel.url else { return }
        perform({
            try EDFWriter.saveCopy(entry.file,to:url,annotations:entry.annotations,patient:entry.patient,recording:entry.recording,signalEdits:entry.signalEdits,startDate:entry.startDate)
        },onSuccess:{
            if let i = self.recordings.firstIndex(where:{$0.id == entry.id}), self.recordings[i].annotations == entry.annotations,
               self.recordings[i].patient == entry.patient, self.recordings[i].recording == entry.recording,
               self.recordings[i].signalEdits == entry.signalEdits, self.recordings[i].startDate == entry.startDate { self.recordings[i].dirty = false }
        })
    }
    func perform(_ work: @escaping @Sendable () throws -> Void,onSuccess:(() -> Void)? = nil) {
        busy = true
        Task {
            do { try await Task.detached(priority:.userInitiated,operation:work).value; status = L.t("Completed","已完成"); onSuccess?() }
            catch { report(error) }; busy = false
        }
    }
    func saveSession() {
        _ = saveSessionWithPanel()
    }
    private func saveSessionWithPanel() -> Bool {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Recording.edfsession"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        var state = SessionState(paths:recordings.map { $0.file.url.path },fileIDs:recordings.map(\.id),traces:traces,position:position,page:page,amplitude:amplitude,annotations:recordings.map(\.annotations),absoluteTime:absoluteTime,patients:recordings.map(\.patient),recordingIDs:recordings.map(\.recording),signalEdits:recordings.map(\.signalEdits),startDates:recordings.map(\.startDate),showHypnogram:showHypnogram)
        state.autoScale = autoScale; state.inspector = inspector; state.cursorA = cursorA; state.cursorB = cursorB
        state.selection = selection; state.channelSearch = channelSearch; state.activeFileID = active?.id
        state.selectedTrace = focusedTrace?.id; state.annotationSelection = annotationSelection
        state.epoch = epoch; state.scrollWithScoring = scrollWithScoring
        do {
            try state.validate(); try JSONEncoder().encode(state).write(to:url,options:.atomic)
            for i in recordings.indices { recordings[i].dirty = false }
            status = L.t("Session saved","会话已保存"); return true
        } catch { report(error); return false }
    }
    func loadSession() {
        let panel = NSOpenPanel(); guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let s = try JSONDecoder().decode(SessionState.self,from:Data(contentsOf:url))
            try s.validate()
            let opened = try s.paths.enumerated().map { i,path in try EDFFile(url:URL(fileURLWithPath:path),id:s.fileIDs[i]) }
            for trace in s.traces { guard let file = opened.first(where:{$0.id == trace.sourceID}) else { throw EDFError.invalid("Session trace source is missing") }; try trace.validate(for:file) }
            if recordings.contains(where: \.dirty) {
                let alert = NSAlert(); alert.messageText = L.t("Unsaved changes in this workspace","当前工作区有未保存的修改")
                alert.informativeText = L.t("Opening a session replaces the current recordings. Save your current session to keep these changes.","打开会话会替换当前记录。可先保存当前会话以保留这些修改。")
                alert.addButton(withTitle:L.t("Cancel","取消")); alert.addButton(withTitle:L.t("Save Current Session…","保存当前会话…")); alert.addButton(withTitle:L.t("Discard Changes and Open","放弃修改并打开"))
                let answer = alert.runModal()
                if answer == .alertFirstButtonReturn { return }
                if answer == .alertSecondButtonReturn && !saveSessionWithPanel() { return }
            }
            stopPlayback(); stopMonitoring(); renderTask?.cancel(); renderWorker?.cancel(); rendered = []; rendering = false
            undoManager?.removeAllActions(withTarget:self)
            recordings = opened.enumerated().map { i,file in
                var entry = RecordingEntry(file:file,annotations:s.annotations[i],patient:s.patients?.indices.contains(i) == true ? s.patients![i] : file.header.patient,recording:s.recordingIDs?.indices.contains(i) == true ? s.recordingIDs![i] : file.header.recording,dirty:false)
                entry.signalEdits = s.signalEdits?.indices.contains(i) == true ? s.signalEdits![i] : [:]
                entry.startDate = s.startDates?.indices.contains(i) == true ? s.startDates![i] : nil
                return entry
            }
            traces = s.traces; page = s.page; amplitude = s.amplitude; absoluteTime = s.absoluteTime
            jump(s.position); autoScale = s.autoScale ?? false; inspector = s.inspector ?? true
            cursorA = s.cursorA; cursorB = s.cursorB; selection = s.selection
            channelSearch = s.channelSearch ?? ""; epoch = s.epoch ?? 30; scrollWithScoring = s.scrollWithScoring ?? true
            if let show = s.showHypnogram { showHypnogram = show }
            activeFileID = s.activeFileID.flatMap { id in recordings.contains(where:{$0.id == id}) ? id : nil } ?? recordings.first?.id
            selectedTrace = s.selectedTrace.flatMap { id in traces.contains(where:{$0.id == id}) ? id : nil } ?? traces.first?.id
            annotationSelection = s.annotationSelection.flatMap { id in active?.annotations.contains(where:{$0.id == id}) == true ? id : nil }
            status = L.t("Session restored","会话已恢复"); revision += 1
        } catch { report(error) }
    }
    func saveMontage() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Montage.edfmontage"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try JSONEncoder().encode(Montage(traces:traces)).write(to:url,options:.atomic) } catch { report(error) }
    }
    func loadMontage() {
        let panel = NSOpenPanel(); guard panel.runModal() == .OK, let url = panel.url, let entry = active else { return }
        do {
            if url.pathExtension.lowercased() == "mtg" || url.pathExtension.lowercased() == "xml" {
                let imported = try LegacyMontage.read(url:url,file:entry.file)
                traces = imported.traces; if let value = imported.page, value >= 0.05, value <= 86400 { page = value }
                selectedTrace = traces.first?.id; revision += 1; status = imported.notes.joined(separator:" · "); return
            }
            let m = try JSONDecoder().decode(Montage.self,from:Data(contentsOf:url))
            for trace in m.traces { try trace.validate(for:entry.file) }
            guard m.traces.allSatisfy({ $0.channel >= 0 && $0.channel < entry.file.header.signals.count && ($0.reference == nil || ($0.reference! >= 0 && $0.reference! < entry.file.header.signals.count)) }) else { throw EDFError.invalid("Montage channel indices do not match the recording") }
            traces = m.traces.map { t in var trace = t; trace.id = UUID(); trace.sourceID = entry.id; return trace }; revision += 1
        } catch { report(error) }
    }
    func togglePlayback() {
        if isPlaying { stopPlayback(); return }
        let limit = max(0,maximumTime-page)
        guard !recordings.isEmpty, limit > 0 else { return }
        if position >= limit { jump(0) }
        isPlaying = true; playbackClock = PlaybackClock(now:ProcessInfo.processInfo.systemUptime)
        let timer = Timer(timeInterval:0.1,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.advancePlayback() }
        }
        playTimer = timer; RunLoop.main.add(timer,forMode:.common)
    }
    private func advancePlayback() {
        guard isPlaying, var clock = playbackClock else { return }
        let limit = max(0,maximumTime-page)
        position = clock.advance(position:position,limit:limit,now:ProcessInfo.processInfo.systemUptime)
        playbackClock = clock
        if position >= limit { stopPlayback() }
    }
    func stopPlayback() {
        playTimer?.invalidate(); playTimer = nil; playbackClock = nil; isPlaying = false
    }
    func startMonitoring() {
        isMonitoring = true; monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in Task { @MainActor in self?.refreshGrowing() } }
    }
    func refreshGrowing() {
        guard let index = activeIndex else { return }
        do {
            let entry = recordings[index], file = try EDFFile(url:entry.file.url,id:entry.id,allowGrowing:true)
            if file.header.recordCount != entry.file.header.recordCount {
                let original = Set(entry.file.annotations.map { "\($0.onset)|\($0.duration ?? -1)|\($0.text)" })
                let added = file.annotations.filter { !original.contains("\($0.onset)|\($0.duration ?? -1)|\($0.text)") }
                recordings[index] = RecordingEntry(file:file,annotations:entry.annotations+added,patient:entry.patient,recording:entry.recording,dirty:entry.dirty)
                recordings[index].signalEdits = entry.signalEdits; recordings[index].startDate = entry.startDate
                jump(maximumTime-page); revision += 1
            }
        } catch { status = error.localizedDescription }
    }
    func stopMonitoring() { monitorTimer?.invalidate(); isMonitoring = false }
    func decodeTriggers() {
        guard let entry = active else { return }; busy = true
        Task {
            do {
                let events = try await Task.detached { try StatusTriggers.decode(file:entry.file) }.value
                if let i = recordings.firstIndex(where:{$0.id == entry.id}) {
                    let existing = Set(recordings[i].annotations.map { "\($0.onset)|\($0.text)" })
                    setAnnotations(recordings[i].annotations+events.filter { !existing.contains("\($0.onset)|\($0.text)") },index:i)
                }
                status = L.t("Decoded triggers: ","已解析触发器：")+String(events.count)
            } catch { report(error) }; busy = false
        }
    }
    func closeActive() {
        guard let index = activeIndex else { return }
        if recordings[index].dirty {
            let alert = NSAlert(); alert.messageText = L.t("Unsaved annotations","标注尚未保存"); alert.informativeText = L.t("Save a copy or session before closing to keep changes.","如需保留修改，请先保存副本或会话。")
            alert.addButton(withTitle:L.t("Cancel","取消")); alert.addButton(withTitle:L.t("Discard and Close","放弃并关闭"))
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        let id = recordings[index].id; recordings.remove(at:index); traces.removeAll { $0.sourceID == id }; activeFileID = recordings.first?.id; revision += 1
        if selectedTrace.map({ selected in !traces.contains(where:{$0.id == selected}) }) ?? true { selectedTrace = traces.first?.id }
        jump(position)
        if recordings.isEmpty {
            stopPlayback(); stopMonitoring(); renderTask?.cancel(); renderWorker?.cancel(); rendered = []; rendering = false
        } else if position >= max(0,maximumTime-page) { stopPlayback() }
    }
}
