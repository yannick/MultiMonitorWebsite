import ScreenSaver
import WebKit

class MultiMonitorWebsiteView: ScreenSaverView {

    // MARK: - Web View
    private var webView: WKWebView?
    private var refreshTimer: Timer?
    private var hasLoadedInitialPage = false


    // MARK: - Instance Tracking
    // Use a file-based counter since each screen runs in a separate process
    private static let counterFile = URL(fileURLWithPath: "/tmp/MultiMonitorWebsite.counter")
    private let instanceIndex: Int

    private struct CounterData: Codable {
        var counter: Int
        var timestamp: TimeInterval
    }

    private static func claimNextIndex() -> Int {
        let lockPath = "/tmp/MultiMonitorWebsite.lock"
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o666)
        guard fd >= 0 else { return 0 }
        flock(fd, LOCK_EX)
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }

        let now = Date().timeIntervalSince1970
        var counter = 0

        // Read existing counter data
        if let data = try? Data(contentsOf: counterFile),
           let counterData = try? JSONDecoder().decode(CounterData.self, from: data) {
            // If counter is less than 10 seconds old, increment it
            // Otherwise, this is a new screensaver session, start fresh
            if now - counterData.timestamp < 10 {
                counter = counterData.counter
            }
        }

        // Save incremented counter with current timestamp
        let newData = CounterData(counter: counter + 1, timestamp: now)
        if let data = try? JSONEncoder().encode(newData) {
            try? data.write(to: counterFile)
        }

        return counter
    }

    // MARK: - Debug Logging
    private static func log(_ message: String) {
        let logFile = URL(fileURLWithPath: "/tmp/MultiMonitorWebsite.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    // MARK: - Configuration
    private static let defaultRefreshInterval: TimeInterval = 30.0

    private var configWindow: NSWindow?
    private var urlTableView: NSTableView?
    private var refreshIntervalTextField: NSTextField?
    private var siteList: [SiteConfig] = []

    // MARK: - Config File Storage
    // Use a shared config file since ScreenSaverDefaults doesn't work reliably
    // between System Settings and legacyScreenSaver processes

    private static var configFileURL: URL {
        // Use /tmp for config since screensaver sandbox can't access Application Support
        return URL(fileURLWithPath: "/tmp/MultiMonitorWebsite.config.json")
    }

    struct SiteConfig: Codable {
        var url: String
        var zoom: Double  // 1.0 = 100%, 1.5 = 150%, etc.

        init(url: String, zoom: Double = 1.0) {
            self.url = url
            self.zoom = zoom
        }
    }

    private struct Config: Codable {
        var sites: [SiteConfig]
        var refreshInterval: TimeInterval

        static let empty = Config(sites: [], refreshInterval: 30.0)

        // Migration from old format
        var urls: [String] {
            return sites.map { $0.url }
        }
    }

    private static func loadConfig() -> Config {
        guard let data = try? Data(contentsOf: configFileURL) else {
            return .empty
        }

        // Try new format first
        if let config = try? JSONDecoder().decode(Config.self, from: data) {
            return config
        }

        // Try migrating from old format (just urls array)
        struct OldConfig: Codable {
            var urls: [String]
            var refreshInterval: TimeInterval
        }
        if let oldConfig = try? JSONDecoder().decode(OldConfig.self, from: data) {
            let sites = oldConfig.urls.map { SiteConfig(url: $0, zoom: 1.0) }
            return Config(sites: sites, refreshInterval: oldConfig.refreshInterval)
        }

        return .empty
    }

    private static func saveConfig(_ config: Config) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: configFileURL)
    }

    private var siteConfigs: [SiteConfig] {
        return Self.loadConfig().sites.filter { !$0.url.isEmpty }
    }

    private var webURLs: [String] {
        return siteConfigs.map { $0.url }
    }

    private var refreshInterval: TimeInterval {
        let val = Self.loadConfig().refreshInterval
        return val > 0 ? val : Self.defaultRefreshInterval
    }

    /// Returns the site config for this screen based on screen position, or nil if none configured
    private var siteConfigForThisScreen: SiteConfig? {
        let sites = siteConfigs
        guard !sites.isEmpty else { return nil }
        let screenIndex = getScreenIndex()
        return sites[screenIndex % sites.count]
    }

    /// Returns the URL for this screen based on screen position, or nil if none configured
    private var webURLForThisScreen: String? {
        return siteConfigForThisScreen?.url
    }

    // MARK: - Initialization

    override init?(frame: NSRect, isPreview: Bool) {
        instanceIndex = Self.claimNextIndex()
        super.init(frame: frame, isPreview: isPreview)
        let screens = NSScreen.screens.map { $0.frame }
        Self.log("init instance \(instanceIndex), isPreview=\(isPreview), frame=\(frame), screens=\(screens)")
        commonInit()
    }

    required init?(coder: NSCoder) {
        instanceIndex = Self.claimNextIndex()
        super.init(coder: coder)
        Self.log("init(coder) instance \(instanceIndex)")
        commonInit()
    }

    private func commonInit() {
        // 30 FPS - sufficient for smooth second hand, halves CPU/GPU load
        animationTimeInterval = 1.0 / 30.0

        // Config is now stored in a JSON file, no defaults registration needed

        // Layer-backed for efficiency
        wantsLayer = true
        layer?.drawsAsynchronously = true

        // Sonoma exit fix: use distributed notifications to detect when screensaver
        // is dismissed, then force-exit the legacyScreenSaver process which otherwise
        // stays alive consuming CPU/RAM.
        setupTerminationObservers()
    }

    // MARK: - Web View Setup

    // Shared data store so all instances share cookies and logins persist between sessions
    private static let sharedDataStore: WKWebsiteDataStore = .default()

    /// Called from startAnimation() to ensure the view is in a window with correct bounds
    private func setupWebView() {
        guard webView == nil else { return }

        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        config.websiteDataStore = Self.sharedDataStore

        let wv = WKWebView(frame: bounds, configuration: config)
        wv.autoresizingMask = [.width, .height]
        addSubview(wv)
        webView = wv

        // Delay loading to allow window.screen to be assigned
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, !self.hasLoadedInitialPage else { return }
            self.hasLoadedInitialPage = true
            self.loadWebPage()
            self.startRefreshTimer()
        }
    }

    private func loadWebPage() {
        let screenIdx = getScreenIndex()

        guard let siteConfig = siteConfigForThisScreen,
              let url = URL(string: siteConfig.url) else {
            // No URL configured - show message
            webView?.loadHTMLString("""
                <html>
                <body style="background: black; color: white; font-family: -apple-system; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0;">
                    <div style="text-align: center;">
                        <p>No website configured</p>
                        <p style="font-size: 14px; opacity: 0.6;">Screen \(screenIdx + 1)</p>
                        <p style="font-size: 12px; opacity: 0.4;">Open Screen Saver Options to add websites</p>
                    </div>
                </body>
                </html>
                """, baseURL: nil)
            return
        }

        // Apply zoom level
        webView?.pageZoom = siteConfig.zoom
        webView?.load(URLRequest(url: url))
    }

    private func getScreenIndex() -> Int {
        let screens = NSScreen.screens
        if let windowScreen = window?.screen {
            return screens.firstIndex(of: windowScreen) ?? 0
        }
        return 0
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.loadWebPage()
        }
    }

    // MARK: - Sonoma Exit Fix
    // macOS Sonoma has a bug where legacyScreenSaver doesn't exit properly,
    // causing high CPU/RAM usage. We rely on distributed notifications to detect
    // when the screensaver is dismissed and force-exit the process.
    // Other approaches (watchdog timers, orphan detection in animateOneFrame,
    // exit from stopAnimation) are too aggressive on multi-monitor setups and
    // cause premature exit.

    private func setupTerminationObservers() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenSaverWillStop),
            name: NSNotification.Name("com.apple.screensaver.willstop"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenSaverDidStop),
            name: NSNotification.Name("com.apple.screensaver.didstop"),
            object: nil
        )
    }

    @objc private func screenSaverWillStop(_ notification: Notification) {
        if #available(macOS 14.0, *), !isPreview {
            teardown()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                exit(0)
            }
        }
    }

    @objc private func screenSaverDidStop(_ notification: Notification) {
        if #available(macOS 14.0, *), !isPreview {
            teardown()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                exit(0)
            }
        }
    }

    /// Clean up resources
    private func teardown() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil

        hasLoadedInitialPage = false
    }

    deinit {
        refreshTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - ScreenSaverView Lifecycle

    override func startAnimation() {
        super.startAnimation()
        let screenInfo = window?.screen.map { "screen=\($0.frame)" } ?? "no screen"
        let windowInfo = window.map { "window=\($0.frame)" } ?? "no window"
        Self.log("startAnimation instance \(instanceIndex), \(windowInfo), \(screenInfo)")

        // Set up web view on first start.
        // Done here rather than init so the view is in a window with correct bounds.
        // Each screen gets its own web view.
        setupWebView()
    }

    override func stopAnimation() {
        super.stopAnimation()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
    }

    override func animateOneFrame() {
        // Web view handles its own rendering
    }

    // MARK: - Configuration Sheet

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        // Always create a fresh window to avoid stale state issues
        configWindow = nil
        urlTableView = nil
        refreshIntervalTextField = nil

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Multi Monitor Website"

        guard let contentView = window.contentView else { return nil }

        // URLs label
        let urlLabel = NSTextField(labelWithString: "Websites (one per screen, in order):")
        urlLabel.frame = NSRect(x: 20, y: 310, width: 250, height: 22)
        contentView.addSubview(urlLabel)

        let zoomLabel = NSTextField(labelWithString: "Zoom")
        zoomLabel.frame = NSRect(x: 410, y: 310, width: 50, height: 22)
        contentView.addSubview(zoomLabel)

        // URL table with scroll view
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 100, width: 460, height: 200))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let tableView = NSTableView(frame: scrollView.bounds)
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.allowsMultipleSelection = false

        let urlColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url"))
        urlColumn.width = 370
        urlColumn.isEditable = true
        tableView.addTableColumn(urlColumn)

        let zoomColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("zoom"))
        zoomColumn.width = 70
        zoomColumn.isEditable = true
        tableView.addTableColumn(zoomColumn)

        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        contentView.addSubview(scrollView)
        urlTableView = tableView

        // Load current sites into the list (fresh from settings)
        siteList = siteConfigs
        tableView.reloadData()

        // Add/Remove buttons
        let addButton = NSButton(title: "+", target: self, action: #selector(addURL))
        addButton.frame = NSRect(x: 20, y: 65, width: 30, height: 24)
        addButton.bezelStyle = .rounded
        contentView.addSubview(addButton)

        let removeButton = NSButton(title: "−", target: self, action: #selector(removeURL))
        removeButton.frame = NSRect(x: 55, y: 65, width: 30, height: 24)
        removeButton.bezelStyle = .rounded
        contentView.addSubview(removeButton)

        // Refresh interval field
        let refreshLabel = NSTextField(labelWithString: "Refresh interval (seconds):")
        refreshLabel.frame = NSRect(x: 200, y: 65, width: 180, height: 22)
        contentView.addSubview(refreshLabel)

        let refreshField = NSTextField(frame: NSRect(x: 385, y: 65, width: 60, height: 22))
        refreshField.stringValue = "\(Int(refreshInterval))"
        refreshField.isEditable = true
        refreshField.isBezeled = true
        refreshField.drawsBackground = true
        contentView.addSubview(refreshField)
        refreshIntervalTextField = refreshField

        // Buttons
        let okButton = NSButton(title: "OK", target: self, action: #selector(configOK))
        okButton.frame = NSRect(x: 400, y: 15, width: 80, height: 32)
        okButton.keyEquivalent = "\r"
        okButton.bezelStyle = .rounded
        contentView.addSubview(okButton)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(configCancel))
        cancelButton.frame = NSRect(x: 310, y: 15, width: 80, height: 32)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded
        contentView.addSubview(cancelButton)

        configWindow = window
        return window
    }

    @objc private func addURL() {
        siteList.append(SiteConfig(url: "https://", zoom: 1.0))
        urlTableView?.reloadData()
        // Select and edit the new row
        let newRow = siteList.count - 1
        urlTableView?.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        urlTableView?.editColumn(0, row: newRow, with: nil, select: true)
    }

    @objc private func removeURL() {
        guard let tableView = urlTableView else { return }
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 && selectedRow < siteList.count else { return }
        siteList.remove(at: selectedRow)
        tableView.reloadData()
    }

    @objc private func configOK() {
        // Filter out empty URLs
        let validSites = siteList.filter { !$0.url.isEmpty && $0.url != "https://" }

        var interval = Self.defaultRefreshInterval
        if let str = refreshIntervalTextField?.stringValue,
           let val = Double(str), val > 0 {
            interval = val
        }

        // Save to config file
        let config = Config(sites: validSites, refreshInterval: interval)
        Self.saveConfig(config)

        closeConfigSheet()
    }

    @objc private func configCancel() {
        closeConfigSheet()
    }

    private func closeConfigSheet() {
        guard let window = configWindow else { return }
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            window.close()
        }
        // Clear references to ensure fresh state next time
        configWindow = nil
        urlTableView = nil
        refreshIntervalTextField = nil
    }
}

// MARK: - NSTableViewDataSource & NSTableViewDelegate

extension MultiMonitorWebsiteView: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return siteList.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row < siteList.count else { return nil }
        let site = siteList[row]

        if tableColumn?.identifier.rawValue == "url" {
            return site.url
        } else if tableColumn?.identifier.rawValue == "zoom" {
            return String(format: "%.0f%%", site.zoom * 100)
        }
        return nil
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard let value = object as? String, row < siteList.count else { return }

        if tableColumn?.identifier.rawValue == "url" {
            siteList[row].url = value
        } else if tableColumn?.identifier.rawValue == "zoom" {
            // Parse zoom value (accept "150", "150%", "1.5")
            var zoomStr = value.trimmingCharacters(in: .whitespaces)
            zoomStr = zoomStr.replacingOccurrences(of: "%", with: "")
            if let zoomVal = Double(zoomStr) {
                // If value > 10, assume it's a percentage (e.g., 150 = 150%)
                siteList[row].zoom = zoomVal > 10 ? zoomVal / 100.0 : zoomVal
            }
        }
    }
}
