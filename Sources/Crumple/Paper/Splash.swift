import SwiftUI
import AppKit
import CoreText

/// Launch animation: "Crumple" appears letter by letter, the m lights up, then a paper ball
/// rolls along the strokes of the m and, at the foot of its last leg, drops into the hoop below.
enum Splash {
    static let duration = 4.0

    static let letterStart = 0.15
    static let letterGap = 0.11
    static let letterDuration = 0.42
    static let highlightStart = 1.15
    static let highlightDuration = 0.4
    static let hoopStart = 1.35
    static let ballStart = 1.55
    static let traceStart = 1.7
    static let traceDuration = 1.25
    static let dropDuration = 0.32
    static let sinkDuration = 0.4
    static var dropStart: Double { traceStart + traceDuration }
    static var landTime: Double { dropStart + dropDuration }

    /// Position of the "m" in "Crumple".
    static let mIndex = 3

    static let cream = Color(hex: 0xF4EDE0)
    static let charcoal = Color(hex: 0x2E2C29)
}

/// "Crumple" set in SF Rounded, as one outline per letter (baseline at y = 0, y pointing down),
/// so each letter can be animated on its own and the m's strokes can be traced exactly.
struct SplashLayout {
    let glyphs: [(path: Path, bounds: CGRect)]
    let width: CGFloat
    let capHeight: CGFloat

    @MainActor static let word = make(text: "Crumple", size: 112)

    private static func make(text: String, size: CGFloat) -> SplashLayout {
        let base = NSFont.systemFont(ofSize: size, weight: .heavy)
        let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .kern: size * 0.02]))
        var glyphs: [(Path, CGRect)] = []
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var ids = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &ids)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            for i in 0..<count {
                var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: positions[i].x, ty: -positions[i].y)
                guard let outline = CTFontCreatePathForGlyph(runFont, ids[i], &flip) else { continue }
                let path = Path(outline)
                glyphs.append((path, path.boundingRect))
            }
        }
        return SplashLayout(glyphs: glyphs, width: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)), capHeight: font.capHeight)
    }

    /// The pen path of the m: up the left stem, over the first arch, down the middle stem and back up,
    /// over the second arch, and down the right stem. Sampled into points.
    func mStroke() -> [CGPoint] {
        let b = glyphs[Splash.mIndex].bounds
        let stem = b.width * 0.13
        let left = b.minX + b.width * 0.115
        let middle = b.minX + b.width * 0.5
        let right = b.minX + b.width * 0.885
        let top = b.minY + stem * 0.5
        let shoulder = b.minY + b.height * 0.32
        let bottom = b.maxY - stem * 0.4

        var points: [CGPoint] = []
        func line(_ from: CGPoint, _ to: CGPoint) {
            for i in 0...10 { points.append(CGPoint(x: lerp(from.x, to.x, CGFloat(i) / 10), y: lerp(from.y, to.y, CGFloat(i) / 10))) }
        }
        func quad(_ from: CGPoint, _ control: CGPoint, _ to: CGPoint) {
            for i in 0...14 {
                let t = CGFloat(i) / 14, u = 1 - t
                points.append(CGPoint(x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                                      y: u * u * from.y + 2 * u * t * control.y + t * t * to.y))
            }
        }
        func arch(from x0: CGFloat, to x1: CGFloat) {
            let peak = CGPoint(x: (x0 + x1) / 2, y: top)
            quad(CGPoint(x: x0, y: shoulder), CGPoint(x: x0, y: top), peak)
            quad(peak, CGPoint(x: x1, y: top), CGPoint(x: x1, y: shoulder))
        }
        line(CGPoint(x: left, y: bottom), CGPoint(x: left, y: shoulder))
        arch(from: left, to: middle)
        line(CGPoint(x: middle, y: shoulder), CGPoint(x: middle, y: bottom))
        line(CGPoint(x: middle, y: bottom), CGPoint(x: middle, y: shoulder))
        arch(from: middle, to: right)
        line(CGPoint(x: right, y: shoulder), CGPoint(x: right, y: bottom))
        return points
    }
}

