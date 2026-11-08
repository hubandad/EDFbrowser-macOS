import Foundation

/// Optional fields preserve compatibility with sessions saved by earlier Mac releases.
public struct SessionState: Codable, Sendable {
    public var paths: [String]
    public var fileIDs: [UUID]
    public var traces: [Trace]
    public var position: Double
    public var page: Double
    public var amplitude: Double
    public var annotations: [[EDFAnnotation]]
    public var absoluteTime: Bool
    public var patients: [String]?
    public var recordingIDs: [String]?
    public var signalEdits: [[Int:EDFSignal]]?
    public var startDates: [Date?]?
    public var showHypnogram: Bool?
    public var autoScale: Bool?
    public var inspector: Bool?
    public var cursorA: Double?
    public var cursorB: Double?
    public var selection: ClosedRange<Double>?
    public var channelSearch: String?
    public var activeFileID: UUID?
    public var selectedTrace: UUID?
    public var annotationSelection: UUID?
    public var epoch: Double?
    public var scrollWithScoring: Bool?

    public init(paths:[String],fileIDs:[UUID],traces:[Trace],position:Double,page:Double,amplitude:Double,
                annotations:[[EDFAnnotation]],absoluteTime:Bool,patients:[String]? = nil,recordingIDs:[String]? = nil,
                signalEdits:[[Int:EDFSignal]]? = nil,startDates:[Date?]? = nil,showHypnogram:Bool? = nil) {
        self.paths = paths; self.fileIDs = fileIDs; self.traces = traces; self.position = position
        self.page = page; self.amplitude = amplitude; self.annotations = annotations; self.absoluteTime = absoluteTime
        self.patients = patients; self.recordingIDs = recordingIDs; self.signalEdits = signalEdits
        self.startDates = startDates; self.showHypnogram = showHypnogram
    }

    public func validate() throws {
        guard paths.count == fileIDs.count, annotations.count == paths.count,
              Set(fileIDs).count == fileIDs.count, Set(traces.map(\.id)).count == traces.count,
              traces.allSatisfy({ fileIDs.contains($0.sourceID) }),
              position.isFinite, position >= 0, page.isFinite, page >= 0.05, page <= 86400,
              amplitude.isFinite, amplitude > 0,
              [cursorA,cursorB].compactMap({$0}).allSatisfy({$0.isFinite && $0 >= 0}),
              selection.map({$0.lowerBound.isFinite && $0.upperBound.isFinite && $0.lowerBound >= 0}) ?? true,
              epoch.map({$0 == 20 || $0 == 30}) ?? true else { throw EDFError.invalid("Invalid session file") }
    }
}

/// Playback follows a monotonic clock rather than assuming timer delivery is punctual.
public struct PlaybackClock: Sendable {
    private var lastTick: Double
    public init(now:Double) { lastTick = now }
    public mutating func advance(position:Double,limit:Double,now:Double) -> Double {
        guard position.isFinite, limit.isFinite, now.isFinite else { return position }
        let elapsed = max(0,now-lastTick)
        lastTick = max(lastTick,now)
        return min(max(0,limit),max(0,position)+elapsed)
    }
}
