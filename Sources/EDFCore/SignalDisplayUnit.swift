import Foundation

/// Presentation conversion only. Source samples, calibration and EDF exports retain their original unit.
public struct SignalDisplayUnit: Equatable, Sendable {
    public let symbol: String
    public let multiplier: Double
    public let isVoltage: Bool

    public init(sourceUnit: String) {
        let original = sourceUnit.trimmingCharacters(in:.whitespacesAndNewlines)
        let normalized = original.lowercased().replacingOccurrences(of:"µ",with:"u").replacingOccurrences(of:"μ",with:"u").replacingOccurrences(of:" ",with:"")
        switch normalized {
        case "uv": multiplier = 1; isVoltage = true; symbol = "μV"
        case "mv": multiplier = 1000; isVoltage = true; symbol = "μV"
        case "v": multiplier = 1_000_000; isVoltage = true; symbol = "μV"
        default: multiplier = 1; isVoltage = false; symbol = original.isEmpty ? "a.u." : original
        }
    }

    public func value(_ sourceValue: Double) -> Double { sourceValue*multiplier }

    public func series(_ source: SampleSeries) -> SampleSeries {
        guard multiplier != 1 else { return source }
        var displayed = source
        displayed.values = source.values.map { $0*multiplier }
        return displayed
    }
}
