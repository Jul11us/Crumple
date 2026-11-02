import SwiftUI
import AppKit

// MARK: - Paper

enum PaperArt {
    static let sheet = CGSize(width: 46, height: 58)
    static let foldSize: CGFloat = 11
    static let ballRadius: CGFloat = 14

    /// The sheet outline (with a dog-eared corner), sampled into evenly spaced points.
    /// Each point is later pulled toward a lumpy circle as the sheet is crumpled.
    private static let fineOutline = sheetOutline(count: 34)
    private static let coarseOutline = sheetOutline(count: 20)

    private static func sheetOutline(count: Int) -> [CGPoint] {
        let w = sheet.width, h = sheet.height, f = foldSize
        return resample([
            CGPoint(x: -w / 2, y: -h / 2), CGPoint(x: w / 2 - f, y: -h / 2), CGPoint(x: w / 2, y: -h / 2 + f),
            CGPoint(x: w / 2, y: h / 2), CGPoint(x: -w / 2, y: h / 2),
        ], count: count)
    }

    private static func resample(_ polygon: [CGPoint], count: Int) -> [CGPoint] {
        let edges = polygon.indices.map { (polygon[$0], polygon[($0 + 1) % polygon.count]) }
        let lengths = edges.map { hypot($0.1.x - $0.0.x, $0.1.y - $0.0.y) }
        let total = lengths.reduce(0, +)
        var points: [CGPoint] = []
        for (edge, length) in zip(edges, lengths) {
            let steps = max(1, Int((CGFloat(count) * length / total).rounded()))
            for j in 0..<steps {
                let t = CGFloat(j) / CGFloat(steps)
                points.append(CGPoint(x: lerp(edge.0.x, edge.1.x, t), y: lerp(edge.0.y, edge.1.y, t)))
            }
        }
        return points
    }

