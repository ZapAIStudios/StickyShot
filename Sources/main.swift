// StickyShot — keeps the screenshot preview on screen until you dismiss it.
// A tiny menu bar app for macOS 13+. No network access, no data collection.

import AppKit
import QuickLookThumbnailing
import ServiceManagement

// MARK: - Settings

enum Settings {
    private static let d = UserDefaults.standard

    static var enabled: Bool {
        get { d.object(forKey: "enabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "enabled") }
    }

    /// Seconds before a preview closes by itself. 0 means never.
    static var autoClose: Int {
        get { d.integer(forKey: "autoClose") }
        set { d.set(newValue, forKey: "autoClose") }
    }

    /// The user's own show-thumbnail value from before StickyShot changed it.
    /// "unset" means the key did not exist.
    static var savedSystemThumbnail: String? {
        get { d.string(forKey: "savedSystemThumbnail") }
        set { d.set(newValue, forKey: "savedSystemThumbnail") }
    }
}

// MARK: - macOS screenshot settings

enum SystemScreenshots {
    private static let domain = "com.apple.screencapture" as CFString

    /// Where macOS saves screenshots (Desktop unless changed in ⌘⇧5 → Options).
    static var folder: URL {
        CFPreferencesAppSynchronize(domain)
        if let path = CFPreferencesCopyAppValue("location" as CFString, domain) as? String, !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    /// Hides the built-in floating thumbnail so there are never two previews.
    static func hideBuiltInThumbnail() {
        if Settings.savedSystemThumbnail == nil {
            let current = CFPreferencesCopyAppValue("show-thumbnail" as CFString, domain) as? Bool
            Settings.savedSystemThumbnail = current.map { $0 ? "true" : "false" } ?? "unset"
        }
        write(false)
    }

    /// Puts the built-in thumbnail back the way the user had it.
    static func restoreBuiltInThumbnail() {
        guard let saved = Settings.savedSystemThumbnail else { return }
        write(saved == "unset" ? nil : (saved == "true"))
        Settings.savedSystemThumbnail = nil
    }

    private static func write(_ value: Bool?) {
        CFPreferencesSetAppValue("show-thumbnail" as CFString, value.map { $0 ? kCFBooleanTrue : kCFBooleanFalse }, domain)
        CFPreferencesAppSynchronize(domain)
        // The screenshot UI rereads its settings when it next launches.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["screencaptureui"]
        task.standardError = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        try? task.run()
    }
}

// MARK: - Folder watcher

/// Watches the screenshot folder and reports each new screenshot or screen recording once.
final class ScreenshotWatcher {
    var onNewCapture: ((URL) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var watchedFolder: URL?
    private var known = Set<String>()
    private let startedAt = Date()

    func start() {
        let folder = SystemScreenshots.folder
        if folder == watchedFolder, source != nil { return }
        stop()
        watchedFolder = folder
        known = Set(listing(of: folder))

        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func listing(of folder: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    private func scan() {
        guard let folder = watchedFolder else { return }
        let now = Set(listing(of: folder))
        let added = now.subtracting(known)
        known = now
        for name in added where !name.hasPrefix(".") {
            let url = folder.appendingPathComponent(name)
            if isCapture(url) { waitUntilWritten(url) }
        }
    }

    /// macOS tags screenshots with kMDItemIsScreenCapture; recordings are matched by name.
    private func isCapture(_ url: URL) -> Bool {
        if getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0 { return true }
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
        guard created >= startedAt.addingTimeInterval(-5) else { return false }
        return (name.hasPrefix("screenshot") || name.hasPrefix("screen shot") || name.hasPrefix("screen recording"))
            && ["png", "jpg", "jpeg", "heic", "tiff", "pdf", "gif", "mov", "mp4"].contains(ext)
    }

    /// Recordings keep growing for a moment after they appear; report once the size settles.
    private func waitUntilWritten(_ url: URL, lastSize: Int = -1, tries: Int = 0) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > 0 && size == lastSize || tries > 40 {
            onNewCapture?(url)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.waitUntilWritten(url, lastSize: size, tries: tries + 1)
        }
    }
}

// MARK: - Preview card

final class PreviewView: NSView, NSDraggingSource {
    let fileURL: URL
    var onClose: (() -> Void)?
    var onUserTouched: (() -> Void)?

    private let imageView = NSImageView()
    private let closeButton = NSButton()
    private var mouseDownPoint: NSPoint?
    private var tracking: NSTrackingArea?

    init(fileURL: URL, size: NSSize) {
        self.fileURL = fileURL
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.unregisterDraggedTypes()
        addSubview(imageView)

        closeButton.frame = NSRect(x: 6, y: bounds.height - 28, width: 22, height: 22)
        closeButton.autoresizingMask = [.maxXMargin, .minYMargin]
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close preview")
        closeButton.contentTintColor = .white
        closeButton.wantsLayer = true
        closeButton.layer?.shadowOpacity = 0.6
        closeButton.layer?.shadowRadius = 2
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.isHidden = true
        closeButton.toolTip = "Close"
        addSubview(closeButton)

        toolTip = "Click to open · Drag to share · Right-click for more"
        setAccessibilityLabel("Screenshot preview: \(fileURL.lastPathComponent)")
        loadThumbnail(size: size)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func loadThumbnail(size: NSSize) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: fileURL, size: CGSize(width: size.width, height: size.height),
                                                   scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            DispatchQueue.main.async {
                if let rep { self?.imageView.image = rep.nsImage }
                else { self?.imageView.image = NSWorkspace.shared.icon(forFile: self?.fileURL.path ?? "") }
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false; onUserTouched?() }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }

    override func mouseDown(with event: NSEvent) { mouseDownPoint = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        item.setDraggingFrame(bounds, contents: imageView.image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if mouseDownPoint != nil { openFile() }
        mouseDownPoint = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open", action: #selector(openFile), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Copy", action: #selector(copyFile), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show in Finder", action: #selector(revealFile), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Move to Trash", action: #selector(trashFile), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Close", action: #selector(closeClicked), keyEquivalent: "").target = self
        return menu
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] { onClose?() }
    }

    @objc private func openFile() { NSWorkspace.shared.open(fileURL); onClose?() }
    @objc private func revealFile() { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
    @objc private func closeClicked() { onClose?() }

    @objc private func copyFile() {
        let pb = NSPasteboard.general
        pb.clearContents()
        var items: [NSPasteboardWriting] = [fileURL as NSURL]
        if let image = NSImage(contentsOf: fileURL) { items.insert(image, at: 0) }
        pb.writeObjects(items)
    }

    @objc private func trashFile() {
        NSWorkspace.shared.recycle([fileURL]) { [weak self] _, _ in self?.onClose?() }
    }
}

// MARK: - Preview stack

/// Shows previews in the lower-right corner, newest at the bottom, older ones stacked above.
final class PreviewStack {
    private var panels: [NSPanel] = []
    private var timers: [ObjectIdentifier: Timer] = [:]
    private let margin: CGFloat = 20
    private let gap: CGFloat = 12
    private let maxVisible = 5

    /// The display the user is working on: whichever one has the mouse pointer.
    private var screen: NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    }

    var count: Int { panels.count }

    func show(_ url: URL) {
        guard let screen else { return }
        let size = cardSize(for: url)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false

        let view = PreviewView(fileURL: url, size: size)
        view.onClose = { [weak self, weak panel] in if let panel { self?.dismiss(panel) } }
        view.onUserTouched = { [weak self, weak panel] in if let panel { self?.cancelTimer(panel) } }
        panel.contentView = view

        // Slide in from the right edge, like the built-in preview.
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX + 10, y: visible.minY + margin))
        panels.insert(panel, at: 0)
        panel.orderFrontRegardless()

        while panels.count > maxVisible, let oldest = panels.last { dismiss(oldest) }
        layout(animated: true)
        startTimer(panel)
    }

    func dismissAll() { panels.forEach { dismiss($0, relayout: false) } }

    private func cardSize(for url: URL) -> NSSize {
        let width: CGFloat = 220
        if let rep = NSImageRep(contentsOf: url), rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            let ratio = CGFloat(rep.pixelsHigh) / CGFloat(rep.pixelsWide)
            return NSSize(width: width, height: min(max(width * ratio, 80), 260))
        }
        return NSSize(width: width, height: 140)
    }

    private func layout(animated: Bool) {
        guard let screen else { return }
        let visible = screen.visibleFrame
        var y = visible.minY + margin
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.25 : 0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for panel in panels {
                let size = panel.frame.size
                let origin = NSPoint(x: visible.maxX - size.width - margin, y: y)
                panel.animator().setFrame(NSRect(origin: origin, size: size), display: true)
                y += size.height + gap
            }
        }
    }

    private func dismiss(_ panel: NSPanel, relayout: Bool = true) {
        cancelTimer(panel)
        guard let index = panels.firstIndex(of: panel) else { return }
        panels.remove(at: index)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
        if relayout { layout(animated: true) }
    }

    private func startTimer(_ panel: NSPanel) {
        let seconds = Settings.autoClose
        guard seconds > 0 else { return }
        timers[ObjectIdentifier(panel)] = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self, weak panel] _ in
            if let panel { self?.dismiss(panel) }
        }
    }

    private func cancelTimer(_ panel: NSPanel) {
        timers.removeValue(forKey: ObjectIdentifier(panel))?.invalidate()
    }
}

