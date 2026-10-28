import Foundation

public enum SignalEngine {
    public static func read(trace: Trace, file: EDFFile, start: Double, duration: Double, envelopePixels: Int? = nil) throws -> SampleSeries {
        guard trace.channel >= 0, trace.channel < file.header.signals.count, !file.header.signals[trace.channel].isAnnotation else { throw EDFError.invalid("Montage refers to a missing or annotation channel") }
        if let pixels = envelopePixels, !trace.filters.isActive, trace.reference == nil, !trace.averageReference, trace.components == nil {
            var result = try file.envelope(channel: trace.channel,start: start,duration: duration,pixels:pixels)
            if trace.inverted { result.values = result.values.map { -$0 } }; return result
        }
        let rate = file.header.signals[trace.channel].sampleRate(file.header.recordDuration)
        var cutoff = [trace.filters.highPass,trace.filters.lowPass].filter { $0 > 0 }.min() ?? 1000
        for spec in trace.filters.extraSpecifications ?? [] where spec.hasPrefix("Hp") || spec.hasPrefix("Lp") || spec.hasPrefix("Bp") {
            if let last = spec.split(separator:"/").last {
                let frequency = Double(last) ?? Double(last.split(separator:"-").first ?? "") ?? 1000
                if frequency > 0 { cutoff = min(cutoff,frequency) }
            }
        }
        let bufferWarmup = max(Double(trace.filters.firTaps.count)/rate,Double(trace.filters.movingAverage)/rate)
        let warmup = trace.filters.isActive ? max(10,12/cutoff,bufferWarmup) : 0
        let readStart = max(0,start-warmup)
        var s = try file.samples(channel:trace.channel,start:readStart,duration:duration+start-readStart)
        let signal = file.header.signals[trace.channel]
        if let components = trace.components {
            var sum = [Double](repeating:0,count:s.values.count)
            for component in components {
                guard file.header.signals.indices.contains(component.channel), !file.header.signals[component.channel].isAnnotation else { throw EDFError.invalid("Missing montage component") }
                let other = file.header.signals[component.channel]
                guard other.samplesPerRecord == signal.samplesPerRecord else { throw EDFError.invalid("Montage component sample rates differ") }
                let factor: Double
                if other.unit == signal.unit { factor = component.factor }
                else if let a = other.microvoltScale, let b = signal.microvoltScale { factor = component.factor*a/b }
                else { throw EDFError.invalid("Montage component units differ") }
                let values = try file.samples(channel:component.channel,start:readStart,duration:duration+start-readStart).values
                guard values.count == sum.count else { throw EDFError.invalid("Montage alignment differs") }
                for i in sum.indices { sum[i] += values[i]*factor }
            }
            s.values = sum
        }
        let references: [Int]
        if trace.averageReference { references = file.signalChannels.filter { $0.label.uppercased().contains("EEG") && $0.id != trace.channel }.map(\.id) }
        else { references = trace.reference.map { [$0] } ?? [] }
        if trace.averageReference && references.isEmpty { throw EDFError.invalid("No other EEG channels for average reference") }
        if !references.isEmpty {
            var sum = [Double](repeating:0,count:s.values.count)
            for channel in references {
                guard file.header.signals.indices.contains(channel), !file.header.signals[channel].isAnnotation else { throw EDFError.invalid("Missing reference channel") }
                let ref = file.header.signals[channel]
                guard ref.samplesPerRecord == signal.samplesPerRecord else { throw EDFError.invalid("Derivation channels must have equal sample rates") }
                let factor: Double
                if ref.unit == signal.unit { factor = 1 }
                else if let r = ref.microvoltScale, let p = signal.microvoltScale { factor = r/p }
                else { throw EDFError.invalid("Derivation channels have incompatible physical units") }
                let r = try file.samples(channel:channel,start:readStart,duration:duration+start-readStart)
                guard r.values.count == s.values.count else { throw EDFError.invalid("Reference sample alignment differs") }
                for i in sum.indices { sum[i] += r.values[i]*factor }
            }
            // Average reference includes the selected EEG channel itself.
            let denominator = Double(references.count + (trace.averageReference ? 1 : 0))
            for i in sum.indices { s.values[i] -= (sum[i] + (trace.averageReference ? s.values[i] : 0))/denominator }
        }
        s = try DSP.filter(s,settings:trace.filters)
        let first = s.times.firstIndex { $0 >= start-1e-7 } ?? s.times.count
        s.times = Array(s.times.dropFirst(first)); s.values = Array(s.values.dropFirst(first))
        if trace.inverted { s.values = s.values.map { -$0 } }
        return s
    }
}
