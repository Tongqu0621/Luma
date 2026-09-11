import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let outer = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 210, yRadius: 210)
        NSGradient(starting: NSColor(calibratedRed: 0.19, green: 0.21, blue: 0.19, alpha: 1), ending: NSColor(calibratedRed: 0.065, green: 0.075, blue: 0.065, alpha: 1))!.draw(in: outer, angle: -70)
        NSColor(calibratedRed: 0.79, green: 0.72, blue: 0.55, alpha: 1).setStroke()
        let frame = NSBezierPath(roundedRect: NSRect(x: 280, y: 210, width: 464, height: 604), xRadius: 12, yRadius: 12)
        frame.lineWidth = 12; frame.stroke()
        NSColor(calibratedRed: 0.93, green: 0.89, blue: 0.76, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 451, y: 505, width: 122, height: 122)).fill()
        let horizon = NSBezierPath()
        horizon.move(to: NSPoint(x: 220, y: 455)); horizon.line(to: NSPoint(x: 804, y: 455))
        horizon.lineWidth = 12; horizon.stroke()
        NSColor(calibratedRed: 0.79, green: 0.72, blue: 0.55, alpha: 0.28).setStroke()
        let echo = NSBezierPath()
        echo.move(to: NSPoint(x: 394, y: 360)); echo.line(to: NSPoint(x: 630, y: 360))
        echo.lineWidth = 8; echo.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
