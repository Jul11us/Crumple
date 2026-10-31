import SwiftUI

/// Flat, minimal logo options: a few solid shapes on the brand green, no shading,
/// and each mark also works in a single colour.
enum MinimalLogo: String, CaseIterable, Identifiable {
    case flatBall, toss, monogram, bin

    var id: String { rawValue }

    var letter: String {
        switch self {
        case .flatBall: "E"
        case .toss: "F"
        case .monogram: "G"
        case .bin: "H"
        }
    }

    var title: String {
        switch self {
        case .flatBall: "扁平纸团"
        case .toss: "扔出去"
        case .monogram: "字母 C"
        case .bin: "极简纸篓"
        }
    }

    var note: String {
        switch self {
        case .flatBall: "一个白色纸团加几道折痕，像路标一样一眼就懂。"
        case .toss: "纸团带着速度线飞出去：扔掉、放下，最有断舍离的感觉。"
        case .monogram: "粗粗的字母 C，开口处飞出一个小纸团，名字和动作都在里面。"
        case .bin: "图形化的纸篓 + 纸团 + 三个点，讲完整的故事但只用几笔。"
        }
    }

    var entry: LogoEntry {
        LogoEntry(letter: letter, title: title, note: note,
                  icon: { drawIcon($0, side: $1) },
                  mono: { context, side, ink, cut in
                      var g = context
                      g.scaleBy(x: side / 1024, y: side / 1024)
                      drawMark(g, ink: ink, cut: cut)
                  })
    }

    private static let top = Color(hex: 0x30CF9F)
    private static let bottom = Color(hex: 0x13977D)
    private static let cut = Color(hex: 0x1DAF8C)

