import Foundation
import CDSP

public struct Spectrum: Sendable {
    public var frequency: [Double]
    public var power: [Double]
    public var resolution: Double
}

public enum DSP {
    private static let filterLock = NSLock()
    public static func specification(_ input: [Double], rate: Double, spec: String) throws -> [Double] {
        var values = input, error = [CChar](repeating:0,count:1024)
        filterLock.lock(); defer { filterLock.unlock() }
        guard em_filter(&values,Int32(values.count),rate,spec,&error,Int32(error.count)) == 0 else { throw EDFError.invalid(String(cString:error)) }
        return values
    }
    public static func aEEG(_ input: [Double], rate: Double) throws -> [Double] {
        guard rate > 30 else { throw EDFError.invalid("aEEG requires sampling above 30 Hz") }
        let band = try specification(input,rate:rate,spec:"BpBu8/2-15")
        return try specification(band.map(abs),rate:rate,spec:"LpBu4/0.5")
    }
    public static func filter(_ input: SampleSeries, settings: FilterSettings) throws -> SampleSeries {
        guard settings.isActive, !input.values.isEmpty else { return input }
        guard (1...8).contains(settings.order), settings.highPass >= 0, settings.lowPass >= 0, settings.notch >= 0,
              [settings.highPass,settings.lowPass,settings.notch].allSatisfy({ $0 < input.rate/2 }),
              settings.lowPass == 0 || settings.highPass < settings.lowPass,
              settings.notchQ.isFinite, settings.notchQ > 0 else { throw EDFError.invalid("Filter cutoff must be below Nyquist and HP must be below LP") }
        var result = input
        var ranges: [Range<Int>] = []; var start = 0
        for i in 1..<max(1,input.times.count) where input.times[i] - input.times[i-1] > 1.5/input.rate {
            ranges.append(start..<i); start = i
        }
        ranges.append(start..<input.values.count)
        for range in ranges where !range.isEmpty {
            var values = Array(input.values[range])
            var specs: [String] = []
            let model = settings.family == "Bessel" ? "Be" : settings.family == "Chebyshev" ? "Ch" : "Bu"
            let suffix = model == "Ch" ? "/-\(settings.ripple)" : ""
            if settings.highPass > 0 { specs.append("Hp\(model)\(settings.order)\(suffix)/\(settings.highPass)") }
            if settings.lowPass > 0 { specs.append("Lp\(model)\(settings.order)\(suffix)/\(settings.lowPass)") }
            if settings.notch > 0 { specs.append("BsRe/\(settings.notchQ)/\(settings.notch)") }
            specs += settings.extraSpecifications ?? []
            for spec in specs {
                var error = [CChar](repeating: 0, count: 1024)
                filterLock.lock()
                let status = em_filter(&values, Int32(values.count), input.rate, spec, &error, Int32(error.count))
                filterLock.unlock()
                guard status == 0 else { throw EDFError.invalid("Filter: " + String(cString: error)) }
            }
            if settings.powerline > 0 {
                guard abs(input.rate-input.rate.rounded()) < 1e-6,
                      em_powerline(&values, Int32(values.count), Int32(input.rate), Int32(settings.powerline)) == 0 else { throw EDFError.invalid("Powerline subtraction requires a supported integer sample rate") }
            }
            if settings.movingAverage > 1 {
                guard settings.movingAverage <= 10000, em_average(&values,Int32(values.count),Int32(settings.movingAverage),settings.movingAverageHighPass == true ? 1 : 0) == 0 else { throw EDFError.invalid("Invalid moving-average filter size") }
            }
            if let velocity = settings.spikeVelocity, velocity > 0 {
                guard velocity.isFinite, input.rate >= 4000, input.rate <= 128000, (10...1000).contains(settings.spikeHoldoff ?? 100), em_spike(&values,Int32(values.count),Int32(input.rate),velocity,Int32(settings.spikeHoldoff ?? 100)) == 0 else { throw EDFError.invalid("Spike filter requires 4000–128000 Hz and holdoff of 10–1000 ms") }
            }
            if !settings.firTaps.isEmpty {
                let raw = values
                for i in raw.indices { var v = 0.0; for j in 0..<min(i+1,settings.firTaps.count) { v += raw[i-j]*settings.firTaps[j] }; values[i] = v }
            }
            result.values.replaceSubrange(range, with: values)
        }
        return result
    }

