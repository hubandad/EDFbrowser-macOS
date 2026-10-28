import Foundation

/// Immutable mapped data; each read borrows bytes without loading whole signal arrays.
public final class EDFFile: @unchecked Sendable, Identifiable {
    public let id: UUID
    public let url: URL
    public let header: EDFHeader
    public let annotations: [EDFAnnotation]
    public let recordOnsets: [Double]
    public let warnings: [String]
    public let data: Data
    public var duration: Double {
        let recorded = (recordOnsets.last ?? 0) + (header.recordCount > 0 ? header.recordDuration : 0)
        return signalChannels.isEmpty ? max(recorded,annotations.map { $0.onset+($0.duration ?? 0) }.max() ?? 0) : recorded
    }
    public var signalChannels: [EDFSignal] { header.signals.filter { !$0.isAnnotation } }

    public init(url: URL, id: UUID = UUID(), allowGrowing: Bool = false) throws {
        self.id = id; self.url = url
        data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let parsed = try Self.parseHeader(data, allowGrowing: allowGrowing)
        header = parsed.0
        var notes = parsed.1
        var events: [EDFAnnotation] = []
        var onsets: [Double] = []; onsets.reserveCapacity(header.recordCount)
        let annotationChannels = header.signals.filter(\.isAnnotation)
        for r in 0..<header.recordCount {
            var onset = Double(r) * header.recordDuration
            for (idx, signal) in annotationChannels.enumerated() {
                let offset = header.headerBytes + r * header.bytesPerRecord + signal.byteOffset
                let bytes = data.subdata(in: offset..<(offset + signal.samplesPerRecord * header.bytesPerSample))
                let tal = try Self.parseTAL(bytes)
                if idx == 0, let timestamp = tal.onset { onset = timestamp }
                events.append(contentsOf: tal.events)
            }
            if let previous = onsets.last, onset < previous + header.recordDuration - 1e-6 {
                throw EDFError.invalid("Data record \(r + 1) overlaps the preceding record")
            }
            if !header.isDiscontinuous, let previous = onsets.last, abs(onset - previous - header.recordDuration) > 1e-5 {
                notes.append("Record \(r + 1) has a time gap although the header declares continuous data")
            }
            onsets.append(onset)
        }
        annotations = events.sorted { $0.onset < $1.onset }
        recordOnsets = onsets; warnings = Array(notes.prefix(100))
    }

