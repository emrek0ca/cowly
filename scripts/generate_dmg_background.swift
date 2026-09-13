import AppKit
import Foundation

// Generates an Apple-quality light/white Retina background image for the Cowly DMG installer.
// Canvas: 660x420 pt, rendered at 2x Retina (1320x840 px).
// Requirements:
// 1. Pure light/white aesthetic
// 2. Floating, dynamic motion elements (translucent glass bubbles, liquid droplets, colorful fluid orbs)
// 3. ZERO TEXT (no letters, numbers, or words of any kind)

let width: CGFloat = 660
let height: CGFloat = 420
let scale: CGFloat = 2.0

let pixelWidth = Int(width * scale)
let pixelHeight = Int(height * scale)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil,
    width: pixelWidth,
    height: pixelHeight,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Could not create CGContext")
}

context.scaleBy(x: scale, y: scale)

// 1. Crisp, Bright Apple Light Background (Pure white with subtle pearlescent warmth)
let bgColors = [
    CGColor(red: 0.985, green: 0.985, blue: 0.992, alpha: 1.0),
    CGColor(red: 0.965, green: 0.968, blue: 0.980, alpha: 1.0),
    CGColor(red: 0.950, green: 0.955, blue: 0.975, alpha: 1.0)
] as CFArray
let bgLocations: [CGFloat] = [0.0, 0.5, 1.0]
if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
    context.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: 0, y: height),
        end: CGPoint(x: width, y: 0),
        options: []
    )
}

// 2. Ambient Soft Pastel Glows (Soft rose-pink and gentle violet/sky-blue)
func drawSoftAura(center: CGPoint, radius: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat, alpha: CGFloat) {
    let auraColors = [
        CGColor(red: r, green: g, blue: b, alpha: alpha),
        CGColor(red: r, green: g, blue: b, alpha: alpha * 0.4),
        CGColor(red: r, green: g, blue: b, alpha: 0.0)
    ] as CFArray
    let auraLocs: [CGFloat] = [0.0, 0.55, 1.0]
    if let grad = CGGradient(colorsSpace: colorSpace, colors: auraColors, locations: auraLocs) {
        context.drawRadialGradient(
            grad,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: []
        )
    }
}

// Auras in background
drawSoftAura(center: CGPoint(x: 180, y: 230), radius: 220, r: 0.96, g: 0.45, b: 0.65, alpha: 0.14) // Pink aura under Cowly
drawSoftAura(center: CGPoint(x: 480, y: 230), radius: 220, r: 0.35, g: 0.55, b: 0.98, alpha: 0.12) // Blue aura under Applications
drawSoftAura(center: CGPoint(x: 330, y: 250), radius: 180, r: 0.70, g: 0.45, b: 0.95, alpha: 0.10) // Purple bridge aura
drawSoftAura(center: CGPoint(x: 120, y: 350), radius: 160, r: 0.98, g: 0.65, b: 0.35, alpha: 0.08) // Warm amber top-left
drawSoftAura(center: CGPoint(x: 540, y: 90), radius: 180, r: 0.40, g: 0.85, b: 0.80, alpha: 0.08)  // Mint bottom-right

// 3. Flowing Dynamic Stream / Wave across the canvas (Connecting Left to Right)
context.saveGState()
let wavePath = CGMutablePath()
wavePath.move(to: CGPoint(x: -20, y: 210))
wavePath.addCurve(to: CGPoint(x: 240, y: 260), control1: CGPoint(x: 70, y: 170), control2: CGPoint(x: 150, y: 270))
wavePath.addCurve(to: CGPoint(x: 440, y: 210), control1: CGPoint(x: 310, y: 255), control2: CGPoint(x: 380, y: 195))
wavePath.addCurve(to: CGPoint(x: 680, y: 240), control1: CGPoint(x: 500, y: 225), control2: CGPoint(x: 590, y: 260))

context.setStrokeColor(CGColor(red: 0.75, green: 0.50, blue: 0.95, alpha: 0.18))
context.setLineWidth(28)
context.setLineCap(.round)
context.addPath(wavePath)
context.strokePath()