    static func draw(_ context: GraphicsContext, pose: PaperPose, seed: UInt64, icon: NSImage?,
                     tint: Color? = nil, shadow: Bool = true, coarse: Bool = false, lineScale: CGFloat = 1,
                     lumpiness: CGFloat = 1) {
        guard pose.opacity > 0.001 else { return }
        var g = context
        g.opacity *= pose.opacity
        g.translateBy(x: pose.center.x, y: pose.center.y)
        g.rotate(by: .radians(pose.rotation))
        g.scaleBy(x: pose.scale, y: pose.scale)

        let c = pose.crumple
        let s = pose.sheetScale
        let w = sheet.width * s
        let h = sheet.height * s
        let wrinkle = sin(.pi * c)

        // Morph the flat sheet into a lumpy ball.
        var shapeRng = SeededRandom(seed)
        let phase1 = shapeRng.range(0, 2 * .pi)
        let phase2 = shapeRng.range(0, 2 * .pi)
        var points: [CGPoint] = []
        for base in coarse ? coarseOutline : fineOutline {
            let p = CGPoint(x: base.x * s, y: base.y * s)
            let angle = atan2(p.y, p.x)
            let lumps = 0.11 * sin(3 * angle + phase1) + 0.07 * sin(5 * angle + phase2)
            let r = ballRadius * (1 + (lumps + shapeRng.range(-0.08, 0.08)) * lumpiness)
            let jitterX = shapeRng.range(-1, 1) * 5 * s * wrinkle
            let jitterY = shapeRng.range(-1, 1) * 5 * s * wrinkle
            points.append(CGPoint(x: lerp(p.x, cos(angle) * r, c) + jitterX, y: lerp(p.y, sin(angle) * r, c) + jitterY))
        }
        let outline = Path { path in
            path.addLines(points)
            path.closeSubpath()
        }

        // Light always comes from the top-left of the screen, whatever the ball's spin.
        let lightAngle = -0.75 * .pi - pose.rotation
        let light = CGPoint(x: cos(lightAngle), y: sin(lightAngle))

        if shadow {
            let back = -pose.rotation
            let dx = (1.2 * cos(back) - 2.6 * sin(back)) / pose.scale
            let dy = (1.2 * sin(back) + 2.6 * cos(back)) / pose.scale
            g.drawLayer { layer in
                layer.addFilter(.blur(radius: 2.2))
                layer.translateBy(x: dx, y: dy)
                layer.fill(outline, with: .color(.black.opacity(0.16 + 0.08 * c)))
            }
        }

        let reach = lerp(max(w, h) / 2, ballRadius, c)
        g.fill(outline, with: .linearGradient(
            Gradient(colors: [Color(white: 1), Color(white: 0.86)]),
            startPoint: CGPoint(x: light.x * reach, y: light.y * reach),
            endPoint: CGPoint(x: -light.x * reach, y: -light.y * reach)
        ))

        if c > 0.02 {
            drawFacets(g, outline: points, seed: seed, crumple: c, lightAngle: lightAngle, lineScale: lineScale)
        }

        // The flat page: file icon, a few lines of "text", and a folded corner. Fades as it crumples.
        let faceAlpha = max(0, 1 - Double(c) / 0.4)
        if faceAlpha > 0 {
            var face = g
            face.opacity *= faceAlpha
            face.scaleBy(x: 1 - c * 0.6, y: 1 - c * 0.6)
            if let icon {
                let side = 22 * s
                face.draw(Image(nsImage: icon), in: CGRect(x: -side / 2, y: -h / 2 + 8 * s, width: side, height: side))
            }
            for (i, fraction) in [0.86, 0.68, 0.78].enumerated() {
                let y = -h / 2 + (36 + CGFloat(i) * 6.5) * s
                let x0 = -w / 2 + 7 * s
                var line = Path()
                line.move(to: CGPoint(x: x0, y: y))
                line.addLine(to: CGPoint(x: x0 + (w - 14 * s) * fraction, y: y))
                face.stroke(line, with: .color(Color(white: 0.78)), style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
            }
            let f = foldSize * s
            let ear = Path { path in
                path.move(to: CGPoint(x: w / 2 - f, y: -h / 2))
                path.addLine(to: CGPoint(x: w / 2 - f, y: -h / 2 + f))
                path.addLine(to: CGPoint(x: w / 2, y: -h / 2 + f))
                path.closeSubpath()
            }
            face.fill(ear, with: .linearGradient(
                Gradient(colors: [Color(white: 0.8), Color(white: 0.95)]),
                startPoint: CGPoint(x: w / 2 - f, y: -h / 2 + f),
                endPoint: CGPoint(x: w / 2 - f / 2, y: -h / 2 + f / 2)
            ))
            face.stroke(ear, with: .color(Color(white: 0.62)), lineWidth: 0.7)
        }

        g.stroke(outline, with: .color(Color(white: 0.45).opacity(0.55)), style: StrokeStyle(lineWidth: 0.8 * lineScale, lineJoin: .round))
        if let tint {
            g.fill(outline, with: .color(tint.opacity(0.28)))
        }
    }

    /// Low-poly shading and crease lines that make the ball read as crumpled paper.
    private static func drawFacets(_ g: GraphicsContext, outline points: [CGPoint], seed: UInt64, crumple c: CGFloat,
                                   lightAngle: CGFloat, lineScale: CGFloat) {
        var rng = SeededRandom(seed &+ 0x51ED)
        let ring = 6
        let inner: [CGPoint] = (0..<ring).map { i in
            let a = CGFloat(i) / CGFloat(ring) * 2 * .pi + rng.range(-0.4, 0.4)
            let r = ballRadius * rng.range(0.25, 0.55)
            return CGPoint(x: cos(a) * r, y: sin(a) * r)
        }
        let core = CGPoint(x: rng.range(-2, 2), y: rng.range(-2, 2))

        func shade(_ triangle: Path, facing angle: CGFloat, noise: CGFloat) {
            let lit = cos(angle - lightAngle)
            let dark = (0.5 - 0.5 * lit) * 0.9 + noise
            if dark > 0.45 {
                g.fill(triangle, with: .color(.black.opacity(Double(min(0.2, (dark - 0.45) * 0.35) * c))))
            } else {
                g.fill(triangle, with: .color(.white.opacity(Double(min(0.55, (0.45 - dark) * 0.7) * c))))
            }
        }

        var creases = Path()
        for i in points.indices {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            var angle = atan2((a.y + b.y) / 2, (a.x + b.x) / 2)
            if angle < 0 { angle += 2 * .pi }
            let k = Int(angle / (2 * .pi) * CGFloat(ring) + 0.5) % ring
            let triangle = Path { path in
                path.move(to: inner[k])
                path.addLine(to: a)
                path.addLine(to: b)
                path.closeSubpath()
            }
            shade(triangle, facing: angle, noise: rng.range(-0.35, 0.35))
            if i % 3 == 0 {
                creases.move(to: inner[k])
                creases.addLine(to: a)
            }
        }
        for i in 0..<ring {
            let a = inner[i]
            let b = inner[(i + 1) % ring]
            let triangle = Path { path in
                path.move(to: core)
                path.addLine(to: a)
                path.addLine(to: b)
                path.closeSubpath()
            }
            shade(triangle, facing: atan2((a.y + b.y) / 2, (a.x + b.x) / 2), noise: rng.range(-0.45, 0.45))
            creases.move(to: a)
            creases.addLine(to: b)
        }
        g.stroke(creases, with: .color(Color(white: 0.4).opacity(Double(0.3 * c))), style: StrokeStyle(lineWidth: 0.6 * lineScale, lineCap: .round))
    }
}

// MARK: - Basket

struct BasketGeometry {
    static let size = CGSize(width: 108, height: 104)
    static let trailingInset: CGFloat = 26
    static let bottomInset: CGFloat = 20
    /// Space the bottom bar leaves free for the basket.
    static var reservedTrailing: CGFloat { trailingInset + size.width + 18 }

