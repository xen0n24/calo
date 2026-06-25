#!/usr/bin/swift
// Rendert SF Symbol "fork.knife.circle.fill" als 1024×1024 PNG
// Aufruf: swift gen_icon.swift <output-path>
import AppKit

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon-1024.png"

let size = 1024
let pointSize: CGFloat = 820
let green = NSColor(red: 52/255.0, green: 199/255.0, blue: 89/255.0, alpha: 1.0)

// Off-screen bitmap context
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Schwarzer Hintergrund
NSColor.black.setFill()
NSBezierPath.fill(NSRect(x: 0, y: 0, width: size, height: size))

// SF Symbol mit Palette: Kreis=Grün, Gabel+Messer=Schwarz
let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    .applying(NSImage.SymbolConfiguration(paletteColors: [green, .black]))

if let symbol = NSImage(systemSymbolName: "fork.knife.circle.fill",
                         accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
    let x = (CGFloat(size) - symbol.size.width)  / 2
    let y = (CGFloat(size) - symbol.size.height) / 2
    symbol.draw(in: NSRect(x: x, y: y,
                           width: symbol.size.width,
                           height: symbol.size.height))
    print("Symbol gerendert: \(symbol.size.width)×\(symbol.size.height)pt")
} else {
    print("FEHLER: SF Symbol nicht gefunden")
    exit(1)
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    print("FEHLER: PNG-Erstellung fehlgeschlagen")
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("✓ Gespeichert: \(outputPath) (\(png.count / 1024) KB)")
} catch {
    print("FEHLER beim Schreiben: \(error)")
    exit(1)
}
