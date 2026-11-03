import SwiftUI
import AppKit

@MainActor @Observable
final class CleanCategory: Identifiable {
    let kind: CategoryKind
    var items: [CleanItem] = []
    var isScanning = false

    nonisolated var id: CategoryKind { kind }

    init(kind: CategoryKind) {
        self.kind = kind
    }

    var liveItems: [CleanItem] { items.filter { $0.status != .cleaned } }
    var selectedItems: [CleanItem] { items.filter { $0.isSelected && $0.status != .cleaned } }
    var totalBytes: Int64 { liveItems.reduce(0) { $0 + $1.size } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    var selectionState: CheckState {
        let live = liveItems
        let selected = live.filter(\.isSelected).count
        if selected == 0 { return .off }
        return selected == live.count ? .on : .mixed
    }

    func toggleAll() {
        let newValue = selectionState != .on
        for i in items.indices where items[i].status != .cleaned {
            items[i].isSelected = newValue
        }
    }

    func selectAll() {
        for i in items.indices where items[i].status != .cleaned { items[i].isSelected = true }
    }

    func toggle(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].isSelected.toggle()
    }

    func setStatus(_ id: String, _ status: CleanItem.Status) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].status = status
        if status == .failed { items[i].isSelected = false }
    }

    /// Lets items that failed last time be retried if the user ticked them again.
    func prepareForCleaning() {
        for i in items.indices where items[i].isSelected && items[i].status == .failed {
            items[i].status = .ready
        }
    }
}

@MainActor
final class IconCache {
    private var cache: [String: NSImage] = [:]

    func icon(for item: CleanItem) -> NSImage {
        if let icon = cache[item.id] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: (item.appURL ?? item.url).path)
        cache[item.id] = icon
        return icon
    }
}

/// A question to confirm before doing something that can't be undone easily.
struct Confirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let actionTitle: String
    let action: @MainActor () -> Void
    /// Runs when the user backs out (Cancel or Esc).
    var cancel: (@MainActor () -> Void)? = nil
}

@MainActor @Observable
final class AppModel {
    // MARK: Navigation
    var page: Page = .overview
    private(set) var smartPhase: SmartPhase = .landing
    private(set) var filesPhase: ListPhase = .landing
    private(set) var appsPhase: ListPhase = .landing
    private(set) var dupPhase: ListPhase = .landing

    // MARK: Data
    let junk: [CleanCategory]
    let largeFiles = CleanCategory(kind: .largeFiles)
    let apps = CleanCategory(kind: .applications)
    let duplicates = CleanCategory(kind: .duplicates)
    var reviewKind: CategoryKind = .appCaches
    private(set) var revealed: Set<CategoryKind> = []
    private(set) var lastSmartScan: Date?
    private(set) var resultsShownAt = Date()
    private(set) var filesChecked = 0
    private(set) var appsProgress = (done: 0, total: 0)
    private(set) var dupProgress = ""
    var fileFilter: FileTag?
    var fileSort: FileSort = .size
    var appFilter: AppFilter = .all
    var focusedAppID: String?
    /// The row under the pointer (or last clicked), which the space bar previews.
    @ObservationIgnored var pointedURL: URL?
    /// The file shown in Quick Look, if any.
    var previewURL: URL?
    /// The last file thrown by hand, so ⌘Z can put it back in its row.
    @ObservationIgnored private var lastThrow: (entry: UUID, item: String, kind: CategoryKind)?
    /// One batch sent to the shredder with ⌥⌘⌫, whatever the usual cleaning mode is.
    @ObservationIgnored private var batchMode: CleanMode?
    @ObservationIgnored private var keyMonitor: Any?

    // MARK: Cleaning
    private(set) var cleaningCategoryID: CategoryKind?
    private(set) var isCleaning = false
    private(set) var cleanDone = 0
    private(set) var cleanTotal = 0
    private(set) var sessionFreed: Int64 = 0
    private(set) var lastSummary: CleanSummary?
    private(set) var doneAt = Date()
    var banner: CleanSummary?
    var confirmation: Confirmation?
    var trashError: String?
    /// Short message shown above the basket when a paper bounces off.
    private(set) var basketNote: String?
    /// Short message at the top of the window (undo results, ignored items…).
    private(set) var toast: String?
    @ObservationIgnored private var toastToken = 0

    // MARK: Permissions
    var showsOnboarding = false
    private(set) var hasFullDiskAccess = Permissions.hasFullDiskAccess
    /// What's in the Trash right now; nil when it can't be read.
    private(set) var trashSize: Int64?
    var hidesPermissionBanner: Bool {
        didSet { UserDefaults.standard.set(hidesPermissionBanner, forKey: "hidesPermissionBanner") }
    }

