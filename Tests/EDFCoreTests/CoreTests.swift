import XCTest
import CDSP
@testable import EDFCore

final class CoreTests: XCTestCase {
    func temporary(_ suffix: String = "edf") -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(suffix) }
    func testEDFRoundTripAndIndependentValidator() throws {
        let url = temporary(); defer { try? FileManager.default.removeItem(at: url) }
        try Demo.generate(to: url,duration: 90)
        let f = try EDFFile(url: url)
        XCTAssertEqual(f.signalChannels.count,12); XCTAssertEqual(f.duration,90)
        XCTAssertEqual(f.annotations.filter { $0.sleepStage != nil }.count,3)
        let s = try f.samples(channel: 0,start: 1,duration: 2)
        XCTAssertEqual(s.values.count,512); XCTAssertEqual(s.times.first!,1,accuracy: 1e-8)
        var h = edflib_hdr_t()
        let result = url.path.withCString { edfopen_file_readonly($0,&h,1) }
        XCTAssertEqual(result,0,"Independent EDFlib rejected the generated EDF+ file: \(h.filetype)")
        if result == 0 { XCTAssertEqual(h.edfsignals,12); edfclose_file(h.handle) }
    }
    func testBDFNegative24BitAndAnnotationCopy() throws {
        let url = temporary("bdf"), out = temporary("bdf")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: out) }
        let values = [-8388608.0,-1,0,8388607]
        try EDFWriter.write(to: url,signals: [.init(label:"Test",unit:"uV",rate:4,minimum:-8388608,maximum:8388607)],duration:1,bdf:true) { _,_,_ in values }
        let file = try EDFFile(url: url)
        XCTAssertEqual(try file.samples(channel:0,start:0,duration:1).values,values)
        try EDFWriter.saveCopy(file,to:out,annotations:[.init(onset:0.25,duration:0.125,text:"纺锤波, spindle")])
        let copy = try EDFFile(url:out)
        XCTAssertEqual(copy.annotations.first?.text,"纺锤波, spindle")
        XCTAssertEqual(try copy.samples(channel:0,start:0,duration:1).values,values)
    }
    func testRejectTruncation() throws {
        let url = temporary(); defer { try? FileManager.default.removeItem(at:url) }
        try Demo.generate(to:url,duration:2)
        var data = try Data(contentsOf:url); data.removeLast(10); try data.write(to:url)
        XCTAssertThrowsError(try EDFFile(url:url))
        XCTAssertEqual(try EDFFile(url:url,allowGrowing:true).header.recordCount,1)
    }
    func testTALAndCSVUnicode() throws {
        let event = EDFAnnotation(onset:-0.05,duration:30,text:"N2,\"睡眠\"\nStage")
        let parsed = try EDFFile.parseTAL(EDFWriter.tal(event))
        XCTAssertEqual(parsed.events[0].text,event.text); XCTAssertEqual(parsed.events[0].onset,-0.05)
        let url = temporary("csv"); defer { try? FileManager.default.removeItem(at:url) }
        try CSV.writeAnnotations([event],to:url)
        XCTAssertEqual(try CSV.annotations(from:url)[0].text,event.text)
    }
    func testFFTAndFilterResponse() throws {
        let rate = 256.0, count = 8192
        let times = (0..<count).map { Double($0)/rate }
        let values = times.map { sin(2*Double.pi*10*$0)+sin(2*Double.pi*60*$0) }
        let spectrum = try DSP.spectrum(values,rate:rate)
        let peak = spectrum.power.enumerated().max { $0.element < $1.element }!.offset
        XCTAssertTrue([10.0,60.0].contains(spectrum.frequency[peak]))
        var filter = FilterSettings(); filter.lowPass = 30
        let filtered = try DSP.filter(.init(times:times,values:values,rate:rate),settings:filter)
        let psd = try DSP.spectrum(Array(filtered.values.suffix(4096)),rate:rate)
        XCTAssertGreaterThan(psd.power[40]/psd.power[240],100)
        let area = spectrum.power.reduce(0,+)*spectrum.resolution
        XCTAssertEqual(area,1,accuracy:0.02)
    }
    func testResamplingAntiAlias() throws {
        let x = (0..<4096).map { sin(2*Double.pi*10*Double($0)/256) + sin(2*Double.pi*100*Double($0)/256) }
        let y = try DSP.resample(x,from:256,to:64)
        let s = try DSP.spectrum(Array(y.dropFirst(128).dropLast(128)),rate:64,blockSize:256)
        XCTAssertGreaterThan(s.power[40]/max(1e-10,s.power[112]),100)
    }
    func testCSVSignalImport() throws {
        let input = temporary("csv"), output = temporary(); defer { try? FileManager.default.removeItem(at:input); try? FileManager.default.removeItem(at:output) }
        try "time,C3,C4\n0,1,2\n0.25,2,3\n0.5,3,4\n0.75,4,5\n".write(to:input,atomically:true,encoding:.utf8)
        try CSV.importSignals(from:input,to:output)
        let f = try EDFFile(url:output)
        XCTAssertEqual(f.signalChannels.count,2)
        XCTAssertEqual(try f.samples(channel:0,start:0,duration:1).values[0],1,accuracy:0.001)
    }
}
