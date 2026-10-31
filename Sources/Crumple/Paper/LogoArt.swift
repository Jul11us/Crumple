import SwiftUI

/// Candidate logos for Crumple, drawn with the same paper-ball renderer as the app.
enum LogoConcept: String, CaseIterable, Identifiable {
    case ball, arc, basket, buddy

    var id: String { rawValue }

    var letter: String {
        switch self {
        case .ball: "A"
        case .arc: "B"
        case .basket: "C"
        case .buddy: "D"
        }
    }

    var title: String {
        switch self {
        case .ball: "一个纸团"
        case .arc: "抛物线 C"
        case .basket: "纸篓投篮"
        case .buddy: "纸团君"
        }
    }

    var note: String {
        switch self {
        case .ball: "只有一个揉皱的纸团。最简单、最好认，小尺寸和单色都清楚。"
        case .arc: "纸团被扔出去的轨迹弯成字母 C，名字和动作合在一起。"
        case .basket: "纸团飞进纸篓（现在用的图标）。故事最完整，但细节多。"
        case .buddy: "给纸团画上表情，变成吉祥物。最可爱，也最好做周边。"
        }
    }
}

enum LogoArt {
    /// The paper-ball shape picked for the brand: compact and evenly crumpled.
    static let brandBallSeed: UInt64 = 12

    static func draw(_ context: GraphicsContext, side: CGFloat, concept: LogoConcept) {
        if concept == .basket {
            IconArt.drawBasketShot(context, side: side)
            return
        }
        var g = context
        g.scaleBy(x: side / 1024, y: side / 1024)
        switch concept {
        case .ball: drawBall(g)
        case .arc: drawArc(g)
        case .buddy: drawBuddy(g)
        case .basket: break
        }
    }

    /// A: one big faceted paper ball resting on its shadow.
    private static func drawBall(_ g: GraphicsContext) {
        IconArt.drawTile(g, top: Color(hex: 0x4BE0B2), bottom: Color(hex: 0x0A6A5F))
        var inside = g
        inside.clip(to: IconArt.tilePath)
        inside.drawLayer { layer in
            layer.addFilter(.blur(radius: 26))
            layer.fill(Path(ellipseIn: CGRect(x: 300, y: 730, width: 424, height: 80)), with: .color(.black.opacity(0.28)))
        }
        let ball = PaperPose(center: CGPoint(x: 512, y: 500), rotation: 0.2, scale: 19,
                             crumple: 1, sheetScale: 1, opacity: 1, phase: .flying)
        PaperArt.draw(inside, pose: ball, seed: brandBallSeed, icon: nil, shadow: false, lineScale: 0.45, lumpiness: 0.5)
    }

    /// B: the dotted path of a throw curls into a "C" and ends in the paper ball.
    private static func drawArc(_ g: GraphicsContext) {
        IconArt.drawTile(g, top: Color(hex: 0x1F5E56), bottom: Color(hex: 0x0B1D22))
        var inside = g
        inside.clip(to: IconArt.tilePath)
        inside.drawLayer { layer in
            layer.addFilter(.blur(radius: 80))
            layer.fill(Path(ellipseIn: CGRect(x: 230, y: 230, width: 560, height: 560)), with: .color(Color(hex: 0x2ED3A0).opacity(0.35)))
        }
        let center = CGPoint(x: 540, y: 512)
        let radius: CGFloat = 255
        let start = -48.0 * .pi / 180  // upper right
        let end = -306.0 * .pi / 180   // lower right, after going over the top and around the left
        let dots = 15
        for i in 0..<dots {
            let t = Double(i) / Double(dots - 1)
            let angle = start + (end - start) * t
            let r = CGFloat(11 + 15 * t)
            let p = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            inside.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                        with: .color(.white.opacity(0.35 + 0.55 * t)))
        }
        let ballAngle = -318.0 * .pi / 180
        let ball = PaperPose(center: CGPoint(x: center.x + radius * cos(ballAngle), y: center.y + radius * sin(ballAngle)),
                             rotation: 0.2, scale: 8.2, crumple: 1, sheetScale: 1, opacity: 1, phase: .flying)
        PaperArt.draw(inside, pose: ball, seed: brandBallSeed, icon: nil, lineScale: 0.7, lumpiness: 0.5)
    }

    /// D: the paper ball with a face — a mascot.
    private static func drawBuddy(_ g: GraphicsContext) {
        IconArt.drawTile(g, top: Color(hex: 0x6DE8BE), bottom: Color(hex: 0x1C9A83))
        var inside = g
        inside.clip(to: IconArt.tilePath)
        inside.drawLayer { layer in
            layer.addFilter(.blur(radius: 26))
            layer.fill(Path(ellipseIn: CGRect(x: 310, y: 740, width: 404, height: 74)), with: .color(.black.opacity(0.25)))
        }
        let ball = PaperPose(center: CGPoint(x: 512, y: 512), rotation: 0.1, scale: 18,
                             crumple: 1, sheetScale: 1, opacity: 1, phase: .flying)
        PaperArt.draw(inside, pose: ball, seed: 20, icon: nil, shadow: false, lineScale: 0.45, lumpiness: 0.45) // the roundest shape, good for a face

        let ink = Color(hex: 0x1E2A2C)
        for x in [446.0, 578.0] {
            inside.fill(Path(ellipseIn: CGRect(x: x - 22, y: 470, width: 44, height: 58)), with: .color(ink))
            inside.fill(Path(ellipseIn: CGRect(x: x - 9, y: 480, width: 16, height: 18)), with: .color(.white))
        }
        for x in [392.0, 632.0] {
            inside.fill(Path(ellipseIn: CGRect(x: x - 34, y: 560, width: 68, height: 32)), with: .color(Color(hex: 0xFF8FA3).opacity(0.45)))
        }
        var smile = Path()
        smile.move(to: CGPoint(x: 476, y: 572))
        smile.addQuadCurve(to: CGPoint(x: 548, y: 572), control: CGPoint(x: 512, y: 616))
        inside.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 16, lineCap: .round))

        // A little sparkle, as if it just got tidied up.
        let spark = CGPoint(x: 735, y: 300)
        var star = Path()
        let r: CGFloat = 34
        star.move(to: CGPoint(x: spark.x, y: spark.y - r))
        star.addQuadCurve(to: CGPoint(x: spark.x + r, y: spark.y), control: spark)
        star.addQuadCurve(to: CGPoint(x: spark.x, y: spark.y + r), control: spark)
        star.addQuadCurve(to: CGPoint(x: spark.x - r, y: spark.y), control: spark)
        star.addQuadCurve(to: CGPoint(x: spark.x, y: spark.y - r), control: spark)
        inside.fill(star, with: .color(.white.opacity(0.9)))
    }
}