// Second overlapping subtle wave
let wavePath2 = CGMutablePath()
wavePath2.move(to: CGPoint(x: -20, y: 250))
wavePath2.addCurve(to: CGPoint(x: 280, y: 190), control1: CGPoint(x: 80, y: 290), control2: CGPoint(x: 190, y: 170))
wavePath2.addCurve(to: CGPoint(x: 680, y: 200), control1: CGPoint(x: 380, y: 210), control2: CGPoint(x: 530, y: 170))

context.setStrokeColor(CGColor(red: 0.96, green: 0.45, blue: 0.65, alpha: 0.15))
context.setLineWidth(20)
context.setLineCap(.round)
context.addPath(wavePath2)
context.strokePath()
context.restoreGState()

// 4. Subtle Liquid Glass Pedestals for the Icons
// Finder top-left: Cowly at (180, 190), Applications at (480, 190)
// CG bottom-left: Y = 420 - 190 = 230
let leftCenter = CGPoint(x: 180, y: 230)
let rightCenter = CGPoint(x: 480, y: 230)
let pedestalSize: CGFloat = 138

for center in [leftCenter, rightCenter] {
    let rect = CGRect(x: center.x - pedestalSize / 2, y: center.y - pedestalSize / 2, width: pedestalSize, height: pedestalSize)
    
    context.saveGState()
    // Soft shadow under the frosted pedestal
    context.setShadow(offset: CGSize(width: 0, height: -4), blur: 18, color: CGColor(red: 0.3, green: 0.35, blue: 0.5, alpha: 0.10))
    
    // Translucent white frosted glass fill
    context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.65))
    context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
    context.setLineWidth(1.8)
    let pPath = CGPath(roundedRect: rect, cornerWidth: 32, cornerHeight: 32, transform: nil)
    context.addPath(pPath)
    context.drawPath(using: .fillStroke)
    
    // Inner delicate border
    context.setStrokeColor(CGColor(red: 0.80, green: 0.82, blue: 0.92, alpha: 0.40))
    context.setLineWidth(1.0)
    let innerRect = rect.insetBy(dx: 1.5, dy: 1.5)
    let innerPath = CGPath(roundedRect: innerRect, cornerWidth: 30.5, cornerHeight: 30.5, transform: nil)
    context.addPath(innerPath)
    context.strokePath()
    context.restoreGState()
}

// 5. Sleek Directional Motion Flow in the Center (between pedestals)
// Center point (330, 230)
let midX: CGFloat = width / 2
let midY: CGFloat = 230

// Floating dynamic arrow / chevrons flying rightward
for (offset, alpha, sz) in [(-22.0, 0.40, 10.0), (0.0, 0.85, 14.0), (24.0, 0.40, 10.0)] {
    let cx = midX + offset
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: CGColor(red: 0.85, green: 0.35, blue: 0.60, alpha: 0.25 * alpha))
    
    let chevPath = CGMutablePath()
    chevPath.move(to: CGPoint(x: cx - sz * 0.6, y: midY + sz))
    chevPath.addLine(to: CGPoint(x: cx + sz * 0.6, y: midY))
    chevPath.addLine(to: CGPoint(x: cx - sz * 0.6, y: midY - sz))
    
    context.setStrokeColor(CGColor(red: 0.88, green: 0.36, blue: 0.62, alpha: alpha))
    context.setLineWidth(sz * 0.32)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(chevPath)
    context.strokePath()
    context.restoreGState()
}

// 6. Floating Translucent Glass Bubbles / Orbs / Droplets
// Each orb has a 3D glass aesthetic:
// - Contact shadow below
// - Spherical radial gradient body
// - Specular reflection dot (light source from top-left)
// - Subtle rim light on the opposite edge

struct FloatingOrb {
    let center: CGPoint
    let radius: CGFloat
    let baseColor: (CGFloat, CGFloat, CGFloat)
    let alpha: CGFloat
    let blur: CGFloat
}

