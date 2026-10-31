import SwiftUI

/// Variations of logo H (a paper ball tossed into a basket): different baskets and background colours.
struct BinPalette: Identifiable {
    let name: String
    let top: Color
    let bottom: Color
    /// Lines cut into the white shapes (a shade of the background).
    let cut: Color
    /// The inside of the basket's opening, darker than the background.
    let hole: Color
    /// Colour of the basket, ball and dots.
    var ink: Color = .white

    var id: String { name }

    /// Off-white backgrounds need dark marks, so these flip it: coloured ink on cream.
    static let cream: [BinPalette] = [
        (name: "米白 · 墨黑", ink: Color(hex: 0x2E2C29), hole: Color(hex: 0x77705F)),
        (name: "米白 · 深海蓝", ink: Color(hex: 0x22396E), hole: Color(hex: 0x6F83B3)),
        (name: "米白 · 森林绿", ink: Color(hex: 0x1D6B57), hole: Color(hex: 0x6FA898)),
        (name: "米白 · 赤陶", ink: Color(hex: 0xC4553A), hole: Color(hex: 0xE6A08B)),
    ].map {
        BinPalette(name: $0.name, top: Color(hex: 0xFBF7EF), bottom: Color(hex: 0xECE2CF),
                   cut: Color(hex: 0xF4EDE0), hole: $0.hole, ink: $0.ink)
    }

    static let all: [BinPalette] = [
        BinPalette(name: "深海蓝", top: Color(hex: 0x3A5BA8), bottom: Color(hex: 0x1A2A5C), cut: Color(hex: 0x2A4282), hole: Color(hex: 0x111C40)),
        BinPalette(name: "珊瑚橙", top: Color(hex: 0xFF9873), bottom: Color(hex: 0xEA5638), cut: Color(hex: 0xF27352), hole: Color(hex: 0xB93A22)),
        BinPalette(name: "葡萄紫", top: Color(hex: 0xA286FF), bottom: Color(hex: 0x5E3FD6), cut: Color(hex: 0x7D5FEE), hole: Color(hex: 0x3F25A3)),
        BinPalette(name: "牛皮纸", top: Color(hex: 0xE6BC84), bottom: Color(hex: 0xC2864A), cut: Color(hex: 0xD29F63), hole: Color(hex: 0x8F5A2B)),
        BinPalette(name: "墨黑", top: Color(hex: 0x3D434C), bottom: Color(hex: 0x181B20), cut: Color(hex: 0x2C3139), hole: Color(hex: 0x0B0C0F)),
    ]
}

enum BinDesign: String, CaseIterable, Identifiable {
    case wire, hoop, woven

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wire: "铁丝网篓"
        case .hoop: "篮球框"
        case .woven: "编织篓"
        }
    }

    var note: String {
        switch self {
        case .wire: "敞口 + 斜网格，和应用里的纸篓是同一个"
        case .hoop: "篮筐 + 网兜，突出“投进去”的手感"
        case .woven: "交错编织纹，更温和、更像家里的纸篓"
        }
    }
}