/// One logo option as shown on a comparison sheet.
struct LogoEntry: Identifiable {
    let letter: String
    let title: String
    let note: String
    let icon: (GraphicsContext, CGFloat) -> Void
    /// The bare mark in one colour: (context, side, ink, colour of the cut-out lines).
    var mono: ((GraphicsContext, CGFloat, Color, Color) -> Void)? = nil

    var id: String { letter }
}

extension LogoConcept {
    var entry: LogoEntry {
        LogoEntry(letter: letter, title: title, note: note, icon: { LogoArt.draw($0, side: $1, concept: self) })
    }
}

struct LogoIcon: View {
    let draw: (GraphicsContext, CGFloat) -> Void

    var body: some View {
        Canvas { context, size in draw(context, size.width) }
    }
}

/// Side-by-side comparison of logo options: big icon, small sizes, single-colour versions,
/// and the name lockup on dark and light.
struct LogoSheet: View {
    let title: String
    let subtitle: String
    let entries: [LogoEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 34, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 22) {
                ForEach(entries) { ConceptColumn(entry: $0) }
            }
        }
        .padding(48)
        .background(Color(hex: 0xF3F4F6))
        .environment(\.colorScheme, .light)
    }

    private struct ConceptColumn: View {
        let entry: LogoEntry

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Text(entry.letter)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(hex: 0x16A085)))
                    Text(entry.title).font(.system(size: 20, weight: .semibold))
                }
                Text(entry.note)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 40, alignment: .top)

                LogoIcon(draw: entry.icon)
                    .frame(width: 300, height: 300)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .bottom, spacing: 22) {
                    ForEach([64, 32, 16], id: \.self) { size in
                        VStack(spacing: 6) {
                            LogoIcon(draw: entry.icon).frame(width: CGFloat(size), height: CGFloat(size))
                            Text("\(size)").font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                }

                if let mono = entry.mono {
                    HStack(spacing: 12) {
                        monoSwatch(mono, ink: Color(hex: 0x14181D), cut: .white, background: .white)
                        monoSwatch(mono, ink: .white, cut: Color(hex: 0x15181E), background: Color(hex: 0x15181E))
                        Text("单色版（菜单栏、印刷）").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }

                lockup(dark: true)
                lockup(dark: false)
            }
            .frame(width: 330)
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        }

        private func monoSwatch(_ mono: @escaping (GraphicsContext, CGFloat, Color, Color) -> Void,
                                ink: Color, cut: Color, background: Color) -> some View {
            Canvas { context, size in mono(context, size.width, ink, cut) }
                .frame(width: 64, height: 64)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(background))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.08)))
        }

        private func lockup(dark: Bool) -> some View {
            HStack(spacing: 12) {
                LogoIcon(draw: entry.icon).frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Crumple").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("把垃圾揉成纸团").font(.system(size: 12)).opacity(0.6)
                }
                .foregroundStyle(dark ? Color.white : Color(hex: 0x14181D))
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(dark ? Color(hex: 0x15181E) : Color(hex: 0xF3F4F6)))
        }
    }
}