// MARK: - Menu bar

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let watcher = ScreenshotWatcher()
    private let stack = PreviewStack()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "StickyShot")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        watcher.onNewCapture = { [weak self] url in self?.stack.show(url) }
        apply()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SystemScreenshots.restoreBuiltInThumbnail()
    }

    private func apply() {
        if Settings.enabled {
            SystemScreenshots.hideBuiltInThumbnail()
            watcher.start()
        } else {
            watcher.stop()
            stack.dismissAll()
            SystemScreenshots.restoreBuiltInThumbnail()
        }
        statusItem.button?.appearsDisabled = !Settings.enabled
    }

    // Rebuilt every time it opens, so it always reflects the current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if Settings.enabled { watcher.start() }  // picks up a changed save folder

        let toggle = menu.addItem(withTitle: "Keep Previews On Screen", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = Settings.enabled ? .on : .off

        let closeMenu = NSMenu()
        for (title, seconds) in [("Never — until I close it", 0), ("After 10 seconds", 10), ("After 30 seconds", 30), ("After 1 minute", 60), ("After 5 minutes", 300)] {
            let item = closeMenu.addItem(withTitle: title, action: #selector(setAutoClose(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            item.state = Settings.autoClose == seconds ? .on : .off
        }
        menu.addItem(withTitle: "Close Previews Automatically", action: nil, keyEquivalent: "").submenu = closeMenu

        let closeAll = menu.addItem(withTitle: "Close All Previews", action: #selector(closeAll), keyEquivalent: "")
        closeAll.target = self
        closeAll.isEnabled = stack.count > 0

        menu.addItem(.separator())
        let folder = SystemScreenshots.folder
        menu.addItem(withTitle: "Watching: \(folder.lastPathComponent)", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: "Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: "").target = self

        let login = menu.addItem(withTitle: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit StickyShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func toggleEnabled() { Settings.enabled.toggle(); apply() }
    @objc private func setAutoClose(_ sender: NSMenuItem) { Settings.autoClose = sender.tag }
    @objc private func closeAll() { stack.dismissAll() }
    @objc private func openFolder() { NSWorkspace.shared.open(SystemScreenshots.folder) }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Start at Login"
            alert.informativeText = "Add StickyShot yourself in System Settings → General → Login Items.\n\n\(error.localizedDescription)"
            alert.runModal()
        }
    }
}

// Quitting from the Dock or a logout also restores the built-in thumbnail.
signal(SIGTERM) { _ in
    SystemScreenshots.restoreBuiltInThumbnail()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
