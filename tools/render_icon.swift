import AppKit

let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Background gradient (cyan -> blue), full bleed; iOS masks the corners.
let cs = CGColorSpaceCreateDeviceRGB()
let grad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1), // cyan
    CGColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1)  // blue
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// White shield, centered.
func shieldPath(cx: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let halfW = w / 2
    p.move(to: CGPoint(x: cx, y: top))                                  // top center
    p.addLine(to: CGPoint(x: cx + halfW, y: top - h * 0.22))            // upper right
    p.addLine(to: CGPoint(x: cx + halfW, y: top - h * 0.58))            // mid right
    p.addQuadCurve(to: CGPoint(x: cx, y: top - h),                      // bottom point
                   control: CGPoint(x: cx + halfW * 0.85, y: top - h * 0.9))
    p.addQuadCurve(to: CGPoint(x: cx - halfW, y: top - h * 0.58),       // bottom point -> mid left
                   control: CGPoint(x: cx - halfW * 0.85, y: top - h * 0.9))
    p.addLine(to: CGPoint(x: cx - halfW, y: top - h * 0.22))            // upper left
    p.closeSubpath()
    return p
}
let cx = size / 2
let shield = shieldPath(cx: cx, top: size * 0.84, w: size * 0.5, h: size * 0.62)
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: CGColor(gray: 0, alpha: 0.25))
ctx.addPath(shield)
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

// Voice waveform inside the shield (gradient bars).
let barColor = CGColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1)
let heights: [CGFloat] = [0.10, 0.20, 0.34, 0.20, 0.10]
let barW = size * 0.045
let gap = size * 0.028
let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
var x = cx - totalW / 2
let midY = size * 0.52
for h in heights {
    let bh = size * h
    let r = CGRect(x: x, y: midY - bh / 2, width: barW, height: bh)
    let path = CGPath(roundedRect: r, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(barColor)
    ctx.fillPath()
    x += barW + gap
}

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
