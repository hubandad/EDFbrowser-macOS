import Foundation

public enum CSV {
    public static func escape(_ text: String) -> String {
        text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
    }
    public static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], value = "", quoted = false
        let chars = Array(text); var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i+1 < chars.count && chars[i+1] == "\"" { value.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if c == "," && !quoted { row.append(value); value = "" }
            else if (c == "\n" || c == "\r\n" || c == "\r") && !quoted {
                row.append(value); if !row.allSatisfy(\.isEmpty) { rows.append(row) }; row = []; value = ""
            } else { value.append(c) }
            i += 1
        }
        guard !quoted else { throw EDFError.invalid("Unclosed CSV quotation") }
        if !value.isEmpty || !row.isEmpty { row.append(value); rows.append(row) }
        return rows
    }
    public static func annotations(from url: URL) throws -> [EDFAnnotation] {
        let rows = try parse(String(contentsOf: url, encoding: .utf8))
        return try rows.enumerated().compactMap { index,row in
            guard row.count >= 3 else { if row.isEmpty { return nil }; throw EDFError.invalid("Annotation CSV needs onset,duration,description columns") }
            if index == 0, Double(row[0]) == nil { return nil }
            guard let onset = Double(row[0]), onset.isFinite else { throw EDFError.invalid("Invalid annotation onset on row \(index+1)") }
            let duration = row[1].isEmpty ? nil : Double(row[1])
            if !row[1].isEmpty && (duration == nil || !duration!.isFinite || duration! < 0) { throw EDFError.invalid("Invalid duration on row \(index+1)") }
            return EDFAnnotation(onset: onset, duration: duration, text: row[2])
        }
    }
    public static func writeAnnotations(_ annotations: [EDFAnnotation], to url: URL) throws {
        let text = "onset,duration,description\n" + annotations.sorted { $0.onset < $1.onset }.map {
            "\($0.onset),\($0.duration.map(String.init(describing:)) ?? ""),\(escape($0.text))"
        }.joined(separator: "\n") + "\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    public static func export(_ file: EDFFile, channels: [Int], range: Range<Double>, to url: URL) throws {
        try EDFWriter.atomicWrite(to: url) { output in
            try output.write(contentsOf: Data("time,signal,value,unit\n".utf8))
            var time = range.lowerBound
            while time < range.upperBound {
                let length = min(10,range.upperBound-time)
                for channel in channels {
                    let s = file.header.signals[channel], series = try file.samples(channel: channel,start: time,duration: length)
                    var text = ""
                    for i in series.values.indices { text += "\(series.times[i]),\(escape(s.label)),\(series.values[i]),\(escape(s.unit))\n" }
                    try output.write(contentsOf: Data(text.utf8))
                }
                time += length
            }
        }
    }
    public static func importSignals(from url: URL, to destination: URL, defaultRate: Int = 256, unit: String = "uV") throws {
        let rows = try parse(String(contentsOf: url,encoding: .utf8))
        guard rows.count > 1 else { throw EDFError.invalid("CSV has no signal data") }
        let headings = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        var labels: [String] = [], units: [String] = [], arrays: [[Double]] = [], times: [[Double]] = [], rates: [Int] = []
        if headings.prefix(3).elementsEqual(["time","signal","value"]) {
            var indices: [String:Int] = [:]
            for (i,row) in rows.dropFirst().enumerated() {
                guard row.count >= 3, let t = Double(row[0]), let v = Double(row[2]), t.isFinite, v.isFinite else { throw EDFError.invalid("Invalid signal CSV row \(i+2)") }
                let label = row[1]
                let idx: Int
                if let existing = indices[label] { idx = existing } else {
                    idx = labels.count; indices[label] = idx; labels.append(label); units.append(row.count > 3 ? row[3] : unit); arrays.append([]); times.append([])
                }
                arrays[idx].append(v); times[idx].append(t)
            }
        } else {
            let hasTime = ["time","seconds","timestamp"].contains(headings[0]), start = hasTime ? 1 : 0
            let hasHeader = rows[0].dropFirst(start).contains { Double($0) == nil }
            let dataRows = hasHeader ? Array(rows.dropFirst()) : rows
            let columns = rows[0].count-start
            guard columns > 0, defaultRate > 0 else { throw EDFError.invalid("No signal columns or invalid sample rate") }
            labels = (0..<columns).map { hasHeader ? rows[0][$0+start] : "Signal \($0+1)" }; units = labels.map { _ in unit }
            arrays = labels.map { _ in [] }; times = arrays
            for (i,row) in dataRows.enumerated() {
                guard row.count == columns+start else { throw EDFError.invalid("Inconsistent CSV column count on row \(i+1)") }
                let t = hasTime ? Double(row[0]) : Double(i)/Double(defaultRate)
                guard let time = t, time.isFinite else { throw EDFError.invalid("Invalid CSV time") }
                for j in 0..<columns {
                    guard let v = Double(row[j+start]), v.isFinite else { throw EDFError.invalid("Invalid CSV signal value on row \(i+1)") }
                    arrays[j].append(v); times[j].append(time)
                }
            }
        }
        guard !arrays.isEmpty else { throw EDFError.invalid("No CSV signal samples") }
        let origin = times[0].first ?? 0
        for t in times {
            guard t.count >= 2, abs((t.first ?? 0)-origin) < 1e-6 else { throw EDFError.invalid("CSV signals must have at least two samples and the same start time") }
            let rate = 1/(t[1]-t[0]), rounded = rate.rounded()
            guard rate.isFinite, rate > 0, rate <= 1_000_000, abs(rate-rounded) < 0.001,
                  t.enumerated().allSatisfy({ abs($0.element-origin-Double($0.offset)/rounded) < 1e-5 }) else {
                throw EDFError.invalid("CSV time must be uniformly sampled at an integer Hz rate without gaps")
            }
            rates.append(Int(rounded))
        }
        let durations = arrays.indices.map { Double(arrays[$0].count)/Double(rates[$0]) }
        guard let duration = durations.min(), durations.allSatisfy({ abs($0-duration) < 1e-5 }) else { throw EDFError.invalid("CSV signal durations differ") }
        let signals = arrays.indices.map { i -> EDFOutputSignal in
            let low = arrays[i].min()!, high = arrays[i].max()!, margin = max(1e-3,(high-low)*0.01)
            return EDFOutputSignal(label: labels[i],unit: units[i],rate: rates[i],minimum: low-margin,maximum: high+margin)
        }
        try EDFWriter.write(to: destination,signals: signals,duration: duration,annotations: [EDFAnnotation(onset: 0,text: "Imported from CSV; time origin \(origin)s")]) { i,record,count in
            Array(arrays[i][record*rates[i]..<(record*rates[i]+count)])
        }
    }
}