    static func rect(in canvas: CGSize) -> CGRect {
        CGRect(x: canvas.width - trailingInset - size.width, y: canvas.height - bottomInset - size.height,
               width: size.width, height: size.height)
    }

    let rect: CGRect

    var scale: CGFloat { rect.width / BasketGeometry.size.width }
    var mouth: CGRect { CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.width * 0.3) }
    var base: CGRect {
        let w = rect.width * 0.7
        let h = w * 0.3
        return CGRect(x: rect.midX - w / 2, y: rect.maxY - h, width: w, height: h)
    }

    /// An ellipse between the mouth (t = 0) and the base (t = 1).
    func ring(_ t: CGFloat) -> CGRect {
        CGRect(x: lerp(mouth.minX, base.minX, t), y: lerp(mouth.minY, base.minY, t),
               width: lerp(mouth.width, base.width, t), height: lerp(mouth.height, base.height, t))
    }

    static func point(on r: CGRect, angle a: CGFloat) -> CGPoint {
        CGPoint(x: r.midX + r.width / 2 * cos(a), y: r.midY + r.height / 2 * sin(a))
    }

    static func arc(_ r: CGRect, from a0: CGFloat, to a1: CGFloat, steps: Int = 28) -> [CGPoint] {
        (0...steps).map { point(on: r, angle: a0 + (a1 - a0) * CGFloat($0) / CGFloat(steps)) }
    }

    /// The whole basket outline seen from the front.
    var silhouette: Path {
        Path { path in
            path.addLines(Self.arc(mouth, from: .pi, to: 2 * .pi) + Self.arc(base, from: 0, to: .pi))
            path.closeSubpath()
        }
    }

    /// The front wall, between the front half of the rim and the front half of the base.
    var frontWall: Path {
        Path { path in
            path.addLines(Self.arc(mouth, from: 0, to: .pi) + Self.arc(base, from: .pi, to: 0))
            path.closeSubpath()
        }
    }
}

struct BasketStyle {
    var rim: Color
    var slat: Color
    var wall: Color
    var interior: Color
    var shadow: Double