    // MARK: History & settings
    private(set) var history: [HistoryEntry]
    private(set) var disk: DiskInfo? = DiskInfo.current()
    var mode: CleanMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "cleanMode") }
    }
    var largeFileThresholdMB: Int {
        didSet { UserDefaults.standard.set(largeFileThresholdMB, forKey: "largeFileThresholdMB") }
    }
    var oldDownloadDays: Int {
        didSet { UserDefaults.standard.set(oldDownloadDays, forKey: "oldDownloadDays") }
    }
    /// Files and folders the user never wants to see in results again.
    private(set) var ignoredPaths: [String] {
        didSet { UserDefaults.standard.set(ignoredPaths, forKey: Self.ignoredKey) }
    }
    // Demo paths live in the sandbox; keep them apart from the real list.
    private static var ignoredKey: String { Paths.isDemo ? "demoIgnoredPaths" : "ignoredPaths" }
    // MARK: Menu bar and reminders
    var showsMenuBarExtra: Bool {
        didSet { UserDefaults.standard.set(showsMenuBarExtra, forKey: "showsMenuBarExtra") }
    }
    var remindsLowDisk: Bool {
        didSet {
            UserDefaults.standard.set(remindsLowDisk, forKey: "remindsLowDisk")
            if remindsLowDisk { askForNotifications() }
        }
    }
    var remindsWeekly: Bool {
        didSet {
            UserDefaults.standard.set(remindsWeekly, forKey: "remindsWeekly")
            if remindsWeekly { askForNotifications() }
        }
    }
    private(set) var notificationsDenied = false
    /// Opens (or brings back) the main window. Set by the first view that has SwiftUI's openWindow action.
    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored let reminders = Reminders()

    enum UpdateState: Equatable {
        case checking
        case done(UpdateCheck.Outcome)
    }
    /// nil until the user (or the daily check) has looked for an update.
    private(set) var update: UpdateState?
    /// The app's one model, for the AppKit delegate.
    static weak var shared: AppModel?

    /// Paper sounds and trackpad taps; `SoundBoard` reads the same setting.
    var playsSounds: Bool {
        didSet { UserDefaults.standard.set(playsSounds, forKey: "playsSounds") }
    }
    var playsLaunchAnimation: Bool {
        didSet { UserDefaults.standard.set(playsLaunchAnimation, forKey: "playsLaunchAnimation") }
    }

    var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            Palette.light = appearance.lightPalette
            NSApp?.appearance = appearance.nsAppearance
        }
    }
    var language: AppLanguage {
        didSet {
            let defaults = UserDefaults.standard
            defaults.set(language.rawValue, forKey: "appLanguage")
            if language == .system {
                defaults.removeObject(forKey: "AppleLanguages")
            } else {
                defaults.set([language.rawValue], forKey: "AppleLanguages")
            }
        }
    }
    private let launchLanguage: AppLanguage
    var languageNeedsRestart: Bool { language != launchLanguage }
    var relaunchError: String?

    func relaunch() {
        guard !isCleaning, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        if let demoHome = Paths.demoHome {
            configuration.environment = ["CRUMPLE_DEMO_HOME": demoHome.path]
        }
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.relaunchError = String(localized: "没能重新打开 Crumple：\(error.localizedDescription)")
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    // MARK: Launch animation
    /// When the launch animation started; nil once it is gone.
    private(set) var splashStart: Date?
    @ObservationIgnored private var splashShown = false

    // MARK: Status, analysis, optimise
    let monitor = SystemMonitor()
    let analyzer = SpaceAnalyzer()
    private(set) var launchAgents: [LaunchAgent] = []
    private(set) var taskStates: [String: TaskState] = [:]

    enum TaskState { case idle, running, done, failed }

    let stage = PaperStage()
    let icons = IconCache()
    /// Where each row's icon sits on screen, so its paper can start from there.
    @ObservationIgnored var iconFrames: [String: CGRect] = [:]
    @ObservationIgnored var listViewport: CGRect = .zero
    @ObservationIgnored private var scanToken = 0
    /// The page scans that are running, so they can be called off; and where each one goes back to.
    @ObservationIgnored private var listScans: [Page: (task: Task<Void, Never>, previous: ListPhase)] = [:]
    @ObservationIgnored private var flagsMonitor: Any?
    @ObservationIgnored private var shredAllowed = true
    @ObservationIgnored private var noteToken = 0

    init() {
        junk = CategoryKind.junk.map { CleanCategory(kind: $0) }
        let defaults = UserDefaults.standard
        let savedAppearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .mist
        appearance = savedAppearance
        Palette.light = savedAppearance.lightPalette
        let savedLanguage = AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "") ?? .system
        language = savedLanguage
        launchLanguage = savedLanguage
        mode = CleanMode(rawValue: defaults.string(forKey: "cleanMode") ?? "") ?? .trash
        largeFileThresholdMB = defaults.object(forKey: "largeFileThresholdMB") as? Int ?? 100
        oldDownloadDays = defaults.object(forKey: "oldDownloadDays") as? Int ?? 90
        playsLaunchAnimation = defaults.object(forKey: "playsLaunchAnimation") as? Bool ?? true
        playsSounds = defaults.object(forKey: "playsSounds") as? Bool ?? true
        hidesPermissionBanner = defaults.bool(forKey: "hidesPermissionBanner")
        ignoredPaths = defaults.stringArray(forKey: Self.ignoredKey) ?? []
        showsMenuBarExtra = defaults.object(forKey: "showsMenuBarExtra") as? Bool ?? true
        remindsLowDisk = defaults.bool(forKey: "remindsLowDisk")
        remindsWeekly = defaults.bool(forKey: "remindsWeekly")
        if let demo = Paths.demoHome {
            DemoData.populate(at: demo)
        }
        history = HistoryStore.load()
        NSApp?.appearance = appearance.nsAppearance
        Self.shared = self
        reminders.onOpen = { [weak self] in
            guard let self else { return }
            self.openMainWindow?()
            NSApp.activate()
            self.startSmartScan()
        }
        reminders.start { [weak self] in self?.checkReminders() }
        checkForUpdatesIfDue()
    }

    // MARK: - Updates

    func checkForUpdates() {
        guard update != .checking else { return }
        update = .checking
        Task {
            let outcome = await UpdateCheck.check()
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
            withAnimation(.snappy) { update = .done(outcome) }
        }
    }

    /// Once a day at most, and only when an update address is configured.
    private func checkForUpdatesIfDue() {
        guard UpdateCheck.repository != nil, !Paths.isDemo else { return }
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        if Date().timeIntervalSince(last) > 86_400 { checkForUpdates() }
    }

    // MARK: - Reminders

    private func askForNotifications() {
        Task {
            let allowed = await reminders.requestPermission()
            notificationsDenied = !allowed
        }
    }

    func refreshNotificationStatus() {
        Task { notificationsDenied = await reminders.isDenied() }
    }

    /// Runs every half hour while Crumple is open.
    private func checkReminders() {
        refreshDisk()
        if remindsLowDisk, let disk, disk.total > 0,
           disk.available < 15_000_000_000 || Double(disk.available) / Double(disk.total) < 0.1 {
            reminders.post("lowDisk", title: String(localized: "磁盘快满了"),
                           body: String(localized: "只剩 \(disk.available.byteString) 可用。点这里，看看有哪些垃圾可以扔掉。"),
                           every: 24 * 3600)
        }
        let week: TimeInterval = 7 * 86_400
        if remindsWeekly, Date().timeIntervalSince(history.first?.date ?? .distantPast) > week {
            reminders.post("weekly", title: String(localized: "一周没清理了"),
                           body: String(localized: "缓存和日志又攒了一些。点这里，用 Crumple 扫一扫。"),
                           every: week)
        }
    }

    // MARK: - Status, analysis, optimise

    func requestForceQuit(_ app: NSRunningApplication, name: String) {
        confirmation = Confirmation(title: String(localized: "强制退出 \(name)？"),
                                    message: String(localized: "没保存的内容会丢失。只在它卡住、没反应时这样做。"),
                                    actionTitle: String(localized: "强制退出")) {
            app.forceTerminate()
        }
    }

    func requestTrash(_ entry: SpaceAnalyzer.Entry) {
        let size = entry.size.map { String(localized: "（\($0.byteString)）") } ?? ""
        confirmation = Confirmation(title: String(localized: "把“\(entry.name)”移到废纸篓？"),
                                    message: String(localized: "\(Paths.display(entry.url))\(size) 会被移到废纸篓，需要时可以从废纸篓放回。"),
                                    actionTitle: String(localized: "移到废纸篓")) { [weak self] in
            guard let self else { return }
            let url = entry.url
            Task {
                let ok = await Task.detached { Cleaner.clean(url, mode: .trash) }.value
                if ok {
                    withAnimation(.snappy) { self.analyzer.remove(entry) }
                    self.refreshDisk()
                } else {
                    self.trashError = String(localized: "没能移动“\(entry.name)”，它可能正在使用或受系统保护。")
                }
            }
        }
    }

    func loadLaunchAgents() {
        launchAgents = LaunchAgent.list()
    }

    func setLaunchAgent(_ agent: LaunchAgent, enabled: Bool) {
        Task {
            _ = await Task.detached { agent.setEnabled(enabled) }.value
            withAnimation(.snappy) { loadLaunchAgents() }
        }
    }

    func runMaintenance(_ task: MaintenanceTask) {
        guard taskStates[task.id] != .running else { return }
        taskStates[task.id] = .running
        Task {
            let ok = await Task.detached { task.run() }.value
            withAnimation(.snappy) { taskStates[task.id] = ok ? .done : .failed }
        }
    }

    // MARK: - Launch animation

    func startSplashIfNeeded() {
        refreshDisk()
        guard playsLaunchAnimation, !splashShown else {
            presentOnboardingIfNeeded()
            return
        }
        splashShown = true
        let start = Date()
        splashStart = start
        Task {
            try? await Task.sleep(for: .seconds(Splash.duration))
            if splashStart == start { dismissSplash() }
        }
    }

    func dismissSplash() {
        guard splashStart != nil else { return }
        withAnimation(.easeOut(duration: 0.45)) { splashStart = nil }
        presentOnboardingIfNeeded()
    }

    // MARK: - Permissions

    private func presentOnboardingIfNeeded() {
        guard !Paths.isDemo, !UserDefaults.standard.bool(forKey: "onboardingDone") else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            showsOnboarding = true
        }
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingDone")
        showsOnboarding = false
    }

    /// Called when the app comes back to the front, e.g. after visiting System Settings.
    func refreshPermissions() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess
        refreshDisk()
    }

    // MARK: - Derived state

    /// The basket sits in the corner of every page, except where the page's own picture already shows one.
    var showsBasket: Bool {
        switch page {
        case .smartClean: smartPhase != .landing
        case .largeFiles: filesPhase != .landing
        case .duplicates: dupPhase != .landing
        case .uninstaller: appsPhase != .landing
        case .history: !history.isEmpty
        case .overview, .status, .analysis, .optimize: true
        }
    }

    /// How many balls show in the basket for what is in the Trash: a few for a little, more as it grows.
    nonisolated static func pileCount(forTrash bytes: Int64) -> Int {
        guard bytes > 0 else { return 0 }
        let megabytes = Double(bytes) / 1_000_000
        return min(30, 1 + Int((log2(megabytes + 1) * 1.6).rounded()))
    }

    var junkFound: Int64 { junk.reduce(0) { $0 + $1.totalBytes } }
    var junkSelectedBytes: Int64 { junk.reduce(0) { $0 + $1.selectedBytes } }
    var junkSelectedCount: Int { junk.reduce(0) { $0 + $1.selectedItems.count } }
    var revealedBytes: Int64 { junk.filter { revealed.contains($0.kind) }.reduce(0) { $0 + $1.totalBytes } }
    var scanProgress: Double { Double(revealed.count) / Double(CategoryKind.junk.count) }
    // Cleans that were undone don't count.
    var historyTotal: Int64 { history.filter { !$0.isRestored }.reduce(0) { $0 + $1.bytes } }
    var historyPapers: Int { history.filter { !$0.isRestored }.reduce(0) { $0 + $1.count } }

    func category(_ kind: CategoryKind) -> CleanCategory {
        switch kind {
        case .largeFiles: largeFiles
        case .duplicates: duplicates
        case .applications: apps
        default: junk.first { $0.kind == kind } ?? junk[0]
        }
    }

    /// The rows a list shows, after the page's filter and sort.
    func visibleItems(in category: CleanCategory) -> [CleanItem] {
        // While a category is being cleaned only the queue is shown, so the next paper is always near the top.
        if cleaningCategoryID == category.kind {
            return category.items.filter { $0.isSelected && $0.status == .ready }
        }
        var items = category.liveItems
        switch category.kind {
        case .largeFiles:
            if let fileFilter { items = items.filter { $0.tag == fileFilter } }
            if fileSort == .oldest { items.sort { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) } }
        case .applications:
            items = Self.filter(items, by: appFilter)
        default: break
        }
        return items
    }

    nonisolated static func filter(_ items: [CleanItem], by filter: AppFilter) -> [CleanItem] {
        switch filter {
        case .all: items
        case .unused: items.filter { $0.badge == String(localized: "很久没用") || $0.lastUsed == nil }
        case .large: items.filter { $0.size >= 500_000_000 }
        case .appStore: items.filter(\.isAppStore)
        }
    }

    func cleaningMode(for kind: CategoryKind) -> CleanMode {
        kind == .applications ? .trash : batchMode ?? mode
    }

    // MARK: - Smart clean

    func startSmartScan() {
        guard !isCleaning else { return }
        scanToken += 1
        let token = scanToken
        lastSummary = nil
        withAnimation(.smooth(duration: 0.45)) {
            page = .smartClean
            smartPhase = .scanning
            revealed = []
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let days = oldDownloadDays
        let ignored = ignoredPaths
        for category in junk {
            category.isScanning = true
            category.items = []
            let kind = category.kind
            Task.detached(priority: .userInitiated) {
                let items = Scanner.scan(kind, runningBundleIDs: running, oldDownloadDays: days)
                    .filter { !IgnoreList.contains($0.url, in: ignored) }
                await MainActor.run {
                    category.items = items
                    category.isScanning = false
                }
            }
        }
        // Reveal the categories one by one, so the scan reads as a sequence even when it is quick.
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            for category in junk {
                while category.isScanning {
                    try? await Task.sleep(for: .milliseconds(80))
                }
                guard token == scanToken else { return }
                _ = withAnimation(.snappy) { revealed.insert(category.kind) }
                try? await Task.sleep(for: .milliseconds(320))
            }
            try? await Task.sleep(for: .milliseconds(450))
            guard token == scanToken else { return }
            lastSmartScan = Date()
            resultsShownAt = Date()
            withAnimation(.smooth(duration: 0.5)) { smartPhase = .results }
            refreshDisk()
        }
    }

    func cancelSmartScan() {
        scanToken += 1
        withAnimation(.smooth) { smartPhase = lastSmartScan == nil ? .landing : .results }
    }

    func showSmartResults() {
        guard lastSmartScan != nil else { return startSmartScan() }
        resultsShownAt = Date()
        withAnimation(.smooth(duration: 0.45)) {
            page = .smartClean
            smartPhase = .results
        }
    }

    func openReview(_ kind: CategoryKind? = nil) {
        if let kind { reviewKind = kind }
        withAnimation(.smooth(duration: 0.4)) { smartPhase = .review }
    }

    func backToResults() {
        resultsShownAt = Date()
        withAnimation(.smooth(duration: 0.4)) { smartPhase = .results }
    }

    func finishSmartClean() {
        withAnimation(.smooth(duration: 0.45)) { smartPhase = .landing }
    }

    func requestSmartClean(shred: Bool = false) {
        let work = junk.filter { !$0.selectedItems.isEmpty }
        guard !isCleaning, !work.isEmpty else { return }
        confirmIfDeleting(bytes: junkSelectedBytes, shred: shred) { [weak self] in
            self?.startCleaning(work, source: .smartClean)
        }
    }

    // MARK: - Large files

    func scanLargeFiles() {
        guard !isCleaning, filesPhase != .scanning else { return }
        banner = nil
        filesChecked = 0
        let previous = filesPhase
        withAnimation(.smooth(duration: 0.45)) { filesPhase = .scanning }
        largeFiles.isScanning = true
        let minBytes = Paths.isDemo ? 1_000_000 : Int64(largeFileThresholdMB) * 1_000_000
        let task = Task {
            let started = Date()
            let work = Task.detached(priority: .userInitiated) {
                Scanner.scanLargeFiles(minBytes: minBytes) { checked in
                    Task { @MainActor in self.filesChecked = checked }
                }
            }
            let items = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            let remaining = 1.4 - Date().timeIntervalSince(started)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard !Task.isCancelled else { return }
            listScans[.largeFiles] = nil
            fileFilter = nil
            largeFiles.items = items.filter { !isIgnored($0.url) }
            largeFiles.isScanning = false
            withAnimation(.smooth(duration: 0.5)) { filesPhase = .results }
        }
        listScans[.largeFiles] = (task, previous)
    }

    /// Calls off a scan that is still running and goes back to what was on the page before it.
    func cancelScan(on page: Page) {
        guard let scan = listScans.removeValue(forKey: page) else { return }
        scan.task.cancel()
        let back: ListPhase = scan.previous == .results ? .results : .landing
        withAnimation(.smooth(duration: 0.4)) {
            switch page {
            case .largeFiles: largeFiles.isScanning = false; filesPhase = back
            case .duplicates: duplicates.isScanning = false; dupPhase = back
            case .uninstaller: apps.isScanning = false; appsPhase = back
            default: break
            }
        }
    }

    /// Whether the page is showing a scan that can be called off.
    func isScanning(_ page: Page) -> Bool {
        switch page {
        case .smartClean: smartPhase == .scanning
        case .largeFiles: filesPhase == .scanning
        case .duplicates: dupPhase == .scanning
        case .uninstaller: appsPhase == .scanning
        default: false
        }
    }

    func cancelCurrentScan() {
        guard isScanning(page) else { return NSSound.beep() }
        if page == .smartClean { cancelSmartScan() } else { cancelScan(on: page) }
    }

    func requestLargeFileClean(shred: Bool = false) {
        guard !isCleaning, !largeFiles.selectedItems.isEmpty else { return }
        confirmIfDeleting(bytes: largeFiles.selectedBytes, shred: shred) { [weak self] in
            guard let self else { return }
            self.startCleaning([self.largeFiles], source: .largeFiles)
        }
    }

    // MARK: - Duplicates

    func scanDuplicates() {
        guard !isCleaning, dupPhase != .scanning else { return }
        banner = nil
        dupProgress = String(localized: "正在列出文件…")
        let previous = dupPhase
        withAnimation(.smooth(duration: 0.45)) { dupPhase = .scanning }
        duplicates.isScanning = true
        let minBytes: Int64 = Paths.isDemo ? 50_000 : 256_000
        let ignored = ignoredPaths
        let task = Task {
            let started = Date()
            let work = Task.detached(priority: .userInitiated) {
                DuplicateFinder.scan(minBytes: minBytes, ignored: ignored) { text in
                    Task { @MainActor in self.dupProgress = text }
                }
            }
            let items = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            let remaining = 1.4 - Date().timeIntervalSince(started)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard !Task.isCancelled else { return }
            listScans[.duplicates] = nil
            duplicates.items = items
            duplicates.isScanning = false
            withAnimation(.smooth(duration: 0.5)) { dupPhase = .results }
        }
        listScans[.duplicates] = (task, previous)
    }

    /// How many sets of identical files are listed.
    var duplicateGroups: Int { Set(duplicates.liveItems.compactMap { $0.keeper?.path }).count }

    func requestDuplicateClean(shred: Bool = false) {
        guard !isCleaning, !duplicates.selectedItems.isEmpty else { return }
        confirmIfDeleting(bytes: duplicates.selectedBytes, shred: shred) { [weak self] in
            guard let self else { return }
            self.startCleaning([self.duplicates], source: .duplicates)
        }
    }

    /// Keep this copy instead: it leaves the list, and the copy that was kept takes its place.
    func keepInstead(_ item: CleanItem) {
        guard let oldKeeper = item.keeper, !isCleaning,
              let index = duplicates.items.firstIndex(where: { $0.id == item.id }) else { return }
        let swapped = DuplicateFinder.makeItem(oldKeeper, size: item.size, modified: nil, keeper: item.url)
        withAnimation(.snappy) {
            duplicates.items[index] = swapped
            for i in duplicates.items.indices where duplicates.items[i].keeper == oldKeeper {
                let other = duplicates.items[i]
                var updated = DuplicateFinder.makeItem(other.url, size: other.size, modified: other.lastUsed, keeper: item.url)
                updated.isSelected = other.isSelected
                duplicates.items[i] = updated
            }
        }
        showToast(String(localized: "改为保留 \(Paths.display(item.url))"))
    }

    // MARK: - Uninstaller

    func scanApps() {
        guard !isCleaning, appsPhase != .scanning else { return }
        banner = nil
        appsProgress = (0, 0)
        let previous = appsPhase
        withAnimation(.smooth(duration: 0.45)) { appsPhase = .scanning }
        apps.isScanning = true
        let task = Task {
            let started = Date()
            let items = await Task.detached(priority: .userInitiated) {
                Scanner.scanApplications { done, total in
                    Task { @MainActor in self.appsProgress = (done, total) }
                }
            }.value
            let remaining = 1.4 - Date().timeIntervalSince(started)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard !Task.isCancelled else { return }
            listScans[.uninstaller] = nil
            apps.items = items.filter { !isIgnored($0.url) }
            apps.isScanning = false
            focusedAppID = apps.items.first?.id
            withAnimation(.smooth(duration: 0.5)) { appsPhase = .results }
        }
        listScans[.uninstaller] = (task, previous)
    }

    func requestUninstall(only id: String? = nil) {
        guard !isCleaning else { return }
        if let id {
            for i in apps.items.indices { apps.items[i].isSelected = apps.items[i].id == id }
        }
        let selected = apps.selectedItems
        guard !selected.isEmpty else { return }
        let leftovers = selected.reduce(0) { $0 + $1.components.count - 1 }
        let names = selected.prefix(3).map(\.name).joined(separator: String(localized: "、")) + (selected.count > 3 ? String(localized: " 等") : "")
        confirmation = Confirmation(
            title: String(localized: "卸载 \(selected.count) 个应用？"),
            message: String(localized: "\(names) 以及 \(leftovers) 个残留文件（共 \(apps.selectedBytes.byteString)）会被移到废纸篓。"),
            actionTitle: String(localized: "卸载")
        ) { [weak self] in
            guard let self else { return }
            self.startCleaning([self.apps], source: .uninstaller)
        }
    }

    // MARK: - Cleaning

    /// `shred` sends this one batch to the shredder even when cleaning normally goes to the Trash.
    private func confirmIfDeleting(bytes: Int64, shred: Bool = false, then action: @escaping @MainActor () -> Void) {
        let run: @MainActor () -> Void = { [weak self] in
            self?.batchMode = shred ? .delete : nil
            action()
        }
        if (mode == .delete || shred) && !Paths.isDemo {
            confirmation = Confirmation(
                title: String(localized: "把选中的文件送进碎纸机？"),
                message: String(localized: "将永久删除 \(bytes.byteString)，不经过废纸篓，无法撤销。"),
                actionTitle: String(localized: "粉碎"),
                action: run
            )
        } else {
            run()
        }
    }

    private func startCleaning(_ work: [CleanCategory], source: CleanSource) {
        isCleaning = true
        banner = nil
        cleanDone = 0
        cleanTotal = work.reduce(0) { $0 + $1.selectedItems.count }
        if source == .smartClean {
            withAnimation(.smooth(duration: 0.45)) { smartPhase = .cleaning }
        }
        Task { await runCleaning(work, source: source) }
    }

    private func runCleaning(_ work: [CleanCategory], source: CleanSource) async {
        var report = CleanSummary(source: source, mode: cleaningMode(for: work[0].kind))

        for category in work {
            let mode = cleaningMode(for: category.kind)
            category.prepareForCleaning()
            withAnimation(.snappy) {
                cleaningCategoryID = category.kind
                if source == .smartClean { reviewKind = category.kind }
            }
            // Give the list a moment to lay out so we know where every icon is.
            try? await Task.sleep(for: .milliseconds(450))

            let queue = category.items.filter { $0.isSelected && $0.status == .ready }
            let gap = max(0.035, min(0.28, 5.5 / Double(max(queue.count, 1))))
            var line = CleanSummary.Line(kind: category.kind, count: 0, bytes: 0)
            defer { if line.count > 0 { report.lines.append(line) } }
            for item in queue {
                let block = blockReason(for: item)
                var ok = false
                if block == nil {
                    let outcome = await Task.detached(priority: .userInitiated) { Cleaner.clean(item, mode: mode) }.value
                    ok = outcome.removed
                    report.trashed += outcome.trashed
                }
                let size = item.size
                let reason = block ?? String(localized: "删除失败（受系统保护或正在使用）")
                stage.launch(from: launchOrigin(for: item.id), icon: icons.icon(for: item), succeeded: ok,
                             shred: mode == .delete) { [weak self] in
                    guard let self else { return }
                    if ok {
                        withAnimation(.snappy) { self.sessionFreed += size }
                    } else {
                        self.showNote(block ?? String(localized: "\(item.name) 删不掉，投不进去"))
                    }
                }
                withAnimation(.easeInOut(duration: 0.22)) {
                    category.setStatus(item.id, ok ? .cleaned : .failed)
                    cleanDone += 1
                }
                if ok {
                    report.count += 1
                    report.bytes += size
                    line.count += 1
                    line.bytes += size
                } else {
                    report.failures.append(.init(name: item.name, reason: reason))
                }
                try? await Task.sleep(for: .seconds(gap))
            }
        }

        // Let the last paper balls land before wrapping up.
        for _ in 0..<40 where !stage.papers.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        report.finishedAt = Date()
        withAnimation(.snappy) {
            for category in work {
                category.items.removeAll { $0.status == .cleaned }
            }
            cleaningCategoryID = nil
            isCleaning = false
        }
        batchMode = nil
        report.historyID = record(report)
        refreshDisk()
        if source == .smartClean {
            lastSummary = report
            doneAt = Date()
            withAnimation(.smooth(duration: 0.5)) { smartPhase = .done }
        } else {
            withAnimation(.snappy) { banner = report }
        }
    }

    private func launchOrigin(for id: String) -> CGPoint {
        let viewport = listViewport.insetBy(dx: -4, dy: -4)
        if let frame = iconFrames[id], viewport.contains(CGPoint(x: frame.midX, y: frame.midY)) {
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        return CGPoint(x: listViewport.minX + 70, y: listViewport.minY + 30)
    }

    /// Why an item can't go in the basket right now (its app is running, or we may not delete it).
    func blockReason(for item: CleanItem) -> String? {
        if let owner = item.ownerBundleID {
            let running = NSWorkspace.shared.runningApplications.contains { app in
                guard let id = app.bundleIdentifier else { return false }
                return owner == id || owner.hasPrefix(id + ".")
            }
            if running { return String(localized: "\(item.name) 正在运行，投不进去") }
        }
        // Never throw away the last copy of a duplicate.
        if let keeper = item.keeper, !FileManager.default.fileExists(atPath: keeper.path) {
            return String(localized: "另一份已经不在了，\(item.name) 要留着")
        }
        // Apps get a second chance through Finder, which can ask for an administrator password.
        if item.url.pathExtension != "app", !FileManager.default.isDeletableFile(atPath: item.url.path) {
            return String(localized: "\(item.name) 没有删除权限，投不进去")
        }
        return nil
    }

    private func showNote(_ text: String) {
        noteToken += 1
        let token = noteToken
        withAnimation(.snappy) { basketNote = text }
        AccessibilityNotification.Announcement(text).post()
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard noteToken == token else { return }
            withAnimation(.easeOut(duration: 0.3)) { basketNote = nil }
        }
    }

    // MARK: - Throwing by hand

    /// Throws one item without dragging it: from the row's menu, or with VoiceOver.
    func throwAway(_ item: CleanItem, in category: CleanCategory) {
        let status = category.items.first { $0.id == item.id }?.status
        guard !isCleaning, status == .ready || status == .failed else { return }
        let mode = cleaningMode(for: category.kind)
        let block = blockReason(for: item)
        let size = item.size
        Task {
            var outcome = Cleaner.Outcome()
            if block == nil {
                outcome = await Task.detached(priority: .userInitiated) { Cleaner.clean(item, mode: mode) }.value
            }
            let ok = outcome.removed
            stage.launch(from: launchOrigin(for: item.id), icon: icons.icon(for: item), succeeded: ok,
                         shred: mode == .delete) {
                if ok {
                    withAnimation(.snappy) { self.sessionFreed += size }
                } else {
                    self.showNote(block ?? String(localized: "\(item.name) 删不掉，投不进去"))
                }
            }
            withAnimation(.easeInOut(duration: 0.22)) {
                category.setStatus(item.id, ok ? .cleaned : (block == nil ? .failed : .ready))
            }
            if ok {
                rememberThrow(record(CleanSummary(source: .manual, mode: mode, count: 1, bytes: size, trashed: outcome.trashed)),
                              item: item.id, kind: category.kind)
                if focusedAppID == item.id { focusedAppID = apps.liveItems.first?.id }
                AccessibilityNotification.Announcement(String(localized: "已扔掉 \(item.name)，\(size.byteString)")).post()
            }
        }
    }

    func beginToss(_ item: CleanItem, in category: CleanCategory, at location: CGPoint) {
        let status = category.items.first { $0.id == item.id }?.status
        guard !isCleaning, stage.held == nil, status == .ready || status == .failed else { return }
        let origin = iconFrames[item.id].map { CGPoint(x: $0.midX, y: $0.midY) } ?? location
        stage.grab(itemID: item.id, icon: icons.icon(for: item), origin: origin, location: location,
                   blocked: blockReason(for: item) != nil)
        withAnimation(.easeOut(duration: 0.15)) {
            category.setStatus(item.id, .tossed)
        }
        // Holding ⌥ brings out the shredder, even without moving the mouse. Apps always go to the Trash.
        shredAllowed = category.kind != .applications
        stage.setArmed(shredAllowed && NSEvent.modifierFlags.contains(.option))
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            self.stage.setArmed(self.shredAllowed && event.modifierFlags.contains(.option))
            return event
        }
    }

    func moveToss(to location: CGPoint) {
        stage.moveHeld(to: location)
    }

    private func stopWatchingFlags() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
    }

    /// Lets go of the paper. Only a ball that lands in the basket gets its file cleaned;
    /// a miss or a rim shot puts the file back in the list. Files that can't be deleted
    /// (app still running, no permission, delete fails) are spat back out.
    func endToss(_ item: CleanItem, in category: CleanCategory, velocity: CGSize) {
        stopWatchingFlags()
        guard let toss = stage.release(velocity: velocity) else { return }
        let mode = cleaningMode(for: category.kind)
        let size = item.size
        let id = item.id
        let block = blockReason(for: item)
        let note = block ?? String(localized: "\(item.name) 删不掉，投不进去")
        if toss.kind == .shred {
            shred(item, in: category, toss: toss, block: block)
            return
        }
        Task {
            if toss.kind == .make {
                var outcome = Cleaner.Outcome()
                if block == nil {
                    outcome = await Task.detached(priority: .userInitiated) { Cleaner.clean(item, mode: mode) }.value
                }
                let ok = outcome.removed
                stage.settle(toss.id, succeeded: ok)
                let wait = toss.born + toss.impactTime - Date.timeIntervalSinceReferenceDate
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                if !ok { showNote(note) }
                withAnimation(.snappy) {
                    if ok { sessionFreed += size }
                    // A refused item simply comes back; one whose delete actually failed is flagged.
                    category.setStatus(id, ok ? .cleaned : (block == nil ? .failed : .ready))
                }
                if ok {
                    rememberThrow(record(CleanSummary(source: .manual, mode: mode, count: 1, bytes: size, trashed: outcome.trashed)),
                                  item: id, kind: category.kind)
                    if focusedAppID == id { focusedAppID = apps.liveItems.first?.id }
                }
            } else {
                try? await Task.sleep(for: .seconds(toss.lifetime))
                withAnimation(.easeOut(duration: 0.25)) {
                    category.setStatus(id, .ready)
                }
            }
        }
    }

    /// A sheet caught by the shredder waits in the slot until the user confirms. Shredding skips the Trash,
    /// so it can't be undone; cancelling puts the file back in the list.
    private func shred(_ item: CleanItem, in category: CleanCategory, toss: TossedPaper, block: String?) {
        let id = item.id
        func putBack() {
            stage.resolveShred(toss.id, shredded: false)
            Task {
                try? await Task.sleep(for: .seconds(0.9))
                withAnimation(.easeOut(duration: 0.25)) { category.setStatus(id, .ready) }
            }
        }
        if let block {
            putBack()
            showNote(block)
            return
        }
        confirmation = Confirmation(
            title: String(localized: "送进碎纸机？"),
            message: String(localized: "“\(item.name)”（\(item.size.byteString)）会被永久删除，不经过废纸篓，无法撤销。"),
            actionTitle: String(localized: "粉碎"),
            action: { [weak self] in
                guard let self else { return }
                Task {
                    let outcome = await Task.detached(priority: .userInitiated) { Cleaner.clean(item, mode: .delete) }.value
                    guard outcome.removed else {
                        putBack()
                        self.showNote(String(localized: "\(item.name) 删不掉，投不进去"))
                        return
                    }
                    self.stage.resolveShred(toss.id, shredded: true)
                    withAnimation(.snappy) {
                        self.sessionFreed += item.size
                        category.setStatus(id, .cleaned)
                    }
                    self.record(CleanSummary(source: .manual, mode: .delete, count: 1, bytes: item.size))
                    self.refreshDisk()
                }
            },
            cancel: { putBack() }
        )
    }

    // MARK: - History, disk, trash

    @discardableResult
    private func record(_ summary: CleanSummary) -> UUID? {
        guard summary.count > 0 || summary.failed > 0 else { return nil }
        let entry = HistoryEntry(date: summary.finishedAt, source: summary.source, mode: summary.mode,
                                 count: summary.count, bytes: summary.bytes, failed: summary.failed,
                                 trashed: summary.trashed.isEmpty ? nil : summary.trashed)
        history.insert(entry, at: 0)
        HistoryStore.save(history)
        return entry.id
    }

    // MARK: - Undo

    /// A clean can be undone while its files are still in the Trash.
    func canRestore(_ entry: HistoryEntry) -> Bool {
        guard !entry.isRestored, let files = entry.trashed, !files.isEmpty else { return false }
        return files.contains { Cleaner.exists(URL(fileURLWithPath: $0.trashed)) }
    }

    func canRestore(_ summary: CleanSummary) -> Bool {
        guard let id = summary.historyID, let entry = history.first(where: { $0.id == id }) else { return false }
        return canRestore(entry)
    }

    /// Puts every file of a clean back where it was.
    func restore(_ entryID: UUID?) {
        guard let entryID, let index = history.firstIndex(where: { $0.id == entryID }),
              let files = history[index].trashed else { return }
        Task {
            let putBack = await Task.detached(priority: .userInitiated) { files.filter { Cleaner.restore($0) } }.value
            let back = putBack.count
            let missing = files.count - back
            // The balls jump back out of the basket and smooth out on their way to the page.
            let icons = putBack.prefix(8).map { NSWorkspace.shared.icon(forFile: $0.original) as NSImage? }
            let target = listViewport == .zero
                ? CGPoint(x: stage.canvasSize.width * 0.55, y: stage.canvasSize.height * 0.42)
                : CGPoint(x: listViewport.midX, y: listViewport.midY)
            if showsBasket { stage.unthrow(icons: Array(icons), to: target) }
            guard back > 0 else {
                showToast(String(localized: "没能放回：文件已经不在废纸篓里，或原处已有同名文件"))
                return
            }
            withAnimation(.snappy) {
                history[index].restored = true
                if lastSummary?.historyID == entryID { lastSummary?.trashed = [] }
                if banner?.historyID == entryID { banner = nil }
            }
            HistoryStore.save(history)
            refreshDisk()
            // A file thrown by hand goes straight back into its row.
            if let thrown = lastThrow, thrown.entry == entryID {
                lastThrow = nil
                withAnimation(.snappy) { category(thrown.kind).setStatus(thrown.item, .ready) }
            }
            // The files are back, so a list that was showing them is out of date.
            switch history[index].source {
            case .largeFiles where filesPhase == .results: scanLargeFiles()
            case .duplicates where dupPhase == .results: scanDuplicates()
            case .uninstaller where appsPhase == .results: scanApps()
            default: break
            }
            if missing > 0 {
                showToast(String(localized: "放回了 \(back) 个，\(missing) 个已不在废纸篓里"))
            } else {
                showToast(String(localized: "已全部放回原处（\(back) 个）"))
            }
        }
    }

    private func rememberThrow(_ entry: UUID?, item: String, kind: CategoryKind) {
        lastThrow = entry.map { ($0, item, kind) }
    }

    /// The latest clean, if its files are still in the Trash. ⌘Z puts them back.
    var undoableEntry: HistoryEntry? {
        guard !isCleaning, let latest = history.first, canRestore(latest) else { return nil }
        return latest
    }

    func undoLastClean() {
        guard let entry = undoableEntry else {
            if isCleaning {
                NSSound.beep()
            } else if history.first.map({ !$0.isRestored && $0.mode == .delete }) == true {
                showToast(String(localized: "粉碎的文件没有经过废纸篓，无法撤销"))
            } else {
                showToast(String(localized: "没有可以撤销的清理"))
            }
            return
        }
        restore(entry.id)
    }

    // MARK: - Keyboard

    /// The list the current page is showing, for ⌘A and ⌘⌫.
    private var currentList: [CleanCategory] {
        switch page {
        case .smartClean where smartPhase == .review: [category(reviewKind)]
        case .smartClean where smartPhase == .results: junk
        case .largeFiles where filesPhase == .results: [largeFiles]
        case .duplicates where dupPhase == .results: [duplicates]
        case .uninstaller where appsPhase == .results: [apps]
        default: []
        }
    }

    var canSelectAll: Bool { !isCleaning && currentList.contains { !$0.liveItems.isEmpty } }
    var canThrowSelection: Bool { !isCleaning && currentList.contains { !$0.selectedItems.isEmpty } }

    func selectAllInList() {
        guard canSelectAll else { return NSSound.beep() }
        withAnimation(.snappy) { currentList.forEach { $0.selectAll() } }
    }

    /// ⌘⌫ throws the ticked files the usual way; ⌥⌘⌫ sends them to the shredder.
    func throwSelection(shred: Bool) {
        guard canThrowSelection, !(shred && page == .uninstaller) else { return NSSound.beep() }
        switch page {
        case .smartClean: requestSmartClean(shred: shred)
        case .largeFiles: requestLargeFileClean(shred: shred)
        case .duplicates: requestDuplicateClean(shred: shred)
        case .uninstaller: requestUninstall()
        default: break
        }
    }

    var canRescan: Bool {
        guard !isCleaning else { return false }
        switch page {
        case .smartClean, .largeFiles, .duplicates, .uninstaller, .analysis, .overview: return !isScanning(page)
        default: return false
        }
    }

    func rescan() {
        guard canRescan else { return NSSound.beep() }
        switch page {
        case .smartClean: startSmartScan()
        case .largeFiles: scanLargeFiles()
        case .duplicates: scanDuplicates()
        case .uninstaller: scanApps()
        case .analysis: analyzer.rescan()
        case .overview: refreshDisk()
        default: break
        }
    }

    func go(to page: Page) {
        guard self.page != page else { return }
        pointedURL = nil
        withAnimation(.smooth(duration: 0.3)) { self.page = page }
    }

    /// Space previews the row under the pointer with Quick Look, the way Finder does.
    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 49,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function]).isEmpty,
                  let window = event.window, !(window is NSPanel), window.attachedSheet == nil,
                  !(window.firstResponder is NSText), self.confirmation == nil else { return event }
            if self.previewURL != nil {
                self.previewURL = nil
                return nil
            }
            guard let url = self.pointedURL, self.stage.held == nil,
                  FileManager.default.fileExists(atPath: url.path) else { return event }
            self.previewURL = url
            return nil
        }
    }

    // MARK: - Ignore list

    func isIgnored(_ url: URL) -> Bool {
        IgnoreList.contains(url, in: ignoredPaths)
    }

    /// Hides an item from now on. It disappears from the list it was in.
    func ignore(_ item: CleanItem, in category: CleanCategory) {
        let path = Paths.normalized(item.url)
        guard !ignoredPaths.contains(path) else { return }
        ignoredPaths.append(path)
        withAnimation(.snappy) { category.items.removeAll { $0.id == item.id } }
        showToast(String(localized: "以后不再列出 \(item.name)，可以在设置里恢复"))
    }

    func addIgnored(_ url: URL) {
        let path = Paths.normalized(url)
        guard !ignoredPaths.contains(path) else { return }
        ignoredPaths.append(path)
    }

    func unignore(_ path: String) {
        ignoredPaths.removeAll { $0 == path }
    }

    func showToast(_ text: String) {
        toastToken += 1
        let token = toastToken
        withAnimation(.snappy) { toast = text }
        AccessibilityNotification.Announcement(text).post()
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard toastToken == token else { return }
            withAnimation(.easeOut(duration: 0.3)) { toast = nil }
        }
    }

    func clearHistory() {
        confirmation = Confirmation(title: String(localized: "清空清理记录？"), message: String(localized: "只会删除记录，不影响任何文件。"), actionTitle: String(localized: "清空")) { [weak self] in
            self?.clearHistoryNow()
        }
    }

    func clearHistoryNow() {
        withAnimation(.snappy) { history = [] }
        HistoryStore.save([])
    }

    func refreshDisk() {
        disk = DiskInfo.current()
        Task {
            let size = await Task.detached(priority: .utility) { Permissions.trashSize() }.value
            let previous = trashSize
            trashSize = size
            // Without access to the Trash the basket just keeps what was thrown this session.
            if let size {
                stage.syncPile(to: Self.pileCount(forTrash: size), trashShrank: size < (previous ?? .max))
            }
        }
    }

    func requestEmptyTrash() {
        confirmation = Confirmation(title: String(localized: "清倒废纸篓？"), message: String(localized: "废纸篓里的所有项目都会被永久删除，无法恢复。"), actionTitle: String(localized: "清倒")) { [weak self] in
            self?.emptyTrash()
        }
    }

    private func emptyTrash() {
        Task {
            let ok = await Task.detached { Cleaner.emptyTrash() }.value
            if ok {
                stage.clearPile()
                lastSummary?.trashEmptied = true
                banner?.trashEmptied = true
                refreshDisk()
            } else {
                trashError = String(localized: "请在“系统设置 › 隐私与安全性 › 自动化”中允许 Crumple 控制“访达”，然后再试一次。")
            }
        }
    }
}
