import Foundation
import EDFCore
import CDSP

struct CheckFailure: Error, CustomStringConvertible { var description:String }
func check(_ condition:@autoclosure () throws -> Bool,_ label:String) throws { if try !condition() { throw CheckFailure(description:label) } }
func near(_ a:Double,_ b:Double,_ epsilon:Double = 1e-6) -> Bool { abs(a-b) <= epsilon }
func expectFailure(_ label:String,_ body:() throws -> Void) throws {
    do { try body() } catch { return }; throw CheckFailure(description:"Expected rejection: \(label)")
}
if let i = CommandLine.arguments.firstIndex(of:"--units-demo"), i+1 < CommandLine.arguments.count {
    let signals = [EDFOutputSignal(label:"EEG uV",unit:"uV",rate:256,minimum:-1000,maximum:1000),
                   EDFOutputSignal(label:"EEG mV",unit:"mV",rate:256,minimum:-1,maximum:1),
                   EDFOutputSignal(label:"EEG V",unit:"V",rate:256,minimum:-0.001,maximum:0.001)]
    let multipliers = [1.0,1000,1_000_000]
    try EDFWriter.write(to:URL(fileURLWithPath:CommandLine.arguments[i+1]),signals:signals,duration:30,patient:"X X X Synthetic",annotations:[.init(onset:0,text:"Synthetic unit check: identical 50 microvolt peak signals")]) { channel,record,count in
        (0..<count).map { 50*sin(2*Double.pi*(Double(record)+Double($0)/256))/multipliers[channel] }
    }
    print("Synthetic uV / mV / V display fixture generated.")
    exit(0)
}
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EDFCoreCheck-\(UUID().uuidString)")
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
defer { try? FileManager.default.removeItem(at:folder) }
func path(_ name:String) -> URL { folder.appendingPathComponent(name) }
var passed = 0, failed = 0
func test(_ name:String,_ body:() throws -> Void) {
    do { try body(); passed += 1; print("PASS \(name)") } catch { failed += 1; print("FAIL \(name): \(error)") }
}

