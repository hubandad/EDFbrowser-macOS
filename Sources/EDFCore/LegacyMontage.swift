import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

private final class MontageNode {
    var name:String
    var text = ""
    var children:[MontageNode] = []
    init(_ name:String) { self.name = name }
    func value(_ key:String) -> String { children.first { $0.name == key }?.text.trimmingCharacters(in:.whitespacesAndNewlines) ?? "" }
    func nodes(_ key:String) -> [MontageNode] { children.filter { $0.name == key } }
}
private final class MontageParser: NSObject,XMLParserDelegate {
    var root:MontageNode?
    var stack:[MontageNode] = []
    func parser(_ parser:XMLParser,didStartElement elementName:String,namespaceURI:String?,qualifiedName qName:String?,attributes attributeDict:[String:String]) {
        let node = MontageNode(elementName)
        if let parent = stack.last { parent.children.append(node) } else { root = node }; stack.append(node)
    }
    func parser(_ parser:XMLParser,foundCharacters string:String) { stack.last?.text += string }
    func parser(_ parser:XMLParser,didEndElement elementName:String,namespaceURI:String?,qualifiedName qName:String?) { _ = stack.popLast() }
}

public struct LegacyMontageResult: Sendable {
    public var traces:[Trace]
    public var page:Double?
    public var notes:[String]
}
public enum LegacyMontage {
    public static func read(url:URL,file:EDFFile) throws -> LegacyMontageResult {
        let data = try Data(contentsOf:url)
        guard data.count <= 4_000_000, !String(decoding:data,as:UTF8.self).uppercased().contains("<!DOCTYPE") else { throw EDFError.invalid("Invalid montage XML size or document type") }
        let parser = XMLParser(data:data), delegate = MontageParser(); parser.delegate = delegate; parser.shouldResolveExternalEntities = false
        guard parser.parse(), let root = delegate.root, root.name == "EDFbrowser_montage" else { throw EDFError.invalid("Not an EDFBrowser XML montage") }
        var traces:[Trace] = [], notes:[String] = []
        for node in root.nodes("signalcomposition") {
            var components:[TraceComponent] = []
            for source in node.nodes("signal") {
                let signal: EDFSignal?
                if let index = Int(source.value("edfindex")) { signal = file.signalChannels.first { $0.id == index } }
                else {
                    let matches = file.signalChannels.filter { $0.label == source.value("label") }
                    guard matches.count == 1 else { throw EDFError.invalid("Montage signal label missing or ambiguous: \(source.value("label"))") }
                    signal = matches[0]
                }
                guard let signal, let factor = Double(source.value("factor")), factor.isFinite, abs(factor) >= 0.001, abs(factor) <= 128 else { throw EDFError.invalid("Invalid montage signal/factor") }
                components.append(TraceComponent(channel:signal.id,factor:factor))
            }
            guard let first = components.first, components.count == Int(node.value("num_of_signals")) else { throw EDFError.invalid("Montage signal count does not match components") }
            var trace = Trace(sourceID:file.id,channel:first.channel,label:node.value("alias"),colorIndex:traces.count%8)
            trace.components = components; trace.inverted = node.value("polarity") == "-1"
            if trace.label.isEmpty { trace.label = components.map { "\($0.factor < 0 ? "−" : "+")\(file.header.signals[$0.channel].label)" }.joined(separator:" ").trimmingCharacters(in:CharacterSet(charactersIn:"+ ")) }
            if let value = Double(node.value("voltpercm")), value.isFinite, value > 0 { trace.physicalPerCM = value }
            var specs:[String] = []
            for filter in node.nodes("fidfilter") {
                guard let type = Int(filter.value("type")), (0...4).contains(type), let frequency = Double(filter.value("frequency")), frequency > 0,
                      let order = Int(filter.value("order")), (1...100).contains(order), let model = Int(filter.value("model")), (0...2).contains(model) else { throw EDFError.invalid("Invalid imported filter") }
                let rate = file.header.signals[first.channel].sampleRate(file.header.recordDuration)
                guard frequency < rate/2, frequency.isFinite else { throw EDFError.invalid("Imported cutoff exceeds Nyquist") }
                let family = ["Bu","Ch","Be"][model], prefix = ["Hp","Lp","Bs","Bp","Bs"][type]
                if type == 2 { specs.append("BsRe/\(order)/\(frequency)"); continue }
                guard order <= 8 else { throw EDFError.unsupported("Imported IIR filter order above 8 is not supported") }
                let ripple = abs(Double(filter.value("ripple")) ?? 1)
                let suffix = model == 1 ? "/-\(ripple)" : ""
                if type >= 3 {
                    guard let frequency2 = Double(filter.value("frequency2")), frequency2 > frequency, frequency2 < rate/2 else { throw EDFError.invalid("Invalid imported band filter") }
                    specs.append("\(prefix)\(family)\(order)\(suffix)/\(frequency)-\(frequency2)")
                } else { specs.append("\(prefix)\(family)\(order)\(suffix)/\(frequency)") }
            }
            for filter in node.nodes("filter") {
                guard let frequency = Double(filter.value("frequency")), frequency > 0 else { throw EDFError.invalid("Invalid first-order filter") }
                specs.append("\(filter.value("LPF") == "1" ? "Lp" : "Hp")Bu1/\(frequency)")
            }
            trace.filters.extraSpecifications = specs
            let fir = node.nodes("fir_filter")
            guard fir.count <= 1 else { throw EDFError.unsupported("Multiple cascaded FIR stages are not supported by this importer") }
            if let f = fir.first {
                let taps = f.nodes("tap").compactMap { Double($0.text) }
                guard taps.count == Int(f.value("size")), taps.count <= 4095, taps.allSatisfy(\.isFinite) else { throw EDFError.invalid("Invalid imported FIR taps") }; trace.filters.firTaps = taps
            }
            let averages = node.nodes("ravg_filter")
            guard averages.count <= 1 else { throw EDFError.unsupported("Multiple moving-average stages are not supported by this importer") }
            if let f = averages.first {
                guard f.value("type") == "1", let size = Int(f.value("size")), (2...10000).contains(size) else { throw EDFError.unsupported("Only low-pass moving average is supported by this importer") }; trace.filters.movingAverage = size
            }
            if let plif = node.nodes("plif_eeg_filter").first, let frequency = Int(plif.value("plf")) { trace.filters.powerline = frequency }
            let unsupported = ["spike_filter","math_func_before","math_func_after","plif_ecg_filter","ecg_filter","zratio_filter"]
            for key in unsupported where !node.nodes(key).isEmpty { throw EDFError.unsupported("Montage includes an unsupported imported processing stage: \(key). Remove it in the original montage before importing.") }
            if !node.value("screen_offset").isEmpty { notes.append("Original pixel offsets are replaced by the native stacked layout") }
            traces.append(trace)
        }
        guard !traces.isEmpty else { throw EDFError.invalid("Montage contains no signal compositions") }
        let page = Double(root.value("pagetime")).map { $0/10_000_000 }
        return LegacyMontageResult(traces:traces,page:page,notes:Array(Set(notes)))
    }
}