    public static func spectrum(_ values: [Double], rate: Double, blockSize: Int = 1024, window: String = "Hann", overlap: Double = 0.5) throws -> Spectrum {
        let n = min(blockSize, values.count) / 2 * 2
        guard n >= 4, rate > 0, overlap >= 0, overlap < 1, values.allSatisfy(\.isFinite) else { throw EDFError.invalid("Not enough samples for the spectrum") }
        let weights = (0..<n).map { i -> Double in
            let x = 2 * Double.pi * Double(i) / Double(n-1)
            switch window { case "Rectangular": return 1; case "Hamming": return 0.54-0.46*cos(x); case "Blackman": return 0.42-0.5*cos(x)+0.08*cos(2*x); default: return 0.5-0.5*cos(x) }
        }
        let normalization = rate * weights.reduce(0) { $0 + $1*$1 }
        var power = [Double](repeating: 0,count: n/2+1), blocks = 0
        let step = max(1,Int(Double(n)*(1-overlap)))
        for a in stride(from: 0, through: values.count-n, by: step) {
            let mean = values[a..<(a+n)].reduce(0,+)/Double(n)
            var input = [Double](repeating: 0,count: n)
            for i in 0..<n { input[i] = (values[a+i]-mean)*weights[i] }
            var re = power.map { _ in 0.0 }, im = re
            guard em_fft(&input, Int32(n), &re, &im) == 0 else { throw EDFError.invalid("FFT allocation failed") }
            for k in power.indices { power[k] += (re[k]*re[k]+im[k]*im[k]) / normalization * (k == 0 || k == n/2 ? 1 : 2) }
            blocks += 1
        }
        return Spectrum(frequency: power.indices.map { Double($0)*rate/Double(n) }, power: power.map { $0/Double(blocks) }, resolution: rate/Double(n))
    }
    public static func resample(_ values: [Double], from sourceRate: Double, to targetRate: Double, count: Int? = nil) throws -> [Double] {
        guard sourceRate > 0, targetRate > 0, sourceRate.isFinite, targetRate.isFinite, !values.isEmpty else { return [] }
        let outputCount = count ?? Int((Double(values.count)*targetRate/sourceRate).rounded(.down))
        guard outputCount >= 0, outputCount < 20_000_000 else { throw EDFError.invalid("Invalid resampling size") }
        let ratio = min(1,targetRate/sourceRate)*0.94, radius = min(512,max(24,Int(ceil(24/ratio))))
        return (0..<outputCount).map { i in
            let position = Double(i)*sourceRate/targetRate, center = Int(position)
            var sum = 0.0, weight = 0.0
            for j in max(0,center-radius)...min(values.count-1,center+radius) {
                let x = position-Double(j), z = Double.pi*x*ratio
                let sinc = abs(z) < 1e-10 ? 1 : sin(z)/z
                let w = ratio*sinc*(0.5+0.5*cos(Double.pi*x/Double(radius+1)))
                sum += values[j]*w; weight += w
            }
            return abs(weight) > 1e-12 ? sum/weight : values[min(values.count-1,center)]
        }
    }
    public static func fir(low: Double, high: Double, rate: Double, taps: Int = 129) throws -> [Double] {
        guard taps >= 3, taps <= 4095, taps % 2 == 1, low >= 0, high > low, high < rate/2 else { throw EDFError.invalid("FIR requires odd tap count and 0 ≤ low < high < Nyquist") }
        let middle = taps/2
        func lp(_ f: Double,_ x: Int) -> Double { x == 0 ? 2*f/rate : sin(2*Double.pi*f*Double(x)/rate)/(Double.pi*Double(x)) }
        var coefficients = (0..<taps).map { i in (lp(high,i-middle) - lp(low,i-middle))*(0.54-0.46*cos(2*Double.pi*Double(i)/Double(taps-1))) }
        let omega = 2*Double.pi*(low == 0 ? 0 : (low+high)/2)/rate
        let gain = coefficients.enumerated().reduce(0.0) { $0 + $1.element*cos(omega*Double($1.offset-middle)) }
        if abs(gain) > 1e-10 { for i in coefficients.indices { coefficients[i] /= gain } }
        return coefficients
    }
    public static func parksMcClellan(low:Double,high:Double,rate:Double,transition:Double) throws -> [Double] {
        guard low >= 0, high > low, transition > 0, high+transition < rate/2, low == 0 || low > transition else { throw EDFError.invalid("Transition bands must lie within 0…Nyquist and below the low cutoff") }
        var coefficients = [Double](repeating:0,count:4095)
        let n = em_remez(rate,low,high,transition,&coefficients,Int32(coefficients.count))
        guard n > 0 else { throw EDFError.invalid("Parks–McClellan design failed (\(n)); widen the transition band") }
        return Array(coefficients.prefix(Int(n)))
    }
    public static func zRatio(_ values:[Double],rate:Double,crossover:Double = 7.5) throws -> Double {
        guard rate >= 100, crossover >= 5, crossover <= 9.5 else { throw EDFError.invalid("Z-ratio requires ≥100 Hz and crossover 5–9.5 Hz") }
        let spectrum = try spectrum(values,rate:rate,blockSize:Int(rate*2),window:"Rectangular",overlap:0)
        var low = 0.0, high = 0.0
        for i in spectrum.frequency.indices {
            let f = spectrum.frequency[i]
            if f >= 0.5 && f < crossover { low += spectrum.power[i] }
            if f >= crossover && f <= 25 { high += spectrum.power[i] }
        }
        return low+high > 0 ? (low-high)/(low+high) : 0
    }
    public static func qrs(_ series: SampleSeries, microvoltScale: Double) throws -> [Double] {
        guard series.rate >= 200 else { throw EDFError.invalid("Pan–Tompkins detector requires at least 200 Hz") }
        var result: [Double] = []; var first = 0
        let boundaries = (1..<max(1,series.times.count)).filter { series.times[$0]-series.times[$0-1] > 1.5/series.rate } + [series.times.count]
        for end in boundaries where end > first {
            let input = Array(series.values[first..<end]); var beats = [Double](repeating: 0,count: input.count/20+1)
            let count = em_qrs(input,Int32(input.count),series.rate,microvoltScale,&beats,Int32(beats.count))
            guard count >= 0 else { throw EDFError.invalid("Could not initialize QRS detector") }
            result += beats.prefix(Int(count)).map { $0+series.times[first] }; first = end
        }
        return result.filter { $0 >= (series.times.first ?? 0) }
    }
    public static func statistics(_ values: [Double]) -> [String: Double] {
        guard !values.isEmpty else { return [:] }
        let mean = values.reduce(0,+)/Double(values.count)
        let variance = values.reduce(0) { $0+pow($1-mean,2) }/Double(values.count)
        return ["Count":Double(values.count),"Mean":mean,"SD":sqrt(variance),"RMS":sqrt(values.reduce(0){$0+$1*$1}/Double(values.count)),"Minimum":values.min()!,"Maximum":values.max()!,"Peak-to-peak":values.max()!-values.min()!]
    }
}
