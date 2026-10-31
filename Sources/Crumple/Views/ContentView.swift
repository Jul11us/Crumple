import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: Theme.sidebarWidth)
                .background(Theme.sidebar)
            Rectangle().fill(Theme.stroke).frame(width: 1)
            ZStack {
                PageBackground()
                pageView
                    .id(model.page)
                    .transition(.opacity)
            }
            .clipped()
            // Clipping only affects drawing. Keep hit testing inside the page as well.
            .contentShape(Rectangle())
        }
        .background(Theme.base)
        .ignoresSafeArea()
        .coordinateSpace(.named(StageSpace.name))
        .overlay {
            PaperStageView(stage: model.stage)
                .ignoresSafeArea()
                .accessibilityHidden(true)
                .opacity(model.showsBasket ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: model.showsBasket)
        }
        .overlay(alignment: .bottomTrailing) {
            if let note = model.basketNote {
                BasketNote(text: note)
                    .padding(.trailing, 14)
                    .padding(.bottom, BasketGeometry.bottomInset + BasketGeometry.size.height + 10)
                    .transition(.scale(scale: 0.85, anchor: .bottomTrailing).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Toast(text: toast)
                    .padding(.top, 14)
                    .padding(.leading, Theme.sidebarWidth)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if let start = model.splashStart {
                SplashView(start: start) { model.dismissSplash() }
                    .ignoresSafeArea()
                    .accessibilityElement()
                    .accessibilityLabel("Crumple 开场动画")
                    .accessibilityHint("点一下跳过")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { model.dismissSplash() }
                    .transition(.opacity)
            }
        }
        .onAppear {
            model.openMainWindow = { openWindow(id: "main") }
            model.startSplashIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
        }
        .sheet(isPresented: Binding(get: { model.showsOnboarding }, set: { model.showsOnboarding = $0 })) {
            OnboardingView()
        }
        .frame(minWidth: 1100, minHeight: 720)
        .preferredColorScheme(model.appearance.colorScheme)
        .alert(
            model.confirmation?.title ?? "",
            isPresented: Binding(get: { model.confirmation != nil }, set: { if !$0 { model.confirmation = nil } }),
            presenting: model.confirmation
        ) { confirmation in
            Button(confirmation.actionTitle, role: .destructive) { confirmation.action() }
            Button("取消", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message)
        }
        .alert("没能清倒废纸篓", isPresented: Binding(
            get: { model.trashError != nil },
            set: { if !$0 { model.trashError = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(model.trashError ?? "")
        }
    }

    @ViewBuilder private var pageView: some View {
        switch model.page {
        case .overview: OverviewPage()
        case .smartClean: SmartCleanPage()
        case .largeFiles: LargeFilesPage()
        case .duplicates: DuplicatesPage()
        case .uninstaller: UninstallerPage()
        case .history: HistoryPage()
        case .status: StatusPage()
        case .analysis: AnalysisPage()
        case .optimize: OptimizePage()
        }
    }
}