let orbs: [FloatingOrb] = [
    // Hero floating bubbles in the motion stream
    FloatingOrb(center: CGPoint(x: 295, y: 265), radius: 18, baseColor: (0.95, 0.40, 0.65), alpha: 0.65, blur: 0),
    FloatingOrb(center: CGPoint(x: 360, y: 195), radius: 15, baseColor: (0.50, 0.45, 0.95), alpha: 0.60, blur: 0),
    FloatingOrb(center: CGPoint(x: 325, y: 200), radius: 9, baseColor: (0.35, 0.75, 0.95), alpha: 0.55, blur: 0),
    FloatingOrb(center: CGPoint(x: 338, y: 262), radius: 11, baseColor: (0.98, 0.55, 0.70), alpha: 0.60, blur: 0),
    
    // Top drifting bubbles
    FloatingOrb(center: CGPoint(x: 95, y: 350), radius: 32, baseColor: (0.95, 0.45, 0.60), alpha: 0.45, blur: 0),
    FloatingOrb(center: CGPoint(x: 150, y: 380), radius: 16, baseColor: (0.98, 0.65, 0.45), alpha: 0.50, blur: 0),
    FloatingOrb(center: CGPoint(x: 230, y: 345), radius: 24, baseColor: (0.60, 0.45, 0.95), alpha: 0.40, blur: 0),
    FloatingOrb(center: CGPoint(x: 430, y: 370), radius: 28, baseColor: (0.40, 0.65, 0.98), alpha: 0.45, blur: 0),
    FloatingOrb(center: CGPoint(x: 505, y: 340), radius: 20, baseColor: (0.30, 0.82, 0.85), alpha: 0.50, blur: 0),
    FloatingOrb(center: CGPoint(x: 585, y: 375), radius: 36, baseColor: (0.75, 0.45, 0.95), alpha: 0.40, blur: 0),
    
    // Bottom floating orbs
    FloatingOrb(center: CGPoint(x: 70, y: 85), radius: 42, baseColor: (0.85, 0.40, 0.70), alpha: 0.35, blur: 0),
    FloatingOrb(center: CGPoint(x: 135, y: 60), radius: 19, baseColor: (0.95, 0.50, 0.55), alpha: 0.45, blur: 0),
    FloatingOrb(center: CGPoint(x: 220, y: 95), radius: 26, baseColor: (0.55, 0.48, 0.95), alpha: 0.40, blur: 0),
    FloatingOrb(center: CGPoint(x: 320, y: 70), radius: 14, baseColor: (0.40, 0.70, 0.98), alpha: 0.45, blur: 0),
    FloatingOrb(center: CGPoint(x: 440, y: 85), radius: 34, baseColor: (0.35, 0.78, 0.92), alpha: 0.40, blur: 0),
    FloatingOrb(center: CGPoint(x: 520, y: 65), radius: 18, baseColor: (0.45, 0.88, 0.75), alpha: 0.48, blur: 0),
    FloatingOrb(center: CGPoint(x: 605, y: 110), radius: 30, baseColor: (0.80, 0.42, 0.90), alpha: 0.38, blur: 0),
    
    // Side accents
    FloatingOrb(center: CGPoint(x: 42, y: 220), radius: 22, baseColor: (0.92, 0.45, 0.65), alpha: 0.38, blur: 0),
    FloatingOrb(center: CGPoint(x: 625, y: 235), radius: 24, baseColor: (0.40, 0.60, 0.98), alpha: 0.38, blur: 0),
    
    // Tiny floating sparkles / particles
    FloatingOrb(center: CGPoint(x: 190, y: 310), radius: 6, baseColor: (0.98, 0.60, 0.75), alpha: 0.60, blur: 0),
    FloatingOrb(center: CGPoint(x: 270, y: 225), radius: 5, baseColor: (0.80, 0.50, 0.95), alpha: 0.65, blur: 0),
    FloatingOrb(center: CGPoint(x: 395, y: 235), radius: 6, baseColor: (0.40, 0.75, 0.98), alpha: 0.65, blur: 0),
    FloatingOrb(center: CGPoint(x: 465, y: 310), radius: 7, baseColor: (0.35, 0.85, 0.85), alpha: 0.60, blur: 0),
    FloatingOrb(center: CGPoint(x: 375, y: 125), radius: 5, baseColor: (0.90, 0.45, 0.75), alpha: 0.60, blur: 0),
    FloatingOrb(center: CGPoint(x: 275, y: 120), radius: 6, baseColor: (0.60, 0.55, 0.98), alpha: 0.55, blur: 0)
]

