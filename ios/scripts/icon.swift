// Render the original Android cl0udly vector as an iOS app icon (macOS build tool).
import AppKit
import Foundation
let folder = URL(fileURLWithPath: "ios/OpenCode/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(srgbRed: 0.043, green: 0.047, blue: 0.055, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
func polygon(_ points: [(Double, Double)], color: NSColor) {
    let path = NSBezierPath()
    for (i, point) in points.enumerated() {
        let p = NSPoint(x: point.0 * 1024 / 108, y: (108 - point.1) * 1024 / 108)
        if i == 0 { path.move(to: p) } else { path.line(to: p) }
    }
    path.close(); color.setFill(); path.fill()
}
func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ color: NSColor) {
    polygon([(x,y),(x+w,y),(x+w,y+h),(x,y+h)], color: color)
}
polygon([(31.05,46.1),(40.5,46.1),(40.5,39.07),(70.55,39.07),(70.55,46.1),(77.57,46.1),(77.57,65.69),(31.05,65.69)], color: .white)
let shade = NSColor(srgbRed: 186/255, green: 186/255, blue: 188/255, alpha: 1)
rect(66.19,39.07,4.36,7.03,shade); rect(70.55,46.1,4.29,4.98,shade)
rect(31.05,52.32,3.85,13.37,shade); rect(34.9,59.78,4.05,5.91,shade)
let eye = NSColor(srgbRed: 35/255, green: 36/255, blue: 40/255, alpha: 1)
rect(46.29,45.91,4.23,12.32,eye); rect(57.79,45.91,4.17,12.32,eye)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("AppIcon.png"))
try Data(#"{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}"#.utf8).write(to: folder.appendingPathComponent("Contents.json"))
