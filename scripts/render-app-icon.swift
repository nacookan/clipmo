import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: render-app-icon.swift <output-png-path>")
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let rect = NSRect(origin: .zero, size: size)

let image = NSImage(size: size)
image.lockFocus()

NSColor.clear.setFill()
rect.fill()

let backgroundRect = rect.insetBy(dx: 96, dy: 96)
let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 224, yRadius: 224)

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.16, alpha: 1.0),
    NSColor(calibratedRed: 0.18, green: 0.27, blue: 0.38, alpha: 1.0)
])
gradient?.draw(in: backgroundPath, angle: -90)

NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.18)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
backgroundPath.fill()
NSGraphicsContext.current?.restoreGraphicsState()

let accentRect = NSRect(x: 184, y: 184, width: 656, height: 656)
let accentPath = NSBezierPath(roundedRect: accentRect, xRadius: 160, yRadius: 160)
NSColor(calibratedRed: 0.94, green: 0.97, blue: 1.0, alpha: 0.12).setFill()
accentPath.fill()

let symbolConfig = NSImage.SymbolConfiguration(pointSize: 470, weight: .regular)
guard let symbol = NSImage(systemSymbolName: "list.bullet.clipboard.fill", accessibilityDescription: "Clipmo")?
    .withSymbolConfiguration(symbolConfig)
else {
    fail("failed to load system symbol")
}

let tintedSymbol = symbol.copy() as? NSImage ?? symbol
tintedSymbol.isTemplate = false
tintedSymbol.lockFocus()
NSColor(calibratedRed: 0.98, green: 0.99, blue: 1.0, alpha: 0.96).set()
NSRect(origin: .zero, size: tintedSymbol.size).fill(using: .sourceAtop)
tintedSymbol.unlockFocus()

let symbolRect = NSRect(x: 277, y: 246, width: 470, height: 532)
tintedSymbol.draw(in: symbolRect)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fail("failed to encode png")
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
    )
    try pngData.write(to: outputURL, options: .atomic)
} catch {
    fail("failed to write png: \(error)")
}