for orb in orbs {
    let (r, g, b) = orb.baseColor
    let c = orb.center
    let rad = orb.radius
    
    context.saveGState()
    
    // 1. Contact shadow below bubble
    context.setShadow(
        offset: CGSize(width: 0, height: -rad * 0.35),
        blur: rad * 0.7,
        color: CGColor(red: r * 0.5, green: g * 0.5, blue: b * 0.5, alpha: 0.22 * orb.alpha)
    )
    
    // 2. Base glass sphere with spherical shading
    let orbRect = CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2)
    let sphereColors = [
        CGColor(red: min(r + 0.25, 1.0), green: min(g + 0.25, 1.0), blue: min(b + 0.25, 1.0), alpha: orb.alpha * 0.95),
        CGColor(red: r, green: g, blue: b, alpha: orb.alpha * 0.75),
        CGColor(red: r * 0.75, green: g * 0.75, blue: b * 0.85, alpha: orb.alpha * 0.85)
    ] as CFArray
    let sphereLocs: [CGFloat] = [0.0, 0.60, 1.0]
    
    if let sphereGrad = CGGradient(colorsSpace: colorSpace, colors: sphereColors, locations: sphereLocs) {
        context.addEllipse(in: orbRect)
        context.clip()
        
        let lightCenter = CGPoint(x: c.x - rad * 0.32, y: c.y + rad * 0.32)
        context.drawRadialGradient(
            sphereGrad,
            startCenter: lightCenter,
            startRadius: 0,
            endCenter: c,
            endRadius: rad,
            options: [.drawsAfterEndLocation]
        )
    }
    context.restoreGState()
    
    // 3. Specular highlight (crisp bright reflection from upper-left)
    context.saveGState()
    let specSize = rad * 0.32
    let specCenter = CGPoint(x: c.x - rad * 0.35, y: c.y + rad * 0.35)
    let specRect = CGRect(x: specCenter.x - specSize / 2, y: specCenter.y - specSize * 0.7 / 2, width: specSize, height: specSize * 0.7)
    
    let specColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.88 * orb.alpha),
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
    ] as CFArray
    if let specGrad = CGGradient(colorsSpace: colorSpace, colors: specColors, locations: [0.0, 1.0]) {
        let path = CGPath(ellipseIn: specRect, transform: nil)
        context.addPath(path)
        context.clip()
        context.drawRadialGradient(specGrad, startCenter: specCenter, startRadius: 0, endCenter: specCenter, endRadius: specSize / 2, options: [])
    }
    context.restoreGState()
    
    // 4. Subtle glass rim stroke
    context.saveGState()
    context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.55 * orb.alpha))
    context.setLineWidth(max(rad * 0.06, 0.8))
    context.strokeEllipse(in: orbRect.insetBy(dx: 0.5, dy: 0.5))
    context.restoreGState()
}

// 7. Output image to file (NO TEXT WAS DRAWN ANYWHERE)
guard let cgImage = context.makeImage() else {
    fatalError("Could not generate CGImage")
}

let rep = NSBitmapImageRep(cgImage: cgImage)
rep.size = NSSize(width: width, height: height)

guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not create PNG data")
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Cowly/Resources/dmg_background.png"
let outURL = URL(fileURLWithPath: outPath)
try pngData.write(to: outURL)
print("Apple-grade light DMG background with floating dynamic elements generated at \(outPath)")