    /// Charcoal wire, like the hoop in the logo (pale wire on dark paper).
    static let app = BasketStyle(
        rim: .themed(\.basketRim),
        slat: .themed(\.basketSlat),
        wall: .themed(\.basketWall),
        interior: .themed(\.basketInside),
        shadow: 0.14
    )
    static let icon = BasketStyle(
        rim: .white,
        slat: .white.opacity(0.95),
        wall: .white,
        interior: Color(red: 0.02, green: 0.24, blue: 0.23),
        shadow: 0.22
    )
}

enum BasketArt {
    static let slats = 10

    static func drawBack(_ g: GraphicsContext, _ b: BasketGeometry, _ style: BasketStyle) {
        let k = b.scale
        g.drawLayer { layer in
            layer.addFilter(.blur(radius: 5 * k))
            let r = b.base.insetBy(dx: -10 * k, dy: 0).offsetBy(dx: 0, dy: b.base.height * 0.35)
            layer.fill(Path(ellipseIn: r), with: .color(.black.opacity(style.shadow)))
        }
        g.fill(b.silhouette, with: .color(style.wall.opacity(0.14)))
        g.fill(Path(ellipseIn: b.mouth), with: .linearGradient(
            Gradient(colors: [style.interior.opacity(0.78), style.interior.opacity(0.42)]),
            startPoint: CGPoint(x: b.mouth.midX, y: b.mouth.minY),
            endPoint: CGPoint(x: b.mouth.midX, y: b.mouth.maxY)
        ))
        var back = Path()
        for i in 0..<slats {
            let a = .pi + .pi * (CGFloat(i) + 0.5) / CGFloat(slats)
            back.move(to: BasketGeometry.point(on: b.mouth, angle: a))
            back.addLine(to: BasketGeometry.point(on: b.base, angle: a))
        }
        g.stroke(back, with: .color(style.slat.opacity(0.35)), lineWidth: 1.4 * k)
        var rim = Path()
        rim.addLines(BasketGeometry.arc(b.mouth, from: .pi, to: 2 * .pi))
        g.stroke(rim, with: .color(style.rim.opacity(0.9)), style: StrokeStyle(lineWidth: 3.5 * k, lineCap: .round))
    }

