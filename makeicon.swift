import AppKit

// Draws the LaunchDeck app icon: a dark rounded tile with a 3x3 app grid.

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

let full = NSRect(x: 0, y: 0, width: canvas, height: canvas)
NSColor.clear.setFill()
full.fill()

let body = NSBezierPath(roundedRect: full.insetBy(dx: 44, dy: 44), xRadius: 218, yRadius: 218)
let backdrop = NSGradient(colors: [
    NSColor(srgbRed: 0.20, green: 0.27, blue: 0.52, alpha: 1),
    NSColor(srgbRed: 0.05, green: 0.07, blue: 0.16, alpha: 1),
])!
backdrop.draw(in: body, angle: -68)

NSGraphicsContext.current?.saveGraphicsState()
body.addClip()

let glow = NSGradient(colors: [
    NSColor(srgbRed: 0.45, green: 0.66, blue: 1.0, alpha: 0.55),
    NSColor(srgbRed: 0.45, green: 0.66, blue: 1.0, alpha: 0.0),
])!
glow.draw(in: NSRect(x: -120, y: canvas * 0.52, width: canvas * 1.25, height: canvas * 0.95), relativeCenterPosition: NSPoint(x: 0, y: 0))

let tile: CGFloat = 178
let gap: CGFloat = 46
let total = tile * 3 + gap * 2
let originX = (canvas - total) / 2
let originY = (canvas - total) / 2

let tints: [NSColor] = [
    NSColor(srgbRed: 0.98, green: 0.98, blue: 1.0, alpha: 0.96),
    NSColor(srgbRed: 0.80, green: 0.88, blue: 1.0, alpha: 0.94),
    NSColor(srgbRed: 0.98, green: 0.98, blue: 1.0, alpha: 0.96),
    NSColor(srgbRed: 0.80, green: 0.88, blue: 1.0, alpha: 0.94),
    NSColor(srgbRed: 1.0, green: 0.85, blue: 0.55, alpha: 1.0),
    NSColor(srgbRed: 0.80, green: 0.88, blue: 1.0, alpha: 0.94),
    NSColor(srgbRed: 0.98, green: 0.98, blue: 1.0, alpha: 0.96),
    NSColor(srgbRed: 0.80, green: 0.88, blue: 1.0, alpha: 0.94),
    NSColor(srgbRed: 0.98, green: 0.98, blue: 1.0, alpha: 0.96),
]

for row in 0 ..< 3 {
    for column in 0 ..< 3 {
        let x = originX + CGFloat(column) * (tile + gap)
        let y = originY + CGFloat(2 - row) * (tile + gap)
        let rect = NSRect(x: x, y: y, width: tile, height: tile)
        let cell = NSBezierPath(roundedRect: rect, xRadius: 44, yRadius: 44)
        tints[row * 3 + column].setFill()
        cell.fill()
    }
}

NSGraphicsContext.current?.restoreGraphicsState()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("icon: failed to encode PNG\n".utf8))
    exit(1)
}

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
try png.write(to: URL(fileURLWithPath: output))
print(output)
