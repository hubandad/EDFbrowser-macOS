// EDFBrowser Mac. GPL-3.0-only.
import Foundation

public enum EDFError: LocalizedError {
    case invalid(String), unsupported(String), io(String)
    public var errorDescription: String? {
        switch self { case .invalid(let s), .unsupported(let s), .io(let s): return s }
    }
}

public struct EDFSignal: Identifiable, Codable, Equatable, Sendable {
    public var id: Int
    public var label: String
    public var transducer: String = ""
    public var unit: String
    public var physicalMin: Double
    public var physicalMax: Double
    public var digitalMin: Int
    public var digitalMax: Int
    public var prefilter: String = ""
    public var samplesPerRecord: Int
    public var byteOffset: Int = 0
    public var isAnnotation: Bool { label == "EDF Annotations" || label == "BDF Annotations" }
    public func sampleRate(_ recordDuration: Double) -> Double { Double(samplesPerRecord) / recordDuration }
    public var scale: Double { (physicalMax - physicalMin) / Double(digitalMax - digitalMin) }
    public func physical(_ digital: Int) -> Double { Double(digital - digitalMin) * scale + physicalMin }
    public var microvoltScale: Double? {
        switch unit.lowercased().replacingOccurrences(of: "µ", with: "u").replacingOccurrences(of: "μ", with: "u") {
        case "uv": return 1
        case "mv": return 1000
        case "v": return 1_000_000
        default: return nil
        }
    }
}

public struct EDFAnnotation: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    public var onset: Double
    public var duration: Double?
    public var text: String
    public init(onset: Double, duration: Double? = nil, text: String) { self.onset = onset; self.duration = duration; self.text = text }
    public var sleepStage: Int? {
        let text = text.lowercased().replacingOccurrences(of: "sleep stage ", with: "").trimmingCharacters(in: .whitespaces)
        switch text {
        case "w", "wake", "清醒": return 0
        case "r", "rem": return 1
        case "1", "n1": return 2
        case "2", "n2": return 3
        case "3", "4", "n3", "n4": return 4
        default: return nil
        }
    }
}

public struct EDFHeader: Sendable {
    public var isBDF: Bool
    public var patient: String
    public var recording: String
    public var startDate: Date
    public var reserved: String
    public var headerBytes: Int
    public var declaredRecords: Int
    public var recordCount: Int
    public var recordDuration: Double
    public var bytesPerRecord: Int
    public var signals: [EDFSignal]
    public var bytesPerSample: Int { isBDF ? 3 : 2 }
    public var isDiscontinuous: Bool { reserved.hasPrefix("EDF+D") || reserved.hasPrefix("BDF+D") }
    public var format: String { (isBDF ? "BDF" : "EDF") + (reserved.contains("+") ? (isDiscontinuous ? "+D" : "+C") : "") }
}

public struct SampleSeries: Sendable {
    public var times: [Double]
    public var values: [Double]
    public var rate: Double
    public var gapStarts: [Double] = []
    public init(times: [Double], values: [Double], rate: Double) { self.times = times; self.values = values; self.rate = rate }
    public static let empty = SampleSeries(times: [], values: [], rate: 1)
}

