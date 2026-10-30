import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 4 else {
    fputs("usage: render_svg.swift <src.svg> <dst.png> <size>\n", stderr)
    exit(1)
}
let srcURL = URL(fileURLWithPath: args[1])
let dstURL = URL(fileURLWithPath: args[2])
let size = Int(args[3]) ?? 1024

guard let image = NSImage(contentsOf: srcURL) else {
    fputs("Failed to load SVG: \(srcURL.path)\n", stderr)
    exit(1)
}
image.size = NSSize(width: size, height: size)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else { fputs("bitmap rep failed\n", stderr); exit(1) }

NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
// Opaque background fill (in case gradients don't cover every corner)
ctx.cgContext.setFillColor(CGColor(red: 0x0A/255.0, green: 0x0B/255.0, blue: 0x0E/255.0, alpha: 1.0))
ctx.cgContext.fill(CGRect(x: 0, y: 0, width: size, height: size))
image.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("png representation failed\n", stderr)
    exit(1)
}
try! data.write(to: dstURL)
print("rendered \(size)x\(size) -> \(dstURL.path)")
