import AppKit
import Foundation
let output = CommandLine.arguments[1]
let size = NSSize(width:1024,height:1024)
let image = NSImage(size:size)
image.lockFocus()
NSColor.clear.setFill(); NSRect(origin:.zero,size:size).fill()
let shape = NSBezierPath(roundedRect:NSRect(x:34,y:34,width:956,height:956),xRadius:220,yRadius:220)
NSGradient(starting:NSColor(srgbRed:0.08,green:0.30,blue:0.62,alpha:1),ending:NSColor(srgbRed:0.03,green:0.64,blue:0.70,alpha:1))!.draw(in:shape,angle:-45)
NSGraphicsContext.saveGraphicsState(); shape.addClip()
let grid = NSBezierPath(); grid.lineWidth = 2
for p in stride(from:100.0,through:1000.0,by:82) { grid.move(to:NSPoint(x:p,y:0)); grid.line(to:NSPoint(x:p,y:1024)); grid.move(to:NSPoint(x:0,y:p)); grid.line(to:NSPoint(x:1024,y:p)) }
NSColor.white.withAlphaComponent(0.07).setStroke(); grid.stroke()
let wave = NSBezierPath(); wave.lineWidth = 26; wave.lineCapStyle = .round; wave.lineJoinStyle = .round
wave.move(to:NSPoint(x:128,y:500))
for p in [NSPoint(x:255,y:500),NSPoint(x:310,y:558),NSPoint(x:366,y:425),NSPoint(x:438,y:730),NSPoint(x:508,y:280),NSPoint(x:580,y:570),NSPoint(x:644,y:500),NSPoint(x:710,y:500),NSPoint(x:758,y:540),NSPoint(x:804,y:500),NSPoint(x:896,y:500)] { wave.line(to:p) }
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.15); shadow.shadowBlurRadius = 20; shadow.shadowOffset = NSSize(width:0,height:-10); shadow.set()
NSColor.white.setStroke(); wave.stroke(); NSGraphicsContext.restoreGraphicsState(); image.unlockFocus()
let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:output))
