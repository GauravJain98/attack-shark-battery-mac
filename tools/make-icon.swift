// Renders the app icon: a shark fin over water above a battery gauge.
// Usage: swift tools/make-icon.swift <output-dir>  (writes logo.png and AppIcon.icns)
import AppKit

let canvasSize: CGFloat = 1024
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])

func renderIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: size / canvasSize, y: size / canvasSize)

    // macOS icon grid: 824pt body inset 100pt, continuous-ish corner radius.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    bodyPath.addClip()
    NSGradient(starting: NSColor(red: 0.04, green: 0.11, blue: 0.24, alpha: 1),
               ending: NSColor(red: 0.02, green: 0.42, blue: 0.55, alpha: 1))!.draw(in: body, angle: 90)

    let fin = NSBezierPath()
    fin.move(to: CGPoint(x: 300, y: 500))
    fin.curve(to: CGPoint(x: 640, y: 820), controlPoint1: CGPoint(x: 420, y: 560), controlPoint2: CGPoint(x: 520, y: 700))
    fin.curve(to: CGPoint(x: 720, y: 500), controlPoint1: CGPoint(x: 640, y: 700), controlPoint2: CGPoint(x: 660, y: 580))
    fin.close()
    NSColor(red: 0.86, green: 0.95, blue: 1, alpha: 1).setFill()
    fin.fill()

    let water = NSBezierPath()
    water.move(to: CGPoint(x: 100, y: 500))
    for waveStart in stride(from: CGFloat(100), to: 924, by: 137) {
        water.curve(to: CGPoint(x: waveStart + 137, y: 500),
                    controlPoint1: CGPoint(x: waveStart + 45, y: 540), controlPoint2: CGPoint(x: waveStart + 92, y: 460))
    }
    water.line(to: CGPoint(x: 924, y: 100))
    water.line(to: CGPoint(x: 100, y: 100))
    water.close()
    NSColor(red: 0.03, green: 0.2, blue: 0.36, alpha: 1).setFill()
    water.fill()

    let battery = CGRect(x: 330, y: 230, width: 330, height: 150)
    let batteryOutline = NSBezierPath(roundedRect: battery, xRadius: 36, yRadius: 36)
    batteryOutline.lineWidth = 24
    NSColor.white.setStroke()
    batteryOutline.stroke()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: CGRect(x: 672, y: 270, width: 34, height: 70), xRadius: 12, yRadius: 12).fill()
    NSColor(red: 0.35, green: 0.9, blue: 0.45, alpha: 1).setFill()
    NSBezierPath(roundedRect: CGRect(x: 360, y: 260, width: 200, height: 90), xRadius: 16, yRadius: 16).fill()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) {
    try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

writePNG(renderIcon(size: 512), to: outputDirectory.appendingPathComponent("logo.png"))

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for pointSize in [16, 32, 128, 256, 512] {
    writePNG(renderIcon(size: CGFloat(pointSize)), to: iconset.appendingPathComponent("icon_\(pointSize)x\(pointSize).png"))
    writePNG(renderIcon(size: CGFloat(pointSize * 2)), to: iconset.appendingPathComponent("icon_\(pointSize)x\(pointSize)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputDirectory.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
