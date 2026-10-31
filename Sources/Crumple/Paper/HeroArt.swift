import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum HeroStyle { case smartClean, largeFiles, duplicates, apps, history }

/// A still life of the files and paper basket. Actual cleaning keeps its throwing animation.
struct HeroScene: View {
    let style: HeroStyle
    let accent: Color

    var body: some View {
        let files = HeroIcons.files
        let apps = HeroIcons.apps
        Canvas { context, size in
            let scale = min(size.width / 520, size.height / 260)
            var drawing = context
            drawing.translateBy(x: (size.width - 520 * scale) / 2, y: (size.height - 260 * scale) / 2)
            drawing.scaleBy(x: scale, y: scale)
            HeroArt.draw(drawing, size: CGSize(width: 520, height: 260), time: 0,
                         style: style, accent: accent, files: files, apps: apps)
        }
        .allowsHitTesting(false)
    }
}

@MainActor
enum HeroIcons {
    /// Movie, archive, disk image, photo.
    static let files: [NSImage] = [UTType.movie, .zip, .diskImage, .jpeg].map { NSWorkspace.shared.icon(for: $0) }

    /// A few installed apps, just for decoration.
    static let apps: [NSImage] = {
        let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"), includingPropertiesForKeys: nil)) ?? []
        let picked = urls.filter { $0.pathExtension == "app" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(5)
        let icons = picked.map { NSWorkspace.shared.icon(forFile: $0.path) }
        return icons.count >= 3 ? Array(icons) : Array(repeating: NSWorkspace.shared.icon(for: .applicationBundle), count: 5)
    }()
}

enum HeroArt {
    static func draw(_ g: GraphicsContext, size: CGSize, time t: Double, style: HeroStyle, accent: Color,
                     files: [NSImage], apps: [NSImage]) {
        let cx = size.width / 2

        let basketWidth: CGFloat
        let basketX: CGFloat
        let pile: Int
        switch style {
        case .smartClean: (basketWidth, basketX, pile) = (150, cx, 6)
        case .largeFiles: (basketWidth, basketX, pile) = (112, cx + 105, 4)
        case .duplicates: (basketWidth, basketX, pile) = (112, cx + 120, 3)
        case .apps: (basketWidth, basketX, pile) = (118, cx, 4)
        case .history: (basketWidth, basketX, pile) = (150, cx, 14)
        }
        let basketHeight = basketWidth * BasketGeometry.size.height / BasketGeometry.size.width
        let basket = BasketGeometry(rect: CGRect(x: basketX - basketWidth / 2, y: size.height - basketHeight - 16,
                                                 width: basketWidth, height: basketHeight))

        BasketArt.drawBack(g, basket, .app)
        BasketArt.drawPile(g, basket, count: pile, opacity: 1)

        // A ball that keeps dropping into the basket (history page).
        var dropping: PaperPose?
        if style == .history {
            let period = 2.4
            let phase = t.truncatingRemainder(dividingBy: period) / period
            let y = lerp(-20, basket.mouth.midY + 26, CGFloat(phase * phase))
            dropping = PaperPose(center: CGPoint(x: cx + 6, y: y), rotation: CGFloat(t * 2), scale: 1.05,
                                 crumple: 1, sheetScale: 1, opacity: phase > 0.82 ? (1 - phase) / 0.18 : 1, phase: .flying)
            if let pose = dropping, pose.center.y > basket.mouth.midY {
                var inside = g
                inside.clip(to: basket.silhouette)
                PaperArt.draw(inside, pose: pose, seed: 31, icon: nil)
            }
        }

        BasketArt.drawFront(g, basket, .app)
        if let pose = dropping, pose.center.y <= basket.mouth.midY {
            PaperArt.draw(g, pose: pose, seed: 31, icon: nil)
        }

        switch style {
        case .smartClean:
            let spots: [CGPoint] = [CGPoint(x: cx - 112, y: 82), CGPoint(x: cx, y: 46), CGPoint(x: cx + 112, y: 82)]
            for (i, spot) in spots.enumerated() {
                let bob = CGFloat(sin(t * 1.4 + Double(i) * 1.3)) * 6
                let pose = PaperPose(center: CGPoint(x: spot.x, y: spot.y + bob), rotation: CGFloat(t * 0.35) + CGFloat(i),
                                     scale: 1.3, crumple: 1, sheetScale: 1, opacity: 1, phase: .flying)
                PaperArt.draw(g, pose: pose, seed: UInt64(50 + i), icon: nil)
            }
            let sheet = PaperPose(center: CGPoint(x: cx - 172, y: 156 + CGFloat(sin(t * 1.1)) * 4),
                                  rotation: -0.32 + CGFloat(sin(t * 0.9)) * 0.04, scale: 1,
                                  crumple: 0.35, sheetScale: 1, opacity: 1, phase: .crumpling)
            PaperArt.draw(g, pose: sheet, seed: 61, icon: nil)
        case .largeFiles:
            for i in 0..<3 {
                let bob = CGFloat(sin(t * 1.2 + Double(i) * 0.9)) * 4
                let offset = CGFloat(i - 1)
                let pose = PaperPose(center: CGPoint(x: cx - 80 + offset * 58, y: 118 + abs(offset) * 14 + bob),
                                     rotation: offset * 0.26 + CGFloat(sin(t * 0.8 + Double(i))) * 0.03, scale: 1,
                                     crumple: 0, sheetScale: 1.6, opacity: 1, phase: .crumpling)
                PaperArt.draw(g, pose: pose, seed: UInt64(70 + i), icon: files[i % max(files.count, 1)])
            }
            let ball = PaperPose(center: CGPoint(x: basketX - 6, y: basket.mouth.minY - 34 + CGFloat(sin(t * 1.6)) * 5),
                                 rotation: CGFloat(t * 0.5), scale: 1.1, crumple: 1, sheetScale: 1, opacity: 1, phase: .flying)
            PaperArt.draw(g, pose: ball, seed: 77, icon: nil)
        case .duplicates:
            // Two identical sheets; the copy on the right is already being crumpled.
            let photo = files.count > 3 ? files[3] : files.first
            let bob = CGFloat(sin(t * 1.2)) * 4
            let original = PaperPose(center: CGPoint(x: cx - 150, y: 122 + bob), rotation: -0.12, scale: 1,
                                     crumple: 0, sheetScale: 1.6, opacity: 1, phase: .crumpling)
            PaperArt.draw(g, pose: original, seed: 81, icon: photo)
            var equals = Path()
            equals.addRoundedRect(in: CGRect(x: cx - 104, y: 112 + bob, width: 22, height: 5), cornerSize: CGSize(width: 2.5, height: 2.5))
            equals.addRoundedRect(in: CGRect(x: cx - 104, y: 124 + bob, width: 22, height: 5), cornerSize: CGSize(width: 2.5, height: 2.5))
            g.fill(equals, with: .color(Theme.secondary.opacity(0.8)))
            let squeeze = 0.22 + 0.06 * CGFloat(sin(t * 1.5))
            let copy = PaperPose(center: CGPoint(x: cx - 34, y: 116 - bob), rotation: 0.16 + CGFloat(sin(t * 0.9)) * 0.03, scale: 1,
                                 crumple: squeeze, sheetScale: 1.6, opacity: 1, phase: .crumpling)
            PaperArt.draw(g, pose: copy, seed: 81, icon: photo)
            let ball = PaperPose(center: CGPoint(x: basketX - 4, y: basket.mouth.minY - 34 + CGFloat(sin(t * 1.6)) * 5),
                                 rotation: CGFloat(t * 0.5), scale: 1.1, crumple: 1, sheetScale: 1, opacity: 1, phase: .flying)
            PaperArt.draw(g, pose: ball, seed: 83, icon: nil)
        case .apps:
            let count = min(apps.count, 5)
            for i in 0..<count {
                let fraction = count > 1 ? CGFloat(i) / CGFloat(count - 1) : 0.5
                let spread = (fraction - 0.5) * 2 // -1…1, a gentle arc above the basket
                let bob = CGFloat(sin(t * 1.3 + Double(i) * 1.1)) * 5
                let center = CGPoint(x: cx + spread * 150, y: 62 + spread * spread * 40 + bob)
                let side: CGFloat = i == count / 2 ? 74 : 58
                g.drawLayer { layer in
                    layer.addFilter(.shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4))
                    layer.translateBy(x: center.x, y: center.y)
                    layer.rotate(by: .radians(Double((fraction - 0.5) * 0.3)))
                    layer.draw(Image(nsImage: apps[i]), in: CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
                }
            }
        case .history:
            break
        }

    }
}