enum BinLogo {
    static func drawIcon(_ context: GraphicsContext, side: CGFloat, design: BinDesign, palette: BinPalette) {
        var g = context
        g.scaleBy(x: side / 1024, y: side / 1024)
        let tile = IconArt.tilePath
        g.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 10))
            layer.fill(tile, with: .linearGradient(Gradient(colors: [palette.top, palette.bottom]),
                                                   startPoint: CGPoint(x: 512, y: 100), endPoint: CGPoint(x: 512, y: 924)))
        }
        var inside = g
        inside.clip(to: tile)
        drawMark(inside, design: design, ink: palette.ink, cut: palette.cut, hole: palette.hole)
    }

    /// The mark on the 1024 grid: the basket, the paper ball above its opening, and the throw's dotted trail.
    static func drawMark(_ g: GraphicsContext, design: BinDesign, ink: Color, cut: Color, hole: Color) {
        let rim = CGRect(x: 302, y: 488, width: 420, height: 96)
        switch design {
        case .wire:
            let body = basketBody(top: rim.midY, topHalfWidth: 206, bottom: 800, bottomHalfWidth: 132)
            g.fill(body, with: .color(ink))
            var mesh = g
            mesh.clip(to: body)
            var wires = Path()
            for offset in stride(from: -1100.0, through: 1100.0, by: 66.0) {
                wires.move(to: CGPoint(x: offset, y: 0))
                wires.addLine(to: CGPoint(x: offset + 1024, y: 1024))
                wires.move(to: CGPoint(x: offset + 1024, y: 0))
                wires.addLine(to: CGPoint(x: offset, y: 1024))
            }
            mesh.stroke(wires, with: .color(cut), lineWidth: 17)
            g.stroke(body, with: .color(ink), style: StrokeStyle(lineWidth: 24, lineJoin: .round))
            drawRim(g, rim: rim, ink: ink, hole: hole)

        case .hoop:
            drawHoop(g, ink: ink)

        case .woven:
            let body = basketBody(top: rim.midY, topHalfWidth: 200, bottom: 798, bottomHalfWidth: 150)
            g.fill(body, with: .color(ink))
            var weave = g
            weave.clip(to: body)
            // Rows of short strands, each row offset by half a strand, like wicker.
            var strands = Path()
            for (row, y) in [606.0, 676.0, 746.0].enumerated() {
                strands.move(to: CGPoint(x: 280, y: y))
                strands.addQuadCurve(to: CGPoint(x: 744, y: y), control: CGPoint(x: 512, y: y + 26))
                let shift = row.isMultiple(of: 2) ? 0.0 : 36.0
                for x in stride(from: 330.0 + shift, through: 700.0, by: 72.0) {
                    strands.move(to: CGPoint(x: x, y: y - 64))
                    strands.addLine(to: CGPoint(x: x, y: y - 10))
                }
            }
            weave.stroke(strands, with: .color(cut), style: StrokeStyle(lineWidth: 15, lineCap: .round))
            drawRim(g, rim: rim, ink: ink, hole: hole)
        }

        // On a light background a dark ball looks like coal, so it becomes white paper with an inked edge.
        if ink == .white {
            MinimalLogo.drawBall(g, center: CGPoint(x: 566, y: 316), radius: 78, ink: ink, cut: cut, detailed: false)
        } else {
            MinimalLogo.drawBall(g, center: CGPoint(x: 566, y: 316), radius: 80, ink: .white, cut: ink, detailed: false, outline: ink)
        }
        for (x, y, radius) in [(300.0, 410.0, 13.0), (348.0, 334.0, 15.0), (414.0, 282.0, 17.0)] {
            g.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)), with: .color(ink))
        }
    }

    /// The ring (centred at 512, 512 on the 1024 grid) and a net that tapers down and stays open at the bottom.
    /// `stretch` > 1 pulls the net down, for the swish when a ball drops through.
    static let hoopRing = CGRect(x: 322, y: 470, width: 380, height: 84)

    static func drawHoop(_ g: GraphicsContext, ink: Color, stretch: CGFloat = 1) {
        let ring = hoopRing
        let bottom = CGRect(x: 422, y: ring.midY + (742 + 17 - ring.midY) * stretch - 17, width: 180, height: 34)
        var net = Path()
        let count = 6
        func point(_ r: CGRect, _ i: Int) -> CGPoint {
            let a = Double.pi * Double(i) / Double(count)
            return CGPoint(x: r.midX + r.width / 2 * cos(a), y: r.midY + r.height / 2 * sin(a))
        }
        for i in 0..<count {
            net.move(to: point(ring, i))
            net.addLine(to: point(bottom, i + 1))
            net.move(to: point(ring, i + 1))
            net.addLine(to: point(bottom, i))
        }
        let middle = CGRect(x: (ring.minX + bottom.minX) / 2, y: (ring.minY + bottom.minY) / 2,
                            width: (ring.width + bottom.width) / 2, height: (ring.height + bottom.height) / 2)
        net.addLines((0...24).map { i in
            let a = Double.pi * Double(i) / 24
            return CGPoint(x: middle.midX + middle.width / 2 * cos(a), y: middle.midY + middle.height / 2 * sin(a))
        })
        g.stroke(net, with: .color(ink), style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
        g.stroke(Path(ellipseIn: ring), with: .color(ink), lineWidth: 34)
    }

    /// A tapered body with a gently rounded bottom.
    private static func basketBody(top: CGFloat, topHalfWidth: CGFloat, bottom: CGFloat, bottomHalfWidth: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 512 - topHalfWidth, y: top))
            path.addLine(to: CGPoint(x: 512 - bottomHalfWidth, y: bottom))
            path.addQuadCurve(to: CGPoint(x: 512 + bottomHalfWidth, y: bottom), control: CGPoint(x: 512, y: bottom + 34))
            path.addLine(to: CGPoint(x: 512 + topHalfWidth, y: top))
            path.closeSubpath()
        }
    }

    /// An open rim seen from slightly above: a white ring around a dark opening.
    private static func drawRim(_ g: GraphicsContext, rim: CGRect, ink: Color, hole: Color) {
        g.fill(Path(ellipseIn: rim), with: .color(ink))
        g.fill(Path(ellipseIn: rim.insetBy(dx: 30, dy: 18)), with: .color(hole))
    }
}

/// Every basket in every colour, for picking a combination.
struct BinVariantsSheet: View {
    var title = "H · 纸篓 × 背景色"
    var subtitle = "三种纸篓，五种背景色。告诉我行和列，比如“编织篓 · 牛皮纸”。"
    var palettes = BinPalette.all
    var background = Color(hex: 0xF3F4F6)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 34, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                Color.clear.frame(width: 170, height: 1)
                ForEach(palettes) { palette in
                    HStack(spacing: 8) {
                        Circle().fill(palette.ink == .white ? palette.bottom : palette.ink).frame(width: 14, height: 14)
                        Text(palette.name).font(.system(size: 16, weight: .semibold))
                    }
                    .frame(width: 200)
                }
            }
            ForEach(BinDesign.allCases) { design in
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(design.title).font(.system(size: 20, weight: .semibold))
                        Text(design.note).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            LogoIcon(draw: { BinLogo.drawIcon($0, side: $1, design: design, palette: palettes[0]) })
                                .frame(width: 32, height: 32)
                            LogoIcon(draw: { BinLogo.drawIcon($0, side: $1, design: design, palette: palettes[0]) })
                                .frame(width: 16, height: 16)
                        }
                        .padding(.top, 6)
                    }
                    .frame(width: 170, alignment: .leading)
                    ForEach(palettes) { palette in
                        LogoIcon(draw: { BinLogo.drawIcon($0, side: $1, design: design, palette: palette) })
                            .frame(width: 200, height: 200)
                    }
                }
            }
        }
        .padding(48)
        .background(background)
        .environment(\.colorScheme, .light)
    }
}
