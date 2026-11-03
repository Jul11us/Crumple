import SwiftUI
import AppKit

/// Offscreen rendering and a read-only scan report, for building and checking the app.
enum DevTools {
    /// Reproducible visual checks of the real SwiftUI views, isolated from personal files.
    @MainActor
    static func renderInterface(to dir: URL) {
        guard Paths.isDemo else {
            print("Set CRUMPLE_DEMO_HOME to a temporary folder to render interface previews.")
            return
        }
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel()
        let variants: [(String, ColorScheme, CGFloat, CGFloat)] = [
            ("mist", .light, 1180, 780),
            ("kraft", .light, 1180, 780),
            ("dark-compact", .dark, 1100, 720),
        ]
        func render(_ page: Page, _ name: String, _ scheme: ColorScheme, _ width: CGFloat, _ height: CGFloat) {
            NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            model.page = page
            let view = HStack(spacing: 0) {
                SidebarView().frame(width: Theme.sidebarWidth).background(Theme.sidebar)
                Rectangle().fill(Theme.stroke).frame(width: 1)
                ZStack {
                    PageBackground()
                    interfacePage(page)
                }
                .clipped()
            }
            .environment(model)
            .environment(\.colorScheme, scheme)
            .tint(Theme.accent)
            .foregroundStyle(Theme.primary)
            .frame(width: width, height: height)
            .background(Theme.base)
            writeInterfacePNG(view, width: width, height: height, to: dir.appendingPathComponent("\(name).png"))
        }
        for (name, scheme, width, height) in variants {
            Palette.light = name == "kraft" ? .kraft : .mist
            for page in [Page.overview, .smartClean, .largeFiles, .duplicates, .uninstaller] {
                render(page, "\(page.rawValue)-\(name)", scheme, width, height)
            }
        }

        // With --states, also walk the demo through scans, a clean and the other pages.
        guard CommandLine.arguments.contains("--states") else {
            print("Interface previews: \(dir.path)")
            return
        }
        func pump(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func wait(_ done: () -> Bool) {
            let end = Date().addingTimeInterval(30)
            while !done() && Date() < end { pump(0.1) }
            pump(0.6)
        }
        for (name, scheme, width, height) in variants {
            Palette.light = name == "kraft" ? .kraft : .mist
            model.startSmartScan(); wait { model.smartPhase == .results }
            render(.smartClean, "smartClean-results-\(name)", scheme, width, height)
            model.openReview(); pump(0.6)
            render(.smartClean, "smartClean-review-\(name)", scheme, width, height)
            if name == "mist" {
                model.requestSmartClean(); wait { model.smartPhase == .done }; pump(1.6)
                render(.smartClean, "smartClean-done-\(name)", scheme, width, height)
                model.finishSmartClean()
            }
            model.scanLargeFiles(); wait { model.filesPhase == .results }
            render(.largeFiles, "largeFiles-results-\(name)", scheme, width, height)
            model.scanDuplicates(); wait { model.dupPhase == .results }
            render(.duplicates, "duplicates-results-\(name)", scheme, width, height)
            model.scanApps(); wait { model.appsPhase == .results }
            render(.uninstaller, "uninstaller-results-\(name)", scheme, width, height)
            for page in [Page.status, .analysis, .optimize, .history] {
                render(page, "\(page.rawValue)-\(name)", scheme, width, height)
                pump(3)
                render(page, "\(page.rawValue)-\(name)", scheme, width, height)
            }
        }
        print("Interface previews: \(dir.path)")
    }

    @MainActor @ViewBuilder
    private static func interfacePage(_ page: Page) -> some View {
        switch page {
        case .overview: OverviewPage()
        case .smartClean: SmartCleanPage()
        case .largeFiles: LargeFilesPage()
        case .duplicates: DuplicatesPage()
        case .uninstaller: UninstallerPage()
        case .status: StatusPage()
        case .analysis: AnalysisPage()
        case .optimize: OptimizePage()
        case .history: HistoryPage()
        }
    }

    /// ImageRenderer omits AppKit-backed content such as ScrollView. Host the interface
    /// in an undisplayed window so those views participate in layout and drawing too.
    @MainActor
    private static func writeInterfacePNG<V: View>(_ view: V, width: CGFloat, height: CGFloat, to url: URL) {
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = rect
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: rect) else {
            print("render failed: \(url.lastPathComponent)")
            window.close()
            return
        }
        host.cacheDisplay(in: rect, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
        window.close()
    }

    @MainActor
    static func renderIconSet(to dir: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sizes: [(String, CGFloat)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, side) in sizes {
            let view = Canvas { context, size in IconArt.draw(context, side: size.width) }
                .frame(width: side, height: side)
            writePNG(view, scale: 1, to: dir.appendingPathComponent("\(name).png"))
        }
    }

    /// Stills of the launch animation: a contact sheet over time, plus two full-size frames.
    @MainActor
    static func renderSplash(to dir: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let layout = SplashLayout.word
        let stroke = layout.mStroke()
        let window = CGSize(width: 1180, height: 780)
        let times: [Double] = [0.35, 0.8, 1.3, 1.75, 2.15, 2.5, 2.85, 3.1, 3.35, 3.9]
        let sheet = VStack(spacing: 14) {
            ForEach(0..<2) { row in
                HStack(spacing: 14) {
                    ForEach(0..<5) { column in
                        let t = times[row * 5 + column]
                        VStack(spacing: 4) {
                            Canvas { context, _ in
                                var g = context
                                g.scaleBy(x: 0.4, y: 0.4)
                                SplashArt.draw(g, size: window, t: t, layout: layout, stroke: stroke)
                            }
                            .frame(width: window.width * 0.4, height: window.height * 0.4)
                            Text(String(format: "%.2f 秒", t)).font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white)
        writePNG(sheet, scale: 2, to: dir.appendingPathComponent("splash-frames.png"))
        for t in [2.5, 3.15] {
            let frame = Canvas { context, size in SplashArt.draw(context, size: size, t: t, layout: layout, stroke: stroke) }
                .frame(width: window.width, height: window.height)
            writePNG(frame, scale: 1, to: dir.appendingPathComponent(String(format: "splash-%.2f.png", t)))
        }
    }

    /// Each logo concept at 1024 px, plus a comparison sheet of all of them.
    @MainActor
    static func renderLogos(to dir: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let detailed = LogoConcept.allCases.map { ($0.entry, $0.rawValue) }
        let minimal = MinimalLogo.allCases.map { ($0.entry, $0.rawValue) }
        for (entry, name) in detailed + minimal {
            let icon = LogoIcon(draw: entry.icon).frame(width: 1024, height: 1024)
            writePNG(icon, scale: 1, to: dir.appendingPathComponent("logo-\(entry.letter)-\(name).png"))
        }
        writePNG(LogoSheet(title: "Crumple · Logo 方案",
                           subtitle: "每个方案：大图标、程序坞 / 菜单栏等小尺寸，以及和名字放在一起的样子",
                           entries: detailed.map(\.0)),
                 scale: 2, to: dir.appendingPathComponent("logo-concepts.png"))
        writePNG(LogoSheet(title: "Crumple · 简洁版 Logo",
                           subtitle: "只用几块平面形状，没有渐变和阴影；每个都有单色版，放进菜单栏或印出来也清楚",
                           entries: minimal.map(\.0)),
                 scale: 2, to: dir.appendingPathComponent("logo-minimal.png"))
        writePNG(BinVariantsSheet(), scale: 2, to: dir.appendingPathComponent("logo-H-variants.png"))
        writePNG(BinVariantsSheet(title: "H · 米白色",
                                  subtitle: "米白底 + 深色线条，像印章一样干净。灰底上能看清米白图标的边缘。",
                                  palettes: BinPalette.cream, background: Color(hex: 0xDADCE0)),
                 scale: 2, to: dir.appendingPathComponent("logo-H-cream.png"))
    }

    /// The installer window background (600×400, plus @2x). Icon spots match make-dmg.sh:
    /// the app at (150, 200) and the Applications link at (450, 200).
    @MainActor
    static func renderDMGBackground(to dir: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let view = DMGBackground().frame(width: 600, height: 400)
        writePNG(view, scale: 1, to: dir.appendingPathComponent("background.png"))
        writePNG(view, scale: 2, to: dir.appendingPathComponent("background@2x.png"))
    }

    /// The menu bar icon on a light and a dark bar, and the panel with a few seconds of live readings.
    @MainActor
    static func renderMenuBar(to dir: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let icons = HStack(spacing: 0) {
            ForEach([(Color(white: 0.92), Color.black), (Color(white: 0.16), Color.white)], id: \.0) { bar, ink in
                HStack(spacing: 14) {
                    Image(systemName: "wifi").foregroundStyle(ink)
                    Image(nsImage: MenuBarIcon.image).renderingMode(.template).foregroundStyle(ink)
                    Text("10:42").font(.system(size: 13)).foregroundStyle(ink)
                }
                .padding(.horizontal, 14)
                .frame(height: 24)
                .background(bar)
            }
        }
        writePNG(icons, scale: 4, to: dir.appendingPathComponent("menubar-icon.png"))

        let model = AppModel()
        model.monitor.start()
        RunLoop.main.run(until: Date().addingTimeInterval(5))
        // ImageRenderer has no presentation window, so preferredColorScheme alone has no effect.
        let scheme = model.appearance.colorScheme
            ?? (NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light)
        writePNG(MenuBarPanel().environment(model).background(Theme.base).environment(\.colorScheme, scheme), scale: 2,
                 to: dir.appendingPathComponent("menubar-panel.png"))
        model.monitor.stop()
    }

    /// The shredder at a few moments: a sheet flying in, going through the slot, strips falling.
    @MainActor
    static func renderShredder(to dir: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let size = CGSize(width: 420, height: 420)
        let basket = BasketGeometry(rect: BasketGeometry.rect(in: size))
        let shredder = ShredderGeometry(rect: ShredderGeometry.rect(above: basket))
        let icon = NSWorkspace.shared.icon(forFile: "/Applications/Safari.app")
        let paper = Paper(born: 0, origin: CGPoint(x: 70, y: 300), basket: basket, succeeded: true, seed: 3, icon: icon,
                          shredder: shredder)
        let moments = [0.4, paper.landTime - 0.15, paper.landTime + 0.22, paper.landTime + 0.6]
        for (scheme, name) in [(ColorScheme.light, "light"), (.dark, "dark")] {
            NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let row = HStack(spacing: 8) {
                ForEach(moments, id: \.self) { t in
                    let snapshot = StageSnapshot(papers: [paper], pileCount: 4, shredderShownAt: -10,
                                                 stripCount: 6, lastShred: t > paper.landTime ? paper.landTime + 0.15 : nil)
                    Canvas { context, size in StageRenderer.draw(context, size: size, now: t, snapshot: snapshot) }
                        .frame(width: size.width, height: size.height)
                        .background(Theme.base)
                }
            }
            .environment(\.colorScheme, scheme)
            writePNG(row, scale: 1, to: dir.appendingPathComponent("shredder-\(name).png"))
        }
    }

    /// Stills of the paper animation: a strobe of whole throws, and the crumple stages up close.
    @MainActor
    static func renderPreviews(to dir: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let icon = NSWorkspace.shared.icon(forFile: "/Applications/Safari.app")
        let size = CGSize(width: 900, height: 560)
        let basket = BasketGeometry(rect: BasketGeometry.rect(in: size))
        let good = Paper(born: 0, origin: CGPoint(x: 110, y: 170), basket: basket, succeeded: true, seed: 42, icon: icon)
        let bad = Paper(born: 0, origin: CGPoint(x: 330, y: 380), basket: basket, succeeded: false, seed: 7, icon: icon)

        let strobe = Canvas { context, canvasSize in
            context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(Color(white: 0.97)))
            StageRenderer.draw(context, size: canvasSize, now: 100, snapshot: StageSnapshot(pileCount: 14))
            for t in stride(from: 0.0, through: good.lifetime, by: 0.075) {
                PaperArt.draw(context, pose: good.pose(at: t), seed: good.seed, icon: good.icon)
            }
            for t in stride(from: Paper.crumpleEnd, through: bad.lifetime, by: 0.09) {
                let pose = bad.pose(at: t)
                PaperArt.draw(context, pose: pose, seed: bad.seed, icon: nil, tint: pose.phase == .bouncing ? .red : nil)
            }
        }
        .frame(width: size.width, height: size.height)
        writePNG(strobe, scale: 2, to: dir.appendingPathComponent("strobe.png"))

        // Three hand throws from the same spot: one goes in, one clips the rim, one falls short.
        let tosses = [867, 768, 600].enumerated().map { i, vx in
            TossedPaper(itemID: "", born: 0, start: CGPoint(x: 300, y: 250), velocity: CGVector(dx: vx, dy: -323),
                        seed: UInt64(10 + i), icon: icon, startCrumple: 0.6, basket: basket, canvas: size)
        }
        print("tosses:", tosses.map { "\($0.kind) impact=\(String(format: "%.2f", $0.impactTime))s life=\(String(format: "%.2f", $0.lifetime))s" })
        let tossView = Canvas { context, canvasSize in
            context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(Color(white: 0.97)))
            var held = HeldPaper(itemID: "", grabbedAt: 0, origin: CGPoint(x: 120, y: 260), location: CGPoint(x: 300, y: 250), seed: 5, icon: icon)
            held.location = CGPoint(x: 300, y: 250)
            StageRenderer.draw(context, size: canvasSize, now: 0.2, snapshot: StageSnapshot(held: held, pileCount: 3))
            for toss in tosses {
                for t in stride(from: 0.0, through: toss.lifetime, by: 0.05) {
                    PaperArt.draw(context, pose: toss.pose(at: t), seed: toss.seed, icon: toss.icon)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        writePNG(tossView, scale: 2, to: dir.appendingPathComponent("toss.png"))

        let steps: [CGFloat] = [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1]
        let crumple = Canvas { context, canvasSize in
            context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(Color(white: 0.97)))
            for (i, c) in steps.enumerated() {
                let pose = PaperPose(center: CGPoint(x: 50 + CGFloat(i) * 90, y: 60), rotation: 0, scale: 1,
                                     crumple: c, sheetScale: 1, opacity: 1, phase: .crumpling)
                PaperArt.draw(context, pose: pose, seed: 99, icon: icon)
            }
        }
        .frame(width: CGFloat(steps.count) * 90 + 10, height: 120)
        writePNG(crumple, scale: 3, to: dir.appendingPathComponent("crumple.png"))
    }

    /// Prints what a scan would find, without touching anything. Skips Downloads to avoid a privacy prompt.
    static func printScanReport() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for kind in CategoryKind.junk where kind != .installers && kind != .oldDownloads {
            let start = Date()
            let items = Scanner.scan(kind, runningBundleIDs: running)
            let total = items.reduce(Int64(0)) { $0 + $1.size }
            let picked = items.filter(\.isSelected).reduce(Int64(0)) { $0 + $1.size }
            print("== \(kind.title): \(items.count) 项, 共 \(total.byteString), 默认勾选 \(picked.byteString)  (\(String(format: "%.1f", Date().timeIntervalSince(start)))s)")
            for item in items.prefix(6) {
                print("   \(item.isSelected ? "[x]" : "[ ]") \(item.name)  \(item.size.byteString)  \(item.badge ?? "")")
            }
        }
    }

    private struct DMGBackground: View {
        // The icon's colours turned around: charcoal ground, off-white marks.
        private let charcoal = BinPalette.cream[0].ink
        private let cream = Color(hex: 0xF4EDE0)

        var body: some View {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x37342F), Color(hex: 0x1C1B19)], startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(cream)
                    .frame(width: 360, height: 360)
                    .blur(radius: 120)
                    .opacity(0.12)
                    .position(x: 300, y: 170)
                Canvas { context, _ in
                    // A dotted throw from the app to the Applications folder, with a paper ball mid-flight.
                    let start = CGPoint(x: 216, y: 184)
                    let end = CGPoint(x: 384, y: 184)
                    let control = CGPoint(x: 300, y: 104)
                    var arc = Path()
                    arc.move(to: start)
                    arc.addQuadCurve(to: end, control: control)
                    context.stroke(arc, with: .color(cream.opacity(0.45)),
                                   style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [0.5, 11]))
                    let angle = atan2(end.y - control.y, end.x - control.x)
                    var head = Path()
                    for side in [-1.0, 1.0] {
                        let a = angle + .pi + side * 0.5
                        head.move(to: end)
                        head.addLine(to: CGPoint(x: end.x + cos(a) * 13, y: end.y + sin(a) * 13))
                    }
                    context.stroke(head, with: .color(cream.opacity(0.6)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    // The same flat ball as the icon, drawn on its 1024 grid and scaled down.
                    var ball = context
                    ball.translateBy(x: 300, y: 140)
                    ball.scaleBy(x: 0.34, y: 0.34)
                    MinimalLogo.drawBall(ball, center: .zero, radius: 78, ink: cream, cut: charcoal, detailed: false)
                }
                VStack(spacing: 4) {
                    Text("Crumple").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("把垃圾揉成纸团").font(.system(size: 12)).opacity(0.6)
                }
                .foregroundStyle(cream)
                .position(x: 300, y: 50)
                Text("把 Crumple 拖到 Applications 文件夹即可安装")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(cream.opacity(0.75))
                    .position(x: 300, y: 338)
            }
            .frame(width: 600, height: 400)
            .environment(\.colorScheme, .dark)
        }
    }

    @MainActor
    private static func writePNG<V: View>(_ view: V, scale: CGFloat, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        // ImageRenderer hands back an HDR (PQ) image on recent SDKs; flatten it to 8-bit sRGB
        // so icons and previews look the same everywhere.
        guard let hdr = renderer.cgImage,
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: hdr.width, height: hdr.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            print("render failed: \(url.lastPathComponent)")
            return
        }
        context.draw(hdr, in: CGRect(x: 0, y: 0, width: hdr.width, height: hdr.height))
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            print("render failed: \(url.lastPathComponent)")
            return
        }
        try? data.write(to: url)
    }
}
