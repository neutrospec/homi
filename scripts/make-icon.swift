// make-icon.swift <글자> <out.tiff> — menu bar 용 template icon 을 만든다.
// 16pt 한 장을 @1x·@2x 두 해상도로 담는다. template 이므로 검정 + 투명만 쓴다 (system 이 색을 입힌다).
//   swift scripts/make-icon.swift 호 Sources/homi/Bundle/Resources/homi.tiff

import AppKit

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: make-icon.swift <text> <out.tiff>")
    exit(2)
}
let (text, out) = (args[1], args[2])

func representation(scale: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 16 * scale, pixelsHigh: 16 * scale, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 16, height: 16)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let glyph = NSAttributedString(
        string: text,
        attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.black])
    let size = glyph.size()
    glyph.draw(at: NSPoint(x: (16 - size.width) / 2, y: (16 - size.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let data = NSBitmapImageRep.tiffRepresentationOfImageReps(
    in: [representation(scale: 1), representation(scale: 2)], using: .lzw, factor: 0)!
try data.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