    static func drawFront(_ g: GraphicsContext, _ b: BasketGeometry, _ style: BasketStyle) {
        let k = b.scale
        g.fill(b.frontWall, with: .linearGradient(
            Gradient(colors: [style.wall.opacity(0.32), style.wall.opacity(0.16), style.wall.opacity(0.28)]),
            startPoint: CGPoint(x: b.rect.minX, y: b.rect.midY),
            endPoint: CGPoint(x: b.rect.maxX, y: b.rect.midY)
        ))
        var bands = Path()
        for t: CGFloat in [0.36, 0.7] {
            bands.addLines(BasketGeometry.arc(b.ring(t), from: 0, to: .pi))
        }
        g.stroke(bands, with: .color(style.slat), lineWidth: 1.5 * k)

        var front = Path()
        for i in 0...slats {
            let a = .pi * CGFloat(i) / CGFloat(slats)
            front.move(to: BasketGeometry.point(on: b.mouth, angle: a))
            front.addLine(to: BasketGeometry.point(on: b.base, angle: a))
        }
        g.stroke(front, with: .color(style.slat), style: StrokeStyle(lineWidth: 1.8 * k, lineCap: .round))

        var bottom = Path()
        bottom.addLines(BasketGeometry.arc(b.base, from: 0, to: .pi))
        g.stroke(bottom, with: .color(style.rim), style: StrokeStyle(lineWidth: 3 * k, lineCap: .round))

        var rim = Path()
        rim.addLines(BasketGeometry.arc(b.mouth, from: 0, to: .pi))
        g.stroke(rim, with: .color(style.rim), style: StrokeStyle(lineWidth: 4.5 * k, lineCap: .round))
        var shine = Path()
        shine.addLines(BasketGeometry.arc(b.mouth.offsetBy(dx: 0, dy: -1.2 * k), from: 0.18 * .pi, to: 0.62 * .pi))
        g.stroke(shine, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1.2 * k, lineCap: .round))
    }

    /// Paper balls already in the basket. It fills quickly at first, then more slowly.
    static func drawPile(_ g: GraphicsContext, _ b: BasketGeometry, count: Int, opacity: Double) {
        guard count > 0, opacity > 0 else { return }
        let r = 10.5 * b.scale
        let slots = pileSlots(b, radius: r)
        let shown: Int
        if count <= 8 {
            shown = min(count, slots.count)
        } else {
            let extra = Double(slots.count - 8) * (1 - exp(-Double(count - 8) / 40))
            shown = min(slots.count, 8 + Int(extra))
        }
        for (i, slot) in slots.prefix(shown).enumerated() {
            var rng = SeededRandom(UInt64(i) &* 7919 &+ 17)
            let pose = PaperPose(center: slot, rotation: rng.range(0, 2 * .pi), scale: r / PaperArt.ballRadius,
                                 crumple: 1, sheetScale: 1, opacity: opacity, phase: .sinking)
            PaperArt.draw(g, pose: pose, seed: rng.next(), icon: nil, shadow: false, coarse: true)
        }
    }

    private static func pileSlots(_ b: BasketGeometry, radius r: CGFloat) -> [CGPoint] {
        var rng = SeededRandom(77)
        var slots: [CGPoint] = []
        var y = b.base.midY - r * 0.55
        while y >= b.mouth.midY + r * 0.2 {
            let t = (y - b.mouth.midY) / (b.base.midY - b.mouth.midY)
            let width = lerp(b.mouth.width, b.base.width, t) * 0.78
            let n = max(1, Int(width / (r * 1.75)))
            let spacing = width / CGFloat(n)
            let middle = CGFloat(n - 1) / 2
            for j in (0..<n).sorted(by: { abs(CGFloat($0) - middle) < abs(CGFloat($1) - middle) }) {
                let x = b.rect.midX - width / 2 + spacing * (CGFloat(j) + 0.5) + rng.range(-2, 2) * b.scale
                slots.append(CGPoint(x: x, y: y + rng.range(-1.5, 1.5) * b.scale))
            }
            y -= r * 1.3
        }
        return slots
    }
}

// MARK: - Whole stage

enum StageRenderer {
    static func draw(_ context: GraphicsContext, size: CGSize, now: Double, snapshot: StageSnapshot) {
        let basket = BasketGeometry(rect: BasketGeometry.rect(in: size))

        // The basket wobbles and squashes a little each time something lands.
        var bg = context
        let sinceLanding = now - snapshot.lastLanding
        if sinceLanding >= 0 && sinceLanding < 1.6 {
            let angle = 0.075 * exp(-sinceLanding * 5.5) * sin(sinceLanding * 24)
            let squash = CGFloat(0.06 * exp(-sinceLanding * 11) * cos(sinceLanding * 30))
            let pivot = CGPoint(x: basket.rect.midX, y: basket.rect.maxY)
            bg.translateBy(x: pivot.x, y: pivot.y)
            bg.rotate(by: .radians(angle))
            bg.scaleBy(x: 1 + squash * 0.6, y: 1 - squash)
            bg.translateBy(x: -pivot.x, y: -pivot.y)
        }

        // The rim glows when a paper in hand gets close: green to aim, red if it won't go in.
        if let held = snapshot.held {
            let distance = hypot(held.location.x - basket.mouth.midX, held.location.y - basket.mouth.midY)
            let glow = max(0, 1 - Double(distance) / 220) * 0.6
            if glow > 0 {
                let color = held.blocked ? Color.red : Color.brand
                bg.drawLayer { layer in
                    layer.addFilter(.blur(radius: 10))
                    layer.fill(Path(ellipseIn: basket.mouth.insetBy(dx: -10, dy: -7)), with: .color(color.opacity(glow)))
                }
            }
        }

        BasketArt.drawBack(bg, basket, .app)
        var pileOpacity = 1.0
        if let cleared = snapshot.pileClearedAt {
            pileOpacity = 1 - clamp01((now - cleared) / 0.5)
        }
        BasketArt.drawPile(bg, basket, count: snapshot.pileCount, opacity: pileOpacity)

        // Papers going into the basket are clipped by it; the rest are drawn after the front wall.
        var inside = bg
        inside.clip(to: basket.silhouette)
        var inFront: [(pose: PaperPose, seed: UInt64, icon: NSImage?, tint: Color?)] = []
        func place(_ pose: PaperPose, seed: UInt64, icon: NSImage?) {
            switch pose.phase {
            case .sinking: PaperArt.draw(inside, pose: pose, seed: seed, icon: nil)
            case .bouncing: inFront.append((pose, seed, nil, .red))
            case .loose: inFront.append((pose, seed, icon, nil))
            case .crumpling, .flying: PaperArt.draw(context, pose: pose, seed: seed, icon: icon)
            }
        }
        for paper in snapshot.papers {
            let elapsed = now - paper.born
            guard elapsed >= 0, elapsed <= paper.lifetime else { continue }
            place(paper.pose(at: elapsed), seed: paper.seed, icon: paper.icon)
        }
        for toss in snapshot.tossed {
            let elapsed = now - toss.born
            guard elapsed >= 0, elapsed <= toss.lifetime else { continue }
            place(toss.pose(at: elapsed), seed: toss.seed, icon: toss.icon)
        }

        BasketArt.drawFront(bg, basket, .app)
        for paper in inFront {
            PaperArt.draw(context, pose: paper.pose, seed: paper.seed, icon: paper.icon, tint: paper.tint)
        }
        if let held = snapshot.held {
            PaperArt.draw(context, pose: held.pose(at: now), seed: held.seed, icon: held.icon)
        }
    }
}

