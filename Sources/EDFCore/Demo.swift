import Foundation

public enum Demo {
    public static func generate(to url: URL, duration: Double = 300) throws {
        let labels = ["EEG Fp1-A2","EEG Fp2-A1","EEG C3-A2","EEG C4-A1","EEG O1-A2","EEG O2-A1","EOG-L","EOG-R","EMG Chin","ECG","Resp","SpO2"]
        let signals = labels.enumerated().map { i,label in
            EDFOutputSignal(label: label,unit: i == 11 ? "%" : "uV",rate: i == 11 ? 1 : 256,minimum: i == 11 ? 0 : -2000,maximum: i == 11 ? 100 : 2000)
        }
        let stages = ["W","N1","N2","N2","N3","N3","N2","R","R","W"]
        var annotations = stages.enumerated().filter { Double($0.offset*30) < duration }.map {
            EDFAnnotation(onset: Double($0.offset*30),duration: min(30,duration-Double($0.offset*30)),text: "Sleep stage \($0.element)")
        }
        annotations += [EDFAnnotation(onset: 0,text: "Synthetic demonstration — no patient data"), EDFAnnotation(onset: 12,duration: 2,text: "Eyes closed"), EDFAnnotation(onset: 68,duration: 1.5,text: "Sleep spindle")]
        try EDFWriter.write(to: url,signals: signals,duration: duration,patient: "DEMO X X Synthetic",recording: "Startdate X X X Synthetic_PSG",annotations: annotations) { channel,record,count in
            let rate = Double(signals[channel].rate)
            return (0..<count).map { sample -> Double in
                let t = Double(record)+Double(sample)/rate, phase = Double(channel)*0.31
                if channel == 11 { return 97+sin(t/17) }
                if channel == 9 {
                    let beat = (t*1.15).truncatingRemainder(dividingBy: 1)
                    return 1000*exp(-pow((beat-0.18)/0.018,2))-210*exp(-pow((beat-0.21)/0.026,2))+150*exp(-pow((beat-0.46)/0.09,2))
                }
                if channel == 10 { return 90*sin(2*Double.pi*0.24*t) }
                if channel == 8 { return 9*sin(2*Double.pi*33*t)+4*sin(2*Double.pi*57.3*t) }
                let stage = Int(t/30)%10, hz: Double = stage == 4 || stage == 5 ? 1.5 : stage > 6 ? 5.5 : 10
                let base = (stage == 4 || stage == 5 ? 65.0 : 23.0)*sin(2*Double.pi*hz*t+phase)
                let spindle = 22*exp(-pow((t-68.8)/0.7,2))*sin(2*Double.pi*13.5*t)
                return base + spindle + 8*sin(2*Double.pi*1.2*t+phase) + 2*sin(2*Double.pi*50*t) + 3*sin(2*Double.pi*37.123*t+phase)
            }
        }
    }
}