    func drawIcon(_ context: GraphicsContext, side: CGFloat) {
        var g = context
        g.scaleBy(x: side / 1024, y: side / 1024)
        let tile = IconArt.tilePath
        g.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 10))
            layer.fill(tile, with: .linearGradient(Gradient(colors: [Self.top, Self.bottom]),
                                                   startPoint: CGPoint(x: 512, y: 100), endPoint: CGPoint(x: 512, y: 924)))
        }
        var inside = g
        inside.clip(to: tile)
        drawMark(inside, ink: .white, cut: Self.cut)
    }

    /// The mark on the 1024 grid, in `ink`, with folds and slots drawn in `cut`.
    private func drawMark(_ g: GraphicsContext, ink: Color, cut: Color) {
        switch self {
        case .flatBall:
            Self.drawBall(g, center: CGPoint(x: 512, y: 512), radius: 262, ink: ink, cut: cut, detailed: true)

        case .toss:
            // The ball flies up and to the right; speed lines trail behind it.
            let center = CGPoint(x: 612, y: 420)
            let r: CGFloat = 188
            let direction = CGPoint(x: cos(-0.7), y: sin(-0.7))
            let across = CGPoint(x: -direction.y, y: direction.x)
            var lines = Path()
            for (offset, length) in [(-0.55, 110.0), (0.0, 200.0), (0.55, 140.0)] as [(CGFloat, CGFloat)] {
                let k = offset * r
                let edge = sqrt(max(r * r - k * k, 0)) + 46
                let end = CGPoint(x: center.x + across.x * k - direction.x * edge, y: center.y + across.y * k - direction.y * edge)
                lines.move(to: end)
                lines.addLine(to: CGPoint(x: end.x - direction.x * length, y: end.y - direction.y * length))
            }
            g.stroke(lines, with: .color(ink), style: StrokeStyle(lineWidth: 42, lineCap: .round))
            Self.drawBall(g, center: center, radius: r, ink: ink, cut: cut, detailed: true)

        case .monogram:
            let center = CGPoint(x: 482, y: 545)
            let r: CGFloat = 222
            var c = Path()
            c.addLines(stride(from: 52.0, through: 308.0, by: 4.0).map { degrees in
                let a = degrees * .pi / 180
                return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
            })
            g.stroke(c, with: .color(ink), style: StrokeStyle(lineWidth: 118, lineCap: .round, lineJoin: .round))
            Self.drawBall(g, center: CGPoint(x: 750, y: 248), radius: 76, ink: ink, cut: cut, detailed: false)

        case .bin:
            // Rim, body with rounded corners, and three slots cut out.
            g.fill(Path(roundedRect: CGRect(x: 318, y: 478, width: 388, height: 62), cornerRadius: 31), with: .color(ink))
            let body = Path { $0.addLines([CGPoint(x: 366, y: 560), CGPoint(x: 658, y: 560),
                                           CGPoint(x: 622, y: 806), CGPoint(x: 402, y: 806)]); $0.closeSubpath() }
            g.fill(body, with: .color(ink))
            g.stroke(body, with: .color(ink), style: StrokeStyle(lineWidth: 34, lineJoin: .round))
            var slots = Path()
            for (top, bottom) in [(CGPoint(x: 450, y: 600), CGPoint(x: 462, y: 770)),
                                  (CGPoint(x: 512, y: 600), CGPoint(x: 512, y: 770)),
                                  (CGPoint(x: 574, y: 600), CGPoint(x: 562, y: 770))] {
                slots.move(to: top)
                slots.addLine(to: bottom)
            }
            g.stroke(slots, with: .color(cut), style: StrokeStyle(lineWidth: 24, lineCap: .round))

            Self.drawBall(g, center: CGPoint(x: 566, y: 318), radius: 78, ink: ink, cut: cut, detailed: false)
            for (x, y, radius) in [(296.0, 414.0, 13.0), (344.0, 338.0, 15.0), (412.0, 286.0, 17.0)] {
                g.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)), with: .color(ink))
            }
        }
    }

    /// A flat crumpled ball: an uneven outline, and creases that zigzag from edge to edge and branch,
    /// splitting the ball into facets the way folds do on real crumpled paper.
    /// `outline`, if given, draws an edge around the ball (for a white ball on a light background).
    static func drawBall(_ g: GraphicsContext, center: CGPoint, radius r: CGFloat, ink: Color, cut: Color, detailed: Bool,
                         outline edge: Color? = nil) {
        let radii: [CGFloat] = [1.0, 0.9, 1.04, 0.93, 0.98, 0.88, 1.03, 0.92, 1.0, 0.9, 0.97]
        let jitter: [Double] = [0, 5, -4, 6, -3, 4, -6, 3, -2, 5, -4]
        let outline = Path { path in
            path.addLines(radii.indices.map { i in
                let a = (-90 + Double(i) * 360 / Double(radii.count) + jitter[i]) * .pi / 180
                return CGPoint(x: center.x + cos(a) * r * radii[i], y: center.y + sin(a) * r * radii[i])
            })
            path.closeSubpath()
        }
        g.fill(outline, with: .color(ink))
        g.stroke(outline, with: .color(edge ?? ink), style: StrokeStyle(lineWidth: r * (edge == nil ? 0.06 : 0.13), lineJoin: .round))

        let main: [(CGFloat, CGFloat)] = [(-0.86, -0.3), (-0.34, -0.08), (-0.06, -0.34), (0.26, 0.04), (0.84, -0.12)]
        let folds: [[(CGFloat, CGFloat)]] = detailed
            ? [main, [(-0.06, -0.34), (0.12, -0.84)], [(0.26, 0.04), (0.04, 0.82)], [(-0.34, -0.08), (-0.56, 0.5)]]
            : [main, [(0.26, 0.04), (0.04, 0.82)]]
        var path = Path()
        for fold in folds {
            path.addLines(fold.map { CGPoint(x: center.x + $0.0 * r, y: center.y + $0.1 * r) })
        }
        g.stroke(path, with: .color(cut), style: StrokeStyle(lineWidth: max(11, r * 0.058), lineCap: .round, lineJoin: .round))
    }
}