// MARK: - App icon

enum IconArt {
    /// Draws the app icon into a square of the given side length: a paper ball tossed at a
    /// basketball hoop, in charcoal on off-white (logo option H, chosen by the user).
    static func draw(_ context: GraphicsContext, side: CGFloat) {
        BinLogo.drawIcon(context, side: side, design: .hoop, palette: BinPalette.cream[0])
    }

    /// The first icon: a paper ball flying into a wire basket on green (logo option C).
    static func drawBasketShot(_ context: GraphicsContext, side: CGFloat) {
        var g = context
        g.scaleBy(x: side / 1024, y: side / 1024)
        drawTile(g, top: Color(red: 0.38, green: 0.87, blue: 0.71), bottom: Color(red: 0.04, green: 0.50, blue: 0.48))

        let basket = BasketGeometry(rect: CGRect(x: 312, y: 480, width: 400, height: 370))
        BasketArt.drawBack(g, basket, .icon)
        BasketArt.drawPile(g, basket, count: 5, opacity: 1)
        BasketArt.drawFront(g, basket, .icon)

        var trail = Path()
        trail.move(to: CGPoint(x: 205, y: 560))
        trail.addQuadCurve(to: CGPoint(x: 500, y: 300), control: CGPoint(x: 250, y: 290))
        g.stroke(trail, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 20, lineCap: .round, dash: [1, 52]))

        let ball = PaperPose(center: CGPoint(x: 600, y: 320), rotation: 0.5, scale: 6.6,
                             crumple: 1, sheetScale: 1, opacity: 1, phase: .flying)
        PaperArt.draw(g, pose: ball, seed: 3, icon: nil)
    }

    /// The macOS icon tile (a continuous rounded square on the 1024 grid) with a soft shadow and top sheen.
    static let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    static var tilePath: Path { Path(roundedRect: tileRect, cornerRadius: 185, style: .continuous) }

    static func drawTile(_ g: GraphicsContext, top: Color, bottom: Color) {
        let tile = tilePath
        g.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 10))
            layer.fill(tile, with: .linearGradient(Gradient(colors: [top, bottom]),
                                                   startPoint: CGPoint(x: 512, y: 100), endPoint: CGPoint(x: 512, y: 924)))
        }
        var sheen = g
        sheen.clip(to: tile)
        sheen.fill(Path(ellipseIn: CGRect(x: -100, y: -440, width: 1224, height: 900)), with: .color(.white.opacity(0.10)))
    }
}
