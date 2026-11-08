import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Export the checked-in master artwork; rebuilding the icon never needs image generation.
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/make-icon.swift Resources\n",stderr); exit(1)
}
let resources = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let master = resources.appendingPathComponent("IconArtwork.png")
guard let source = CGImageSourceCreateWithURL(master as CFURL,nil),
      let artwork = CGImageSourceCreateImageAtIndex(source,0,nil) else {
    fputs("Cannot read IconArtwork.png\n",stderr); exit(1)
}
func png(size:Int,to url:URL) throws {
    guard let context = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,
                                  space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
    context.interpolationQuality = .high
    context.draw(artwork,in:CGRect(x:0,y:0,width:size,height:size))
    guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination,image,nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("edf-icon-\(UUID().uuidString)")
let iconset = temporary.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
defer { try? FileManager.default.removeItem(at:temporary) }
for points in [16,32,128,256,512] {
    for scale in [1,2] {
        let suffix = scale == 2 ? "@2x" : ""
        try png(size:points*scale,to:iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try png(size:1024,to:resources.appendingPathComponent("AppIcon.png"))
let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/iconutil")
process.arguments = ["-c","icns",iconset.path,"-o",resources.appendingPathComponent("AppIcon.icns").path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
print("Exported AppIcon.png and AppIcon.icns from IconArtwork.png")