let demoURL = path("demo.edf")
try Demo.generate(to:demoURL,duration:90)
let demo = try EDFFile(url:demoURL)
test("EDF+ mixed-rate sample counts and calibration") {
    try check(demo.signalChannels.count == 12,"channel count")
    try check(near(demo.duration,90),"duration")
    try check(try demo.samples(channel:0,start:1,duration:2).values.count == 512,"EEG sample count")
    try check(try demo.samples(channel:11,start:1,duration:2).values.count == 2,"SpO2 sample count")
    try check(demo.annotations.filter { $0.sleepStage != nil }.count == 3,"sleep stages")
}
test("Independent EDFlib accepts native EDF+ output") {
    var h = edflib_hdr_t(); let status = demoURL.path.withCString { edfopen_file_readonly($0,&h,1) }
    try check(status == 0,"EDFlib status \(status), filetype \(h.filetype)")
    defer { edfclose_file(h.handle) }
    try check(h.edfsignals == 12,"independent channel count")
}
test("BDF signed 24-bit extremes and independent validation") {
    let url = path("signed.bdf"), values = [-8388608.0,-1,0,8388607]
    try EDFWriter.write(to:url,signals:[.init(label:"Test",unit:"uV",rate:4,minimum:-8388608,maximum:8388607)],duration:1,bdf:true) { _,_,_ in values }
    let f = try EDFFile(url:url)
    try check(try f.samples(channel:0,start:0,duration:1).values == values,"24-bit sign extension")
    var h = edflib_hdr_t(); let status = url.path.withCString { edfopen_file_readonly($0,&h,1) }
    try check(status == 0,"EDFlib BDF status \(status) filetype \(h.filetype)"); if status == 0 { edfclose_file(h.handle) }
}
test("Annotation copy preserves physical/digital samples and Unicode") {
    let url = path("annotated.edf")
    try EDFWriter.saveCopy(demo,to:url,annotations:[.init(onset:1.234567,duration:2.5,text:"纺锤波, \"N2\"\nspindle")])
    let f = try EDFFile(url:url)
    try check(f.annotations[0].text == "纺锤波, \"N2\"\nspindle","annotation UTF-8")
    try check(near(f.annotations[0].onset,1.234567,1e-7),"microsecond onset")
    try check(try f.samples(channel:0,start:0,duration:90).values == demo.samples(channel:0,start:0,duration:90).values,"lossless sample copy")
    try expectFailure("source overwrite") { try EDFWriter.saveCopy(demo,to:demoURL,annotations:[]) }
}
test("Discontinuous EDF+D onsets, gaps and lossless save") {
    let url = path("gap.edf")
    try EDFWriter.write(to:url,signals:[.init(label:"C3",unit:"uV",rate:4,minimum:-1,maximum:1)],duration:2) { _,_,_ in [0,0,0,0] }
    let f = try EDFFile(url:url); var data = f.data
    data.replaceSubrange(192..<236,with:Data("EDF+D".utf8)+Data(repeating:32,count:39))
    let offset = f.header.headerBytes+f.header.bytesPerRecord+f.header.signals.last!.byteOffset
    data[offset+1] = 51 // +3 instead of +1
    try data.write(to:url)
    let gap = try EDFFile(url:url)
    try check(gap.recordOnsets == [0,3],"discontinuous record index")
    try check(try gap.samples(channel:0,start:1,duration:2).values.isEmpty,"gap has no invented samples")
    let copy = path("gapcopy.edf"); try EDFWriter.saveCopy(gap,to:copy,annotations:gap.annotations)
    try check(try EDFFile(url:copy).recordOnsets == [0,3],"save preserves gap")
    try expectFailure("export across gap") { try ExportEngine.export(file:gap,traces:[Trace(sourceID:gap.id,channel:0,label:"C3")],annotations:[],start:0,duration:4,targetRate:nil,bdf:false,filtered:false,to:path("badgap.edf")) }
}
test("Truncation, growing files and malformed scaling") {
    var data = demo.data; data.removeLast(10); let url = path("truncated.edf"); try data.write(to:url)
    try expectFailure("truncated closed file") { _ = try EDFFile(url:url) }
    try check(try EDFFile(url:url,allowGrowing:true).header.recordCount == 89,"growing file ignores partial record")
    data = demo.data; let n = demo.header.signals.count; data.replaceSubrange((256+n*112)..<(256+n*112+8),with:Data("-2000   ".utf8)); try data.write(to:url)
    try expectFailure("zero calibration span") { _ = try EDFFile(url:url) }
}
test("TAL malformed timestamps and UTF-8 are rejected") {
    try expectFailure("bad UTF-8") { _ = try EDFFile.parseTAL(Data([43,48,20,255,20,0])) }
    try expectFailure("missing sign") { _ = try EDFFile.parseTAL(Data("0\u{14}event\u{14}\0".utf8)) }
    try expectFailure("unrepresentable timestamp") { _ = try EDFFile.parseTAL(Data("+1e300\u{14}event\u{14}\0".utf8)) }
}
test("CSV quoting and annotation round trip") {
    let url = path("events.csv"), event = EDFAnnotation(onset:-0.2,duration:1.25,text:"纺锤波,\"N2\"\nline")
    try CSV.writeAnnotations([event],to:url)
    try check(try CSV.annotations(from:url)[0].text == event.text,"CSV quoted multiline UTF-8")
}
test("Wide and long signal CSV import/export") {
    let input = path("wide.csv"), output = path("imported.edf"), long = path("long.csv"), reimport = path("reimport.edf")
    try "time,C3,C4\n0,1,2\n0.25,2,3\n0.5,3,4\n0.75,4,5\n".write(to:input,atomically:true,encoding:.utf8)
    try CSV.importSignals(from:input,to:output)
    let f = try EDFFile(url:output); try check(f.signalChannels.count == 2,"CSV channels")
    try CSV.export(f,channels:[0,1],range:0..<1,to:long)
    try CSV.importSignals(from:long,to:reimport)
    try check(try EDFFile(url:reimport).signalChannels.count == 2,"long CSV round trip")
}
test("Welch PSD frequency and physical normalization") {
    let rate = 256.0, x = (0..<8192).map { sin(2*Double.pi*10*Double($0)/rate) }
    let p = try DSP.spectrum(x,rate:rate)
    let peak = p.power.indices.max { p.power[$0] < p.power[$1] }!
    try check(near(p.frequency[peak],10),"spectral peak")
    try check(near(p.power.reduce(0,+)*p.resolution,0.5,0.005),"integrated PSD equals variance")
}
test("Butterworth, Bessel and Chebyshev response") {
    let rate = 256.0, t = (0..<8192).map { Double($0)/rate }, x = t.map { sin(2*Double.pi*10*$0)+sin(2*Double.pi*60*$0) }
    for family in ["Butterworth","Bessel","Chebyshev"] {
        var settings = FilterSettings(); settings.family = family; settings.lowPass = 30
        let y = try DSP.filter(.init(times:t,values:x,rate:rate),settings:settings)
        let p = try DSP.spectrum(Array(y.values.suffix(4096)),rate:rate)
        try check(p.power[40] > p.power[240]*25,"\(family) stopband rejection")
    }
}
test("Notch rejection and invalid cutoff guards") {
    let t = (0..<8192).map { Double($0)/256 }, x = t.map { sin(2*Double.pi*10*$0)+sin(2*Double.pi*50*$0) }
    var settings = FilterSettings(); settings.notch = 50
    let y = try DSP.filter(.init(times:t,values:x,rate:256),settings:settings)
    let p = try DSP.spectrum(Array(y.values.suffix(4096)),rate:256)
    try check(p.power[40] > p.power[200]*100,"50 Hz rejection")
    settings.lowPass = 200
    try expectFailure("Nyquist cutoff") { _ = try DSP.filter(.init(times:t,values:x,rate:256),settings:settings) }
}
test("Resampling anti-aliasing") {
    let x = (0..<4096).map { sin(2*Double.pi*10*Double($0)/256)+sin(2*Double.pi*100*Double($0)/256) }
    let y = try DSP.resample(x,from:256,to:64)
    try check(y.count == 1024,"resampled length")
    let p = try DSP.spectrum(Array(y.dropFirst(128).dropLast(128)),rate:64,blockSize:256)
    try check(p.power[40] > p.power[112]*100,"alias suppression")
}
test("FIR coefficient normalization and aEEG envelope") {
    let fir = try DSP.fir(low:0,high:30,rate:256)
    try check(near(fir.reduce(0,+),1,1e-8),"FIR DC gain")
    let x = (0..<8192).map { 50*sin(2*Double.pi*10*Double($0)/256) }
    let envelope = try DSP.aEEG(x,rate:256)
    let mean = envelope.suffix(4096).reduce(0,+)/4096
    try check(mean > 20 && mean < 40,"rectified envelope in expected µV range, got \(mean)")
}
test("Pan–Tompkins QRS timing and beat count") {
    let s = try demo.samples(channel:9,start:0,duration:90), beats = try DSP.qrs(s,microvoltScale:1)
    try check(beats.count >= 95 && beats.count <= 105,"expected ~103 beats, got \(beats.count)")
    let rr = zip(beats,beats.dropFirst()).map { $1-$0 }
    try check(near(rr.reduce(0,+)/Double(rr.count),1/1.15,0.03),"RR interval")
}
test("Crop, channel selection and downsample export") {
    let url = path("crop.edf"), trace = Trace(sourceID:demo.id,channel:0,label:"C3")
    try ExportEngine.export(file:demo,traces:[trace],annotations:demo.annotations,start:10,duration:5,targetRate:64,bdf:false,filtered:false,to:url)
    let f = try EDFFile(url:url)
    try check(f.signalChannels.count == 1 && near(f.duration,5),"crop shape")
    try check(try f.samples(channel:0,start:0,duration:5).values.count == 320,"crop resampling")
    var h = edflib_hdr_t(); let status = url.path.withCString { edfopen_file_readonly($0,&h,1) }; try check(status == 0,"EDFlib crop validation \(h.filetype)"); if status == 0 { edfclose_file(h.handle) }
}
test("Envelope retains extrema, sufficient temporal resolution and real gaps") {
    let e = try demo.envelope(channel:0,start:0,duration:30,pixels:900)
    try check(e.values.count > 1200 && e.values.count <= 2000,"pixel envelope point count: \(e.values.count)")
    try check((e.values.max() ?? 0)>25 && (e.values.min() ?? 0) < -25,"transient amplitude retained")
}
test("Microsecond crop start and annotation synchronization") {
    let url = path("subsecond.edf"), trace = Trace(sourceID:demo.id,channel:0,label:"C3")
    try ExportEngine.export(file:demo,traces:[trace],annotations:[.init(onset:10.25,text:"Marker")],start:10.125,duration:1,targetRate:nil,bdf:false,filtered:false,to:url)
    let f = try EDFFile(url:url)
    try check(near(f.recordOnsets[0],0.125),"EDF+ timekeeping subsecond")
    try check(near(f.header.startDate.timeIntervalSince(demo.header.startDate)+f.recordOnsets[0],10.125),"absolute crop start")
    try check(near(f.annotations[0].onset,0.25),"annotation absolute synchronization")
}
test("Header calibration edits preserve raw digital data") {
    let url = path("calibrated.edf"); var signal = demo.header.signals[0]
    signal.unit = "mV"; signal.physicalMin /= 1000; signal.physicalMax /= 1000
    try EDFWriter.saveCopy(demo,to:url,annotations:demo.annotations,signalEdits:[0:signal])
    let file = try EDFFile(url:url), old = try demo.samples(channel:0,start:0,duration:1), new = try file.samples(channel:0,start:0,duration:1)
    try check(file.header.signals[0].unit == "mV","edited unit")
    try check(zip(old.values,new.values).allSatisfy({near($0/1000,$1,1e-10)}),"edited calibration")
}
test("Legacy XML montage linear combinations and IIR import") {
    let url = path("test.mtg")
    let xml = """
    <?xml version="1.0"?><EDFbrowser_montage><signalcomposition><num_of_signals>2</num_of_signals><voltpercm>50</voltpercm><polarity>-1</polarity><alias>C3-C4</alias><signal><label>EEG C3-A2</label><factor>1</factor></signal><signal><label>EEG C4-A1</label><factor>-1</factor></signal><fidfilter><type>1</type><frequency>30</frequency><frequency2>50</frequency2><ripple>-1</ripple><order>4</order><model>0</model></fidfilter></signalcomposition><pagetime>300000000</pagetime></EDFbrowser_montage>
    """
    try xml.write(to:url,atomically:true,encoding:.utf8)
    let montage = try LegacyMontage.read(url:url,file:demo)
    try check(montage.traces.count == 1 && montage.page == 30,"legacy layout")
    try check(montage.traces[0].components?.count == 2,"linear combination")
    let values = try SignalEngine.read(trace:montage.traces[0],file:demo,start:10,duration:1)
    try check(values.values.count == 256 && values.values.allSatisfy(\.isFinite),"imported filter execution")
}
test("BioSemi status bit decoding") {
    let url = path("triggers.bdf"), values = [0.0,65537,65537,0,2,2,0,257]
    try EDFWriter.write(to:url,signals:[.init(label:"Status",unit:"",rate:4,minimum:-8388608,maximum:8388607)],duration:2,bdf:true) { _,record,count in Array(values[record*4..<(record*4+count)]) }
    let events = try StatusTriggers.decode(file:EDFFile(url:url))
    try check(events.map(\.text) == ["Trigger 1","Trigger 2","Trigger 257"],"16-bit trigger codes")
    try check(events.map(\.onset) == [0.25,1,1.75],"trigger timing")
}
test("Parks–McClellan FIR passband and stopband") {
    let taps = try DSP.parksMcClellan(low:0,high:30,rate:256,transition:5)
    func response(_ frequency:Double) -> Double {
        let re = taps.enumerated().reduce(0.0) { $0+$1.element*cos(2*Double.pi*frequency*Double($1.offset)/256) }
        let im = taps.enumerated().reduce(0.0) { $0+$1.element*sin(2*Double.pi*frequency*Double($1.offset)/256) }
        return hypot(re,im)
    }
    try check(response(10) > 0.8,"FIR passband gain")
    try check(response(50) < 0.01,"FIR stopband rejection")
}
test("Z-ratio low/high frequency direction") {
    let delta = (0..<512).map { sin(2*Double.pi*2*Double($0)/256) }
    let alpha = (0..<512).map { sin(2*Double.pi*10*Double($0)/256) }
    try check(near(try DSP.zRatio(delta,rate:256),1,1e-6),"low-frequency Z-ratio")
    try check(near(try DSP.zRatio(alpha,rate:256),-1,1e-6),"high-frequency Z-ratio")
}
test("Display units convert voltage values and preserve non-voltage units") {
    for source in ["uV","µV","μV","UV"] {
        let unit = SignalDisplayUnit(sourceUnit:source)
        try check(unit.symbol == "μV" && unit.isVoltage && near(unit.value(50),50),"microvolt normalization: \(source)")
    }
    try check(near(SignalDisplayUnit(sourceUnit:"mV").value(0.05),50),"mV to microvolt factor")
    try check(near(SignalDisplayUnit(sourceUnit:"V").value(0.00005),50),"V to microvolt factor")
    let percent = SignalDisplayUnit(sourceUnit:"%")
    try check(percent.symbol == "%" && !percent.isVoltage && percent.value(97) == 97,"percent must not become voltage")
}
test("Equivalent EDF voltage channels display equally without changing source calibration") {
    let url = path("voltage-units.edf"), out = path("voltage-copy.edf"), rate = 256
    let signals = [EDFOutputSignal(label:"EEG uV",unit:"uV",rate:rate,minimum:-1000,maximum:1000),
                   EDFOutputSignal(label:"EEG mV",unit:"mV",rate:rate,minimum:-1,maximum:1),
                   EDFOutputSignal(label:"EEG V",unit:"V",rate:rate,minimum:-0.001,maximum:0.001)]
    let multipliers = [1.0,1000,1_000_000]
    try EDFWriter.write(to:url,signals:signals,duration:2) { i,record,count in
        (0..<count).map { 50*sin(2*Double.pi*10*(Double(record)+Double($0)/Double(rate)))/multipliers[i] }
    }
    let f = try EDFFile(url:url), originalBytes = try Data(contentsOf:url)
    let raw = try f.samples(channel:0,start:0,duration:2)
    for i in 0..<3 {
        var source = try f.samples(channel:i,start:0,duration:2); source.gapStarts = [1]
        let display = SignalDisplayUnit(sourceUnit:f.header.signals[i].unit).series(source)
        try check(zip(display.values,raw.values).allSatisfy({ near($0,$1,1e-7) }),"voltage channel overlay: \(i)")
        try check(display.times == source.times && display.gapStarts == source.gapStarts,"display conversion preserves time and gaps")
    }
    try check(try Data(contentsOf:url) == originalBytes,"display conversion did not modify EDF")
    try EDFWriter.saveCopy(f,to:out,annotations:f.annotations)
    let copy = try EDFFile(url:out)
    try check(copy.header.signals[1].unit == "mV" && copy.header.signals[2].unit == "V","saved copy retains original units")
    try check(try copy.samples(channel:1,start:0,duration:2).values == f.samples(channel:1,start:0,duration:2).values,"saved copy retains original physical values")
}
test("PSD voltage conversion uses squared amplitude units") {
    let values = (0..<4096).map { 0.05*sin(2*Double.pi*10*Double($0)/256) }
    let source = SampleSeries(times:values.indices.map { Double($0)/256 },values:values,rate:256)
    let nativePSD = try DSP.spectrum(source.values,rate:256)
    let displayedPSD = try DSP.spectrum(SignalDisplayUnit(sourceUnit:"mV").series(source).values,rate:256)
    try check(near(displayedPSD.power[40],nativePSD.power[40]*1_000_000,1e-6),"mV² to microvolt² requires factor 10^6")
    try check(near(displayedPSD.power.reduce(0,+)*displayedPSD.resolution,1250,0.1),"50 microvolt peak sine has expected integrated PSD")
}
if CommandLine.arguments.contains("--large") {
    test("1 GiB sparse EDF indexing and last-window random access") {
        let seed = path("large-seed.edf"), large = path("large-sparse.edf"), count = 65536
        try EDFWriter.write(to:seed,signals:[.init(label:"EEG",unit:"uV",rate:8192,minimum:-1,maximum:1)],duration:1) { _,_,n in [Double](repeating:0,count:n) }
        let f = try EDFFile(url:seed), n = f.header.signals.count
        func field(_ value:String,_ length:Int) -> Data { Data(value.utf8)+Data(repeating:32,count:length-value.utf8.count) }
        var header = Data(f.data.prefix(256))
        header.replaceSubrange(184..<192,with:field("512",8)); header.replaceSubrange(192..<236,with:field("",44))
        header.replaceSubrange(236..<244,with:field(String(count),8)); header.replaceSubrange(252..<256,with:field("1",4))
        var group = 256
        for width in [16,80,8,8,8,8,8,80,8,32] { header.append(f.data[group..<(group+width)]); group += width*n }
        FileManager.default.createFile(atPath:large.path,contents:header)
        let h = try FileHandle(forWritingTo:large); try h.truncate(atOffset:UInt64(512+count*8192*2)); try h.close()
        let start = Date(), indexed = try EDFFile(url:large), values = try indexed.samples(channel:0,start:Double(count-1),duration:1)
        try check(indexed.header.recordCount == count && values.values.count == 8192,"large last-window sample count")
        print(String(format:"  1 GiB sparse fixture indexed + last window in %.3f s",Date().timeIntervalSince(start)))
    }
}
for argument in CommandLine.arguments.dropFirst() where argument.lowercased().hasSuffix(".edf") || argument.lowercased().hasSuffix(".bdf") {
    if CommandLine.arguments.contains("--demo") { break }
    test("Official fixture: \(URL(fileURLWithPath:argument).lastPathComponent)") {
        let f = try EDFFile(url:URL(fileURLWithPath:argument))
        if f.signalChannels.isEmpty {
            try check(!f.annotations.isEmpty && f.duration > 0,"annotation-only hypnogram duration")
            try check(f.annotations.contains(where: { $0.sleepStage != nil }),"hypnogram stages")
            return
        }
        let sine = f.signalChannels.first { $0.label.lowercased().contains("sine 8 hz") }
        if let s = sine {
            let data = try f.samples(channel:s.id,start:10,duration:10)
            let p = try DSP.spectrum(data.values,rate:data.rate,blockSize:1000)
            let peak = p.power.indices.max { p.power[$0]<p.power[$1] }!
            try check(near(p.frequency[peak],8,0.21),"8 Hz reference sine")
        }
        let copy = path("fixture-\(UUID().uuidString)."+(f.header.isBDF ? "bdf":"edf"))
        try EDFWriter.saveCopy(f,to:copy,annotations:f.annotations)
        let roundtrip = try EDFFile(url:copy)
        try check(roundtrip.header.recordCount == f.header.recordCount,"fixture record count")
        let s = f.signalChannels[0]
        try check(try f.samples(channel:s.id,start:0,duration:min(10,f.duration)).values == roundtrip.samples(channel:0,start:0,duration:min(10,f.duration)).values,"fixture digital copy")
    }
}
print("\n\(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }
if let i = CommandLine.arguments.firstIndex(of:"--demo"), i+1 < CommandLine.arguments.count { try Demo.generate(to:URL(fileURLWithPath:CommandLine.arguments[i+1])) }