public struct FilterSettings: Codable, Equatable, Sendable {
    public var highPass: Double = 0
    public var lowPass: Double = 0
    public var notch: Double = 0
    public var notchQ: Double = 30
    public var order: Int = 4
    public var family: String = "Butterworth"
    public var ripple: Double = 1
    public var movingAverage: Int = 0
    public var powerline: Int = 0
    public var firTaps: [Double] = []
    public var extraSpecifications: [String]?
    public var movingAverageHighPass: Bool?
    public var spikeVelocity: Double?
    public var spikeHoldoff: Int?
    public init() {}
    public var isActive: Bool { highPass > 0 || lowPass > 0 || notch > 0 || movingAverage > 1 || powerline > 0 || !firTaps.isEmpty || !(extraSpecifications ?? []).isEmpty || (spikeVelocity ?? 0) > 0 }
    public var summary: String {
        var parts: [String] = []
        if highPass > 0 { parts.append("HP:\(highPass)Hz") }
        if lowPass > 0 { parts.append("LP:\(lowPass)Hz") }
        if notch > 0 { parts.append("N:\(notch)Hz") }
        if movingAverage > 1 { parts.append("MA:\(movingAverage)") }
        if powerline > 0 { parts.append("PLIF:\(powerline)") }
        if !firTaps.isEmpty { parts.append("FIR:\(firTaps.count)") }
        parts += extraSpecifications ?? []
        if let velocity = spikeVelocity, velocity > 0 { parts.append("Spike:\(velocity)") }
        return parts.joined(separator: " ")
    }
}

public struct TraceComponent: Codable, Equatable, Sendable {
    public var channel: Int
    public var factor: Double
    public init(channel:Int,factor:Double) { self.channel = channel; self.factor = factor }
}

public struct Trace: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var sourceID: UUID
    public var channel: Int
    public var reference: Int?
    public var averageReference: Bool = false
    public var label: String
    public var colorIndex: Int = 0
    public var gain: Double = 1
    public var inverted = false
    public var visible = true
    public var filters = FilterSettings()
    public var components: [TraceComponent]?
    public var physicalPerCM: Double?
    public init(sourceID: UUID, channel: Int, reference: Int? = nil, label: String, colorIndex: Int = 0) {
        self.sourceID = sourceID; self.channel = channel; self.reference = reference; self.label = label; self.colorIndex = colorIndex
    }
    public func validate(for file:EDFFile) throws {
        let channels = [channel]+(reference.map { [$0] } ?? [])+(components?.map(\.channel) ?? [])
        guard channels.allSatisfy({ file.header.signals.indices.contains($0) && !file.header.signals[$0].isAnnotation }),
              (0..<8).contains(colorIndex), gain.isFinite, gain > 0,
              physicalPerCM == nil || (physicalPerCM!.isFinite && physicalPerCM! > 0),
              components == nil || (!components!.isEmpty && components!.allSatisfy({ $0.factor.isFinite && abs($0.factor) <= 128 })) else { throw EDFError.invalid("Invalid montage channel, scale, color or coefficient") }
    }
}

public enum EDFDate {
    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c
    }
    public static func parse(date: String, time: String) throws -> Date {
        let d = date.split(separator: ".").compactMap { Int($0) }
        let t = time.split(separator: ".").compactMap { Int($0) }
        guard d.count == 3, t.count == 3 else { throw EDFError.invalid("Invalid recording start date/time") }
        let y = d[2] >= 85 ? 1900 + d[2] : 2000 + d[2]
        guard (1...31).contains(d[0]), (1...12).contains(d[1]), (0...23).contains(t[0]), (0...59).contains(t[1]), (0...59).contains(t[2]),
              let value = calendar.date(from: DateComponents(year: y, month: d[1], day: d[0], hour: t[0], minute: t[1], second: t[2])) else {
            throw EDFError.invalid("Invalid recording start date/time")
        }
        return value
    }
    public static func stamp(_ date: Date) -> (String, String) {
        let c = calendar.dateComponents([.year,.month,.day,.hour,.minute,.second], from: date)
        return (String(format: "%02d.%02d.%02d", c.day!, c.month!, c.year! % 100), String(format: "%02d.%02d.%02d", c.hour!, c.minute!, c.second!))
    }
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        guard abs(seconds) < Double(Int.max/1000) else { return String(format:"%.5g s",seconds) }
        let m = Int(abs(seconds) * 1000)
        return (seconds < 0 ? "−" : "") + String(format: "%02d:%02d:%02d.%03d", m/3600000, m/60000%60, m/1000%60, m%1000)
    }
}