enum SplashArt {
    static func draw(_ context: GraphicsContext, size: CGSize, t: Double, layout: SplashLayout, stroke: [CGPoint]) {
        let cream = Splash.cream
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [Color(hex: 0x37342F), Color(hex: 0x1C1B19)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))

        let highlight = CGFloat(easeInOutCubic(clamp01((t - Splash.highlightStart) / Splash.highlightDuration)))
        let origin = CGPoint(x: (size.width - layout.width) / 2, y: size.height * 0.4 + layout.capHeight / 2)
        let landed = CGFloat(easeInOutCubic(clamp01((t - Splash.landTime - 0.05) / 0.4)))
        // While the ball writes the m, the real letter fades to a guide; it comes back once the ball drops off.
        let ghost = CGFloat(easeInOutCubic(clamp01((t - Splash.traceStart + 0.25) / 0.25)))
        let reveal = CGFloat(easeInOutCubic(clamp01((t - Splash.dropStart) / 0.35)))

        // Soft glow behind the m while it is the star.
        let mBounds = layout.glyphs[Splash.mIndex].bounds.offsetBy(dx: origin.x, dy: origin.y)
        if highlight > 0 {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 40))
                layer.fill(Path(ellipseIn: mBounds.insetBy(dx: -30, dy: -30)), with: .color(cream.opacity(0.14 * highlight * (1 - landed))))
            }
        }

        // Letters, one after another, with a little overshoot.
        for (i, glyph) in layout.glyphs.enumerated() {
            let appear = clamp01((t - Splash.letterStart - Double(i) * Splash.letterGap) / Splash.letterDuration)
            guard appear > 0 else { continue }
            let pop = CGFloat(easeOutBack(appear))
            var g = context
            g.opacity = min(1, appear * 1.8)
            if i == Splash.mIndex {
                g.opacity *= Double(1 - 0.78 * ghost * (1 - reveal))
            } else {
                g.opacity *= Double(1 - 0.72 * highlight * (1 - landed))
            }
            let center = CGPoint(x: origin.x + glyph.bounds.midX, y: origin.y + glyph.bounds.midY + (1 - pop) * 28)
            let scale = 0.84 + 0.16 * pop
            g.translateBy(x: center.x, y: center.y)
            g.scaleBy(x: scale, y: scale)
            g.translateBy(x: -glyph.bounds.midX, y: -glyph.bounds.midY)
            g.fill(glyph.path, with: .color(cream))
        }

        // The paper ball: writes the m, then falls off the foot of its last leg into the hoop below.
        let ballRadius: CGFloat = 25
        let path = stroke.map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) }
        var lengths: [CGFloat] = [0]
        for i in 1..<max(path.count, 1) {
            lengths.append(lengths[i - 1] + hypot(path[i].x - path[i - 1].x, path[i].y - path[i - 1].y))
        }
        let total = lengths.last ?? 0
        func point(at distance: CGFloat) -> CGPoint {
            guard let i = lengths.firstIndex(where: { $0 >= distance }), i > 0 else { return path.first ?? .zero }
            let span = lengths[i] - lengths[i - 1]
            let f = span > 0 ? (distance - lengths[i - 1]) / span : 0
            return CGPoint(x: lerp(path[i - 1].x, path[i].x, f), y: lerp(path[i - 1].y, path[i].y, f))
        }

        // The hoop hangs right under the m's last leg, so the ball just keeps going down into it.
        let end = point(at: total)
        let hoopWidth: CGFloat = 124
        let ringCenter = CGPoint(x: end.x, y: origin.y + 74)
        let hoopScale = hoopWidth / BinLogo.hoopRing.width
        let hoopIn = CGFloat(easeOutBack(clamp01((t - Splash.hoopStart) / 0.4)))
        let sink = clamp01((t - Splash.landTime) / Splash.sinkDuration)
        let swish = CGFloat(sin(.pi * sink)) * 0.22
        func drawHoop() {
            guard hoopIn > 0 else { return }
            var g = context
            g.opacity = Double(min(1, hoopIn))
            g.translateBy(x: ringCenter.x, y: ringCenter.y)
            g.scaleBy(x: hoopScale * (0.8 + 0.2 * hoopIn), y: hoopScale * (0.8 + 0.2 * hoopIn))
            g.translateBy(x: -BinLogo.hoopRing.midX, y: -BinLogo.hoopRing.midY)
            BinLogo.drawHoop(g, ink: cream, stretch: 1 + swish)
        }

        let traced = CGFloat(easeInOutSine(clamp01((t - Splash.traceStart) / Splash.traceDuration))) * total
        if t > Splash.traceStart, !path.isEmpty, reveal < 1 {
            // The m as written so far, in a stroke as thick as the letter's stems; it hands over to the
            // real letter once the ball is thrown.
            var written = Path()
            written.move(to: path[0])
            for (i, p) in path.enumerated() where lengths[i] <= traced { written.addLine(to: p) }
            written.addLine(to: point(at: traced))
            context.stroke(written, with: .color(cream.opacity(Double(1 - reveal))),
                           style: StrokeStyle(lineWidth: layout.glyphs[Splash.mIndex].bounds.width * 0.155,
                                              lineCap: .round, lineJoin: .round))
        }

        var ball: (center: CGPoint, rotation: CGFloat, scale: CGFloat, opacity: Double)?
        if t >= Splash.ballStart && t < Splash.dropStart {
            let popIn = CGFloat(easeOutBack(clamp01((t - Splash.ballStart) / 0.25)))
            ball = (point(at: traced), traced / ballRadius, popIn, 1)
        } else if t >= Splash.dropStart && t < Splash.landTime {
            // Carries straight on down the leg, speeding up, into the ring.
            let u = CGFloat(clamp01((t - Splash.dropStart) / Splash.dropDuration))
            let p = CGPoint(x: end.x, y: lerp(end.y, ringCenter.y, u * u))
            ball = (p, (total + (p.y - end.y)) / ballRadius, 1, 1)
        } else if t >= Splash.landTime && sink < 1 {
            let k = CGFloat(sink)
            let fall = (ringCenter.y - end.y) + k * k * 84
            ball = (CGPoint(x: ringCenter.x, y: end.y + fall), (total + fall) / ballRadius, 1, 1 - Double(k) * 0.9)
        }

        // In the net the ball is behind the strings; everywhere else it is in front.
        let inNet = t >= Splash.landTime
        if inNet, let ball { drawBall(context, ball, radius: ballRadius) }
        drawHoop()
        if !inNet, let ball { drawBall(context, ball, radius: ballRadius) }

        // Tagline once it's in.
        let tagline = clamp01((t - Splash.landTime - 0.1) / 0.4)
        if tagline > 0 {
            var g = context
            g.opacity = tagline
            g.draw(Text("把垃圾揉成纸团").font(.system(size: 18, weight: .medium)).foregroundStyle(cream.opacity(0.7)),
                   at: CGPoint(x: size.width / 2, y: ringCenter.y + 150 + CGFloat(1 - tagline) * 8))
        }
    }

    private static func drawBall(_ context: GraphicsContext, _ ball: (center: CGPoint, rotation: CGFloat, scale: CGFloat, opacity: Double), radius: CGFloat) {
        var g = context
        g.opacity = ball.opacity
        g.translateBy(x: ball.center.x, y: ball.center.y)
        g.rotate(by: .radians(ball.rotation))
        let s = radius / 78 * ball.scale
        g.scaleBy(x: s, y: s)
        // A dark edge keeps the ball readable while it rolls over the off-white strokes.
        MinimalLogo.drawBall(g, center: .zero, radius: 78, ink: .white, cut: Splash.charcoal, detailed: false, outline: Splash.charcoal)
    }
}

func easeOutBack(_ x: Double) -> Double {
    let c1 = 1.70158, c3 = c1 + 1
    return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
}

func easeInOutSine(_ x: Double) -> Double { -(cos(.pi * x) - 1) / 2 }

/// Full-window launch animation. Click anywhere to skip.
struct SplashView: View {
    let start: Date
    let onSkip: () -> Void

    var body: some View {
        let layout = SplashLayout.word
        let stroke = layout.mStroke()
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                SplashArt.draw(context, size: size, t: timeline.date.timeIntervalSince(start), layout: layout, stroke: stroke)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSkip)
    }
}
