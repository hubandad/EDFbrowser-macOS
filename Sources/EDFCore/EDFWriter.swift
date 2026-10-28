import Foundation

public struct EDFOutputSignal: Sendable {
    public var label: String
    public var unit: String
    public var rate: Int
    public var minimum: Double
    public var maximum: Double
    public var prefilter: String
    public init(label: String, unit: String, rate: Int, minimum: Double, maximum: Double, prefilter: String = "") {
        self.label = label; self.unit = unit; self.rate = rate; self.minimum = minimum; self.maximum = maximum; self.prefilter = prefilter
    }
}

public enum EDFWriter {
    static func field(_ text: String, _ count: Int) -> Data {
        let ascii = text.unicodeScalars.map { $0.value >= 32 && $0.value <= 126 ? UInt8($0.value) : UInt8(63) }
        return Data(ascii.prefix(count)) + Data(repeating: 32, count: max(0, count - ascii.count))
    }
    static func number(_ value: Double) throws -> String {
        guard value.isFinite else { throw EDFError.invalid("Non-finite EDF header value") }
        for precision in stride(from: 6, through: 0, by: -1) {
            let s = String(format: "%.*g", locale: Locale(identifier: "en_US_POSIX"), precision + 1, value)
            if s.count <= 8, Double(s) != 0 || value == 0 { return s }
        }
        throw EDFError.invalid("Value cannot be represented in an 8-byte EDF field: \(value)")
    }
    static func tal(_ event: EDFAnnotation) throws -> Data {
        guard event.onset.isFinite, event.duration == nil || (event.duration!.isFinite && event.duration! >= 0),
              !event.text.isEmpty, !event.text.utf8.contains(where: { $0 < 32 && $0 != 9 && $0 != 10 && $0 != 13 }) else {
            throw EDFError.invalid("Invalid annotation time, duration or control character")
        }
        return Data((signed(event.onset) + (event.duration.map { "\u{15}" + decimal($0) } ?? "") + "\u{14}" + event.text + "\u{14}\0").utf8)
    }
    static func decimal(_ v: Double) -> String {
        var s = String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), v)
        while s.last == "0" { s.removeLast() }; if s.last == "." { s.removeLast() }; return s
    }
    static func signed(_ v: Double) -> String { (v >= 0 ? "+" : "") + decimal(v) }
    static func annotationRecords(_ events: [EDFAnnotation], onsets: [Double], bytesPerSample: Int) throws -> ([Data], Int) {
        guard !onsets.isEmpty else { throw EDFError.invalid("Cannot save an empty recording") }
        var payload = onsets.map { Data((signed($0) + "\u{14}\u{14}\0").utf8) }
        for event in events {
            var lo = 0, hi = onsets.count
            while lo < hi { let mid = (lo+hi)/2; if onsets[mid] <= event.onset { lo = mid+1 } else { hi = mid } }
            payload[max(0,lo-1)].append(try tal(event))
        }
        let maxBytes = payload.map(\.count).max() ?? 1
        let samples = max(64, (maxBytes + bytesPerSample - 1) / bytesPerSample)
        guard samples < 10_000_000 else { throw EDFError.invalid("Annotation record is too large") }
        for i in payload.indices { payload[i].append(Data(repeating: 0, count: samples*bytesPerSample - payload[i].count)) }
        return (payload, samples)
    }
    static func header(signals: [EDFSignal], bdf: Bool, patient: String, recording: String, date: Date,
                       recordCount: Int, recordDuration: Double, discontinuous: Bool) throws -> Data {
        guard signals.count <= 4096, recordCount < 100_000_000 else { throw EDFError.invalid("EDF header capacity exceeded") }
        let stamp = EDFDate.stamp(date)
        var d = bdf ? Data([255]) + field("BIOSEMI",7) : field("0",8)
        d += field(patient,80) + field(recording,80) + field(stamp.0,8) + field(stamp.1,8)
        d += field(String(256 + signals.count*256),8) + field((bdf ? "BDF+" : "EDF+") + (discontinuous ? "D" : "C"),44)
        d += field(String(recordCount),8) + field(try number(recordDuration),8) + field(String(signals.count),4)
        for s in signals { d += field(s.label,16) }; for s in signals { d += field(s.transducer,80) }
        for s in signals { d += field(s.unit,8) }; for s in signals { d += field(try number(s.physicalMin),8) }
        for s in signals { d += field(try number(s.physicalMax),8) }; for s in signals { d += field(String(s.digitalMin),8) }
        for s in signals { d += field(String(s.digitalMax),8) }; for s in signals { d += field(s.prefilter,80) }
        for s in signals { d += field(String(s.samplesPerRecord),8) }; for _ in signals { d += field("",32) }
        return d
    }
    static func annotationSignal(bdf: Bool, samples: Int, index: Int) -> EDFSignal {
        EDFSignal(id: index, label: bdf ? "BDF Annotations" : "EDF Annotations", unit: "", physicalMin: -1, physicalMax: 1,
                  digitalMin: bdf ? -8388608 : -32768, digitalMax: bdf ? 8388607 : 32767, samplesPerRecord: samples)
    }
    /// Transactional sibling file; existing destinations are replaced only after a successful write.
    static func atomicWrite(to url: URL, body: (FileHandle) throws -> Void) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".edfmac-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else { throw EDFError.io("Cannot create output file") }
        do {
            let handle = try FileHandle(forWritingTo: temporary)
            do { try body(handle); try handle.synchronize(); try handle.close() } catch { try? handle.close(); throw error }
            if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary) }
            else { try FileManager.default.moveItem(at: temporary, to: url) }
        } catch { try? FileManager.default.removeItem(at: temporary); throw error }
    }
    public static func saveCopy(_ file: EDFFile, to url: URL, annotations: [EDFAnnotation], patient: String? = nil, recording: String? = nil,signalEdits:[Int:EDFSignal] = [:],startDate:Date? = nil) throws {
        guard url.standardizedFileURL != file.url.standardizedFileURL else { throw EDFError.invalid("Choose a new file; source recordings are preserved") }
        let h = file.header
        let channels = try file.signalChannels.map { s -> EDFSignal in
            guard var edited = signalEdits[s.id] else { return s }
            guard edited.samplesPerRecord == s.samplesPerRecord, edited.physicalMin.isFinite, edited.physicalMax.isFinite,
                  edited.physicalMin != edited.physicalMax, edited.digitalMin < edited.digitalMax,
                  edited.digitalMin >= (h.isBDF ? -8388608 : -32768), edited.digitalMax <= (h.isBDF ? 8388607 : 32767),
                  !edited.isAnnotation else { throw EDFError.invalid("Invalid signal header edits") }
            edited.byteOffset = s.byteOffset; return edited
        }
        let (payload, count) = try annotationRecords(annotations, onsets: file.recordOnsets, bytesPerSample: h.bytesPerSample)
        var signals = channels; signals.append(annotationSignal(bdf: h.isBDF, samples: count, index: channels.count))
        let hdr = try header(signals: signals, bdf: h.isBDF, patient: patient ?? h.patient, recording: recording ?? h.recording,
                             date: startDate ?? h.startDate, recordCount: h.recordCount, recordDuration: h.recordDuration, discontinuous: h.isDiscontinuous)
        try atomicWrite(to: url) { output in
            try output.write(contentsOf: hdr)
            for r in 0..<h.recordCount {
                for s in channels {
                    let p = h.headerBytes + r*h.bytesPerRecord + s.byteOffset
                    try output.write(contentsOf: file.data[p..<(p+s.samplesPerRecord*h.bytesPerSample)])
                }
                try output.write(contentsOf: payload[r])
            }
        }
    }
    public static func write(to url: URL, signals: [EDFOutputSignal], duration: Double, bdf: Bool = false, patient: String = "X X X X",
                             recording: String = "Startdate X X X X", date: Date = Date(), annotations: [EDFAnnotation] = [],
                             startOffset: Double = 0,
                             provider: (Int, Int, Int) throws -> [Double]) throws {
        guard duration.isFinite, duration > 0, !signals.isEmpty,
              signals.allSatisfy({ $0.rate > 0 && $0.rate <= 1_000_000 && $0.minimum.isFinite && $0.maximum.isFinite && $0.minimum < $0.maximum }) else {
            throw EDFError.invalid("Invalid output sample rate, range or duration")
        }
        let recordCount = Int(ceil(duration)), bytes = bdf ? 3 : 2, dMin = bdf ? -8388608 : -32768, dMax = bdf ? 8388607 : 32767
        guard startOffset >= 0, startOffset < 1 else { throw EDFError.invalid("Subsecond offset must be in [0,1)") }
        let onset = (0..<recordCount).map { Double($0)+startOffset }
        var events = annotations.map { event in EDFAnnotation(onset:event.onset+startOffset,duration:event.duration,text:event.text) }
        if Double(recordCount) > duration + 1e-7 { events.append(EDFAnnotation(onset: duration+startOffset, duration: Double(recordCount)-duration, text: "Padding: last sample held to complete EDF data record")) }
        let (payload, annotationCount) = try annotationRecords(events, onsets: onset, bytesPerSample: bytes)
        var channels = try signals.enumerated().map { i,s in
            EDFSignal(id: i, label: s.label, unit: s.unit, physicalMin: Double(try number(s.minimum))!, physicalMax: Double(try number(s.maximum))!,
                      digitalMin: dMin, digitalMax: dMax, prefilter: s.prefilter, samplesPerRecord: s.rate)
        }
        guard channels.allSatisfy({ $0.physicalMin != $0.physicalMax }) else { throw EDFError.invalid("Output range is too small to encode") }
        channels.append(annotationSignal(bdf: bdf, samples: annotationCount, index: channels.count))
        let hdr = try header(signals: channels, bdf: bdf, patient: patient, recording: recording, date: date, recordCount: recordCount, recordDuration: 1, discontinuous: false)
        try atomicWrite(to: url) { output in
            try output.write(contentsOf: hdr)
            var last = [Double](repeating: 0, count: signals.count)
            for r in 0..<recordCount {
                for (i,s) in channels.dropLast().enumerated() {
                    let count = max(0, min(s.samplesPerRecord, Int(ceil((duration-Double(r))*Double(s.samplesPerRecord)-1e-7))))
                    let v = try provider(i, r, count)
                    guard v.count == count, v.allSatisfy(\.isFinite) else { throw EDFError.invalid("Missing, non-finite or discontinuous samples in output; crop a continuous interval") }
                    var buffer = Data(); buffer.reserveCapacity(s.samplesPerRecord*bytes)
                    for k in 0..<s.samplesPerRecord {
                        let value = k < v.count ? v[k] : last[i]
                        if value < s.physicalMin - abs(s.scale)*0.51 || value > s.physicalMax + abs(s.scale)*0.51 { throw EDFError.invalid("Output range would clip \(s.label). Increase its physical range.") }
                        let digital = max(dMin,min(dMax,Int(((value-s.physicalMin)/s.scale + Double(dMin)).rounded())))
                        buffer.append(UInt8(truncatingIfNeeded: digital)); buffer.append(UInt8(truncatingIfNeeded: digital >> 8))
                        if bdf { buffer.append(UInt8(truncatingIfNeeded: digital >> 16)) }
                        last[i] = value
                    }
                    try output.write(contentsOf: buffer)
                }
                try output.write(contentsOf: payload[r])
            }
        }
    }
}
