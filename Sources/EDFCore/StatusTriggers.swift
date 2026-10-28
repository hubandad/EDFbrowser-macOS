import Foundation

public enum StatusTriggers {
    public static func decode(file:EDFFile) throws -> [EDFAnnotation] {
        guard file.header.isBDF, let signal = file.signalChannels.first(where:{$0.label.lowercased() == "status"}) else { throw EDFError.invalid("No BioSemi BDF Status channel found") }
        var events:[EDFAnnotation] = [], previous = 0, lastTime = -Double.infinity, time = 0.0
        let rate = signal.sampleRate(file.header.recordDuration)
        while time < file.duration {
            let length = min(30,file.duration-time)
            let series = try file.samples(channel:signal.id,start:time,duration:length)
            for i in series.values.indices {
                if series.times[i]-lastTime > 1.5/rate { previous = 0 }
                let digital = Int(((series.values[i]-signal.physicalMin)/signal.scale+Double(signal.digitalMin)).rounded())
                let status = digital & 0xffff
                if status != 0 && status != previous { events.append(EDFAnnotation(onset:series.times[i],text:"Trigger \(status)")) }
                previous = status; lastTime = series.times[i]
            }
            time += length
        }
        return events
    }
}