    private static func parseHeader(_ data: Data, allowGrowing: Bool) throws -> (EDFHeader, [String]) {
        guard data.count >= 256 else { throw EDFError.invalid("File is shorter than the EDF header") }
        func field(_ start: Int, _ size: Int) -> String {
            String(decoding: data[start..<(start+size)], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let bdf = data[0] == 255 && field(1,7) == "BIOSEMI"
        guard bdf || field(0,8) == "0" else { throw EDFError.invalid("Not an EDF or BDF file") }
        guard let n = Int(field(252,4)), n > 0, n <= 4096,
              let bytes = Int(field(184,8)), bytes >= 256 + n*256, bytes <= data.count,
              let declared = Int(field(236,8)), declared >= -1,
              let duration = Double(field(244,8)), duration.isFinite, duration >= 0, duration <= 86400 else {
            throw EDFError.invalid("Invalid header length, signal count, record count or duration")
        }
        let startDate = try EDFDate.parse(date: field(168,8), time: field(176,8))
        var signals: [EDFSignal] = []; var offset = 0
        for i in 0..<n {
            func f(_ group: Int, _ width: Int) -> String { field(256 + n * group + i * width, width) }
            let label = f(0,16)
            guard let pMin = Double(f(104,8)), let pMax = Double(f(112,8)), pMin.isFinite, pMax.isFinite, pMin != pMax,
                  let dMin = Int(f(120,8)), let dMax = Int(f(128,8)), dMin < dMax,
                  dMin >= (bdf ? -8388608 : -32768), dMax <= (bdf ? 8388607 : 32767),
                  let samples = Int(f(216,8)), samples > 0, samples <= 100_000_000 else {
                throw EDFError.invalid("Invalid scaling or sample count for signal \(i + 1): \(label)")
            }
            signals.append(EDFSignal(id: i, label: label, transducer: f(16,80), unit: f(96,8), physicalMin: pMin, physicalMax: pMax,
                                     digitalMin: dMin, digitalMax: dMax, prefilter: f(136,80), samplesPerRecord: samples, byteOffset: offset))
            offset += samples * (bdf ? 3 : 2)
        }
        guard offset > 0, offset <= 1_000_000_000 else { throw EDFError.invalid("Invalid data record size") }
        if duration == 0 && signals.contains(where:{ !$0.isAnnotation }) { throw EDFError.invalid("Zero-duration records are only permitted in annotation-only EDF+") }
        let actual = (data.count - bytes) / offset
        var warnings: [String] = []
        if declared >= 0 && actual < declared && !allowGrowing { throw EDFError.invalid("Truncated file: \(declared) records declared, only \(actual) complete records found") }
        if declared == -1 { warnings.append("Record count is unspecified; using complete records from file size") }
        if (data.count - bytes) % offset != 0 { warnings.append("Incomplete trailing data record was ignored") }
        if declared >= 0 && actual > declared && !allowGrowing { warnings.append("Trailing records beyond the declared record count were ignored") }
        let count = declared < 0 || allowGrowing ? actual : min(declared, actual)
        guard count <= 20_000_000 else { throw EDFError.unsupported("Too many records for the current index") }
        let h = EDFHeader(isBDF: bdf, patient: field(8,80), recording: field(88,80), startDate: startDate,
                          reserved: field(192,44), headerBytes: bytes, declaredRecords: declared, recordCount: count,
                          recordDuration: duration, bytesPerRecord: offset, signals: signals)
        if h.isDiscontinuous && !signals.contains(where: \.isAnnotation) { throw EDFError.invalid("Discontinuous recording has no timekeeping annotation channel") }
        return (h, warnings)
    }

    public static func parseTAL(_ bytes: Data) throws -> (onset: Double?, events: [EDFAnnotation]) {
        var first: Double?; var events: [EDFAnnotation] = []
        for tal in bytes.split(separator: 0, omittingEmptySubsequences: true) {
            let parts = tal.split(separator: 20, omittingEmptySubsequences: false)
            guard parts.count >= 2 else { throw EDFError.invalid("Malformed EDF+ annotation (missing text separator)") }
            let stamp = parts[0].split(separator: 21, omittingEmptySubsequences: false)
            guard let onsetText = stamp.first, let onset = Double(String(decoding: onsetText, as: UTF8.self)), onset.isFinite, abs(onset) <= 1e12,
                  onsetText.first == 43 || onsetText.first == 45 else { throw EDFError.invalid("Malformed EDF+ annotation timestamp") }
            var duration: Double?
            if stamp.count > 1 {
                guard let d = Double(String(decoding: stamp[1], as: UTF8.self)), d.isFinite, d >= 0, d <= 1e12 else { throw EDFError.invalid("Invalid annotation duration") }
                duration = d
            }
            if first == nil { first = onset }
            for text in parts.dropFirst() where !text.isEmpty {
                guard let description = String(bytes: text, encoding: .utf8) else { throw EDFError.invalid("Annotation text is not valid UTF-8") }
                events.append(EDFAnnotation(onset: onset, duration: duration, text: description))
            }
        }
        return (first, events)
    }

    public func recordIndex(at time: Double) -> Int {
        var lo = 0, hi = recordOnsets.count
        while lo < hi { let mid = (lo + hi) / 2; if recordOnsets[mid] <= time { lo = mid + 1 } else { hi = mid } }
        return max(0, lo - 1)
    }

    public func samples(channel: Int, start: Double, duration: Double, limit: Int = 4_000_000) throws -> SampleSeries {
        guard channel >= 0, channel < header.signals.count, duration.isFinite, duration >= 0, start.isFinite else { throw EDFError.invalid("Invalid sample request") }
        let s = header.signals[channel], rate = s.sampleRate(header.recordDuration)
        guard !s.isAnnotation else { throw EDFError.invalid("Annotation channels are not waveforms") }
        let first = recordIndex(at: start), end = start + duration
        var times: [Double] = [], values: [Double] = []
        guard !recordOnsets.isEmpty else { return SampleSeries(times: [], values: [], rate: rate) }
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for r in first..<header.recordCount {
                let onset = recordOnsets[r]
                if onset >= end { break }
                let a = Int(min(Double(s.samplesPerRecord),max(0,ceil((start - onset) * rate - 1e-7))))
                let b = Int(min(Double(s.samplesPerRecord),max(0,ceil((end - onset) * rate - 1e-7))))
                if b <= a { continue }
                guard values.count + b - a <= limit else { throw EDFError.unsupported("Selection exceeds \(limit) samples. Choose a shorter interval.") }
                let base = header.headerBytes + r * header.bytesPerRecord + s.byteOffset
                for i in a..<b {
                    let p = base + i * header.bytesPerSample
                    var v = Int(raw[p]) | Int(raw[p+1]) << 8
                    if header.isBDF { v |= Int(raw[p+2]) << 16; if v & 0x800000 != 0 { v -= 0x1000000 } }
                    else if v & 0x8000 != 0 { v -= 0x10000 }
                    times.append(onset + Double(i)/rate); values.append(s.physical(v))
                }
            }
        }
        var result = SampleSeries(times: times, values: values, rate: rate)
        result.gapStarts = gapStarts(start:start,end:end)
        return result
    }

    /// Min/max envelope keeps short transients visible when zoomed out.
    public func envelope(channel: Int, start: Double, duration: Double, pixels: Int) throws -> SampleSeries {
        let rate = header.signals[channel].sampleRate(header.recordDuration)
        if duration * rate < Double(max(1,pixels) * 8) { return try samples(channel: channel, start: start, duration: duration) }
        var times: [Double] = [], values: [Double] = []
        let step = max(1/rate, duration / Double(max(1, pixels)))
        var position = start
        while position < start + duration {
            let chunk = try samples(channel: channel, start: position, duration: min(30, start + duration - position), limit: 8_000_000)
            var index = 0
            while index < chunk.values.count {
                let boundary = chunk.times[index] + step
                var minIndex = index, maxIndex = index
                var j = index + 1
                while j < chunk.values.count && chunk.times[j] < boundary {
                    if chunk.values[j] < chunk.values[minIndex] { minIndex = j }
                    if chunk.values[j] > chunk.values[maxIndex] { maxIndex = j }; j += 1
                }
                for i in [minIndex,maxIndex].sorted() { times.append(chunk.times[i]); values.append(chunk.values[i]) }
                index = j
            }
            position += min(30, start + duration - position)
        }
        var result = SampleSeries(times: times, values: values, rate: rate)
        result.gapStarts = gapStarts(start:start,end:start+duration)
        return result
    }
    private func gapStarts(start:Double,end:Double) -> [Double] {
        guard recordOnsets.count > 1 else { return [] }
        return (max(1,recordIndex(at:start))..<recordOnsets.count).prefix { recordOnsets[$0] < end }.compactMap { i in
            recordOnsets[i] > recordOnsets[i-1]+header.recordDuration+1e-6 && recordOnsets[i] >= start ? recordOnsets[i] : nil
        }
    }
}
