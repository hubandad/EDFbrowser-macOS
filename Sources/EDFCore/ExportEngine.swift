import Foundation

public enum ExportEngine {
    public static func export(file: EDFFile, traces: [Trace], annotations: [EDFAnnotation], start: Double, duration: Double,
                              targetRate: Int?, bdf: Bool, filtered: Bool, physicalLimit:Double? = nil, to url: URL) throws {
        guard url.standardizedFileURL != file.url.standardizedFileURL else { throw EDFError.invalid("Export must use a new file") }
        guard start >= 0, duration > 0, start+duration <= file.duration+1e-6, !traces.isEmpty else { throw EDFError.invalid("Invalid export interval or no selected signals") }
        for i in 1..<file.recordOnsets.count {
            let previousEnd = file.recordOnsets[i-1]+file.header.recordDuration
            if file.recordOnsets[i] > previousEnd+1e-6 && previousEnd < start+duration && file.recordOnsets[i] > start {
                throw EDFError.invalid("Export crosses a recording gap. Save an annotated copy to preserve EDF+D, or choose a continuous interval.")
            }
        }
        var effective = traces
        if !filtered { for i in effective.indices { effective[i].filters = FilterSettings() } }
        let signals = try effective.map { t -> EDFOutputSignal in
            let s = file.header.signals[t.channel], sourceRate = s.sampleRate(file.header.recordDuration)
            let rate = targetRate ?? Int(sourceRate.rounded())
            guard targetRate != nil || abs(sourceRate-Double(rate)) < 1e-6 else { throw EDFError.unsupported("Fractional sample rate: select an integer output sample rate") }
            let reference = t.reference.map { file.header.signals[$0] }
            func magnitude(_ channel:EDFSignal) -> Double { max(abs(channel.physicalMin),abs(channel.physicalMax))*(channel.microvoltScale ?? 1)/(s.microvoltScale ?? 1) }
            var bounds = magnitude(s) + (reference.map(magnitude) ?? (t.averageReference ? file.signalChannels.filter {$0.label.uppercased().contains("EEG")}.map(magnitude).max() ?? magnitude(s) : 0))
            if let components = t.components { bounds = components.reduce(0) { $0+abs($1.factor)*magnitude(file.header.signals[$1.channel]) } }
            let limit = physicalLimit ?? bounds*1.1
            guard limit.isFinite, limit > 0 else { throw EDFError.invalid("Invalid physical amplitude limit") }
            return EDFOutputSignal(label:t.label,unit:s.unit,rate:rate,minimum:-limit,maximum:limit,prefilter:filtered ? t.filters.summary : s.prefilter)
        }
        // Preserve fractional start time through the mandatory EDF+ timekeeping TAL.
        let absoluteStart = file.header.startDate.addingTimeInterval(start)
        let fractional = absoluteStart.timeIntervalSince1970 - floor(absoluteStart.timeIntervalSince1970)
        let events = annotations.compactMap { e -> EDFAnnotation? in
            let eventEnd = e.onset + (e.duration ?? 0)
            guard eventEnd >= start, e.onset < start+duration else { return nil }
            let onset = max(start,e.onset)
            return EDFAnnotation(onset:onset-start,duration:e.duration.map { _ in max(0,min(start+duration,eventEnd)-onset) },text:e.text)
        }
        let stamp = EDFDate.calendar.dateComponents([.year,.month,.day],from:absoluteStart)
        let months = ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"]
        let dateText = String(format:"%02d-%@-%04d",stamp.day!,months[stamp.month!-1],stamp.year!)
        var recordingParts = file.header.recording.split(separator:" ").map(String.init)
        if recordingParts.count >= 2 && recordingParts[0] == "Startdate" { recordingParts[1] = dateText }
        let recording = recordingParts.joined(separator:" ")
        try EDFWriter.write(to:url,signals:signals,duration:duration,bdf:bdf,patient:file.header.patient,recording:recording,date:absoluteStart,annotations:events,startOffset:fractional) { i,record,count in
            let trace = effective[i], rate = Double(signals[i].rate), sourceRate = file.header.signals[trace.channel].sampleRate(file.header.recordDuration)
            let position = start+Double(record)
            if abs(sourceRate-rate) < 1e-6 {
                let values = try SignalEngine.read(trace:trace,file:file,start:position,duration:Double(count)/rate).values
                guard values.count >= count else { throw EDFError.invalid("Incomplete samples at export boundary") }; return Array(values.prefix(count))
            }
            // Read a margin on both sides so the sinc kernel does not restart at each output record.
            let margin = 2.0, readStart = max(0,position-margin)
            let series = try SignalEngine.read(trace:trace,file:file,start:readStart,duration:min(file.duration-readStart,Double(count)/rate + position-readStart+margin))
            return try resample(series:series,positions:(0..<count).map { position+Double($0)/rate },targetRate:rate)
        }
    }
    public static func resample(series: SampleSeries, positions: [Double], targetRate: Double) throws -> [Double] {
        guard let origin = series.times.first, !series.values.isEmpty else { throw EDFError.invalid("No samples at export position") }
        let ratio = min(1,targetRate/series.rate)*0.94, radius = min(512,max(24,Int(ceil(24/ratio))))
        return positions.map { t in
            let p = (t-origin)*series.rate, center = Int(p.rounded(.down))
            var sum = 0.0, weight = 0.0
            let lower = max(0,center-radius), upper = min(series.values.count-1,center+radius)
            guard lower <= upper else { return .nan }
            for j in lower...upper {
                let x = p-Double(j), z = Double.pi*x*ratio
                let w = ratio*(abs(z)<1e-10 ? 1 : sin(z)/z)*(0.5+0.5*cos(Double.pi*x/Double(radius+1)))
                sum += series.values[j]*w; weight += w
            }
            return abs(weight)>1e-12 ? sum/weight : .nan
        }
    }
}
