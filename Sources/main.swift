import AppKit
import AVFoundation
import AVKit
import os

final class MirrorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PreviewView: NSView {
    let preview = AVCaptureVideoPreviewLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        CATransaction.commit()
    }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var panel: MirrorPanel!
    private let capture = CaptureController()
    private lazy var settingsController = SettingsWindowController()
    private let preview = PreviewView()
    private let player = DraggablePlayerView()
    private let recordButton = ControlButton()
    private let recordControls = NSStackView()
    private var hoveringVideo = false
    private var selectedRecording: URL?
    private var recordingButtons: [URL: RecordingButton] = [:]
    private let status = NSTextField(labelWithString: "Starting camera…")
    private let filmstrip = NSStackView()
    private let recordingScroll = NSScrollView()
    private var recordingStripHeight: NSLayoutConstraint!
    private var recordingStripTopGap: NSLayoutConstraint!
    private var recordingStripVisible = UserDefaults.standard.object(forKey: "RecordingStripVisible") as? Bool ?? true
    private var recordings: [URL] = []
    private var showPastRecordings = false
    private var timer: Timer?
    private var started: Date?
    private var busy = false { didSet { updateRecordControlVisibility() } }
    private var recording = false { didSet { updateRecordControlVisibility() } }
    private var recordWhenReady = false { didSet { updateRecordControlVisibility() } }
    private var playing = false
    private var quitting = false
    private var closing = false
    private var suspended = false
    private var observers: [NSObjectProtocol] = []
    private var libraryTask: Task<Void, Never>?
    private var loadedThumbnails: Set<URL> = []
    private var recordingVersions: [URL: String] = [:]
    private var libraryGeneration = 0
    private let folder = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Simple Video Recorder", isDirectory: true)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOf: iconURL)
        }
        createMenus()
        buildWindow()
        capture.onError = { [weak self] message in
            self?.cancelPendingRecording()
            self?.resetRecordingControls()
            self?.status.stringValue = message; self?.status.toolTip = message
            self?.recordButton.isEnabled = false
        }
        capture.onPermissionRequest = { [weak self] in
            self?.panel.level = .normal
            self?.status.stringValue = "Allow microphone access in the macOS prompt…"
            NSApp.activate(ignoringOtherApps: true)
        }
        capture.onReady = { [weak self] in
            guard let self, !self.playing, !self.busy else { return }
            if let connection = self.preview.preview.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            self.panel.level = .floating
            self.status.stringValue = ""
            self.status.toolTip = nil
            self.recordButton.isEnabled = true
            if self.recordWhenReady {
                self.cancelPendingRecording()
                if self.panel.isVisible && !self.suspended { self.toggleRecording() }
            }
        }
        capture.onStarted = { [weak self] in
            guard let self else { return }
            self.panel.level = .floating
            self.recording = true
            self.showPastRecordings = false
            self.updateRecordingStripVisibility()
            self.started = Date()
            self.recordButton.title = ""
            self.recordButton.toolTip = "Stop recording"
            self.recordButton.setAccessibilityLabel("Stop recording")
            self.recordButton.symbol = "stop.fill"
            self.recordButton.isEnabled = true
            self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updateTime() }
            self.timer?.tolerance = 0.2
            self.updateTime()
            if self.quitting || self.closing || self.suspended { self.capture.finish() }
        }
        capture.onFinished = { [weak self] url, error in
            guard let self else { return }
            self.panel.level = .floating
            self.resetRecordingControls()
            self.recordButton.isEnabled = error == nil && !self.suspended && !self.closing
            self.status.stringValue = error ?? ""
            self.status.toolTip = error
            if url != nil { self.showPastRecordings = true; self.loadLibrary() }
            if self.quitting { NSApp.reply(toApplicationShouldTerminate: true) }
            else if self.closing { self.capture.stop(); self.panel.orderOut(nil); self.closing = false }
            else if !self.suspended && self.panel.isVisible && !self.playing && error == nil { self.capture.start() }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.suspend() })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.resume() })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.suspend() })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.resume() })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.suspend() })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.resume() })
        NotificationCenter.default.addObserver(self, selector: #selector(captureFailed(_:)), name: AVCaptureSession.runtimeErrorNotification, object: capture.session)
        loadLibrary()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        capture.start()
    }
    private func resetRecordingControls() {
        timer?.invalidate(); timer = nil; started = nil
        busy = false; recording = false
        recordButton.title = ""
        recordButton.toolTip = "Start recording"
        recordButton.setAccessibilityLabel("Start recording")
        recordButton.symbol = "record.circle"
    }
    private func createMenus() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Show Simple Video Recorder", action: #selector(showWindow), keyEquivalent: "0").target = self
        appMenu.addItem(withTitle: "Show Recordings in Finder", action: #selector(showFolder), keyEquivalent: "") .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close Window", action: #selector(closeWindow), keyEquivalent: "w").target = self
        appMenu.addItem(withTitle: "Quit Simple Video Recorder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = main
    }
    private func buildWindow() {
        panel = MirrorPanel(contentRect: NSRect(x: 100, y: 120, width: 480, height: recordingStripVisible ? 396 : 308), styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Simple Video Recorder"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.minSize = NSSize(width: 360, height: recordingStripVisible ? 306 : 218)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.setFrameAutosaveName("SimpleVideoRecorderWindow")
        let root = VideoHoverView(); root.wantsLayer = true
        root.videoView = preview
        root.onHoverChanged = { [weak self] hovering in
            self?.hoveringVideo = hovering
            self?.updateRecordControlVisibility()
        }
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.10, alpha: 1).cgColor
        root.layer?.cornerRadius = 14; root.layer?.masksToBounds = true
        panel.contentView = root
        preview.preview.session = capture.session
        player.controlsStyle = .floating
        player.videoGravity = .resizeAspectFill
        player.isHidden = true
        let videoMenu = NSMenu()
        videoMenu.delegate = self
        let toggle = videoMenu.addItem(withTitle: "Show past recordings", action: #selector(togglePastRecordings), keyEquivalent: "")
        toggle.target = self
        videoMenu.addItem(.separator())
        videoMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: "").target = self
        preview.menu = videoMenu
        player.videoContextMenu = videoMenu
        let bar = recordControls; bar.isHidden = true; bar.orientation = .horizontal; bar.spacing = 8
        recordButton.title = ""; recordButton.symbol = "record.circle"; recordButton.prominent = true; recordButton.isBordered = false
        recordButton.contentTintColor = .systemRed
        recordButton.target = self; recordButton.action = #selector(toggleRecording)
        recordButton.setAccessibilityLabel("Start recording")
        recordButton.toolTip = "Start recording"
        recordButton.isEnabled = false
        status.font = .systemFont(ofSize: 11)
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        [recordButton].forEach { bar.addArrangedSubview($0) }
        let scroll = recordingScroll; scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = false; scroll.drawsBackground = false
        filmstrip.orientation = .horizontal; filmstrip.alignment = .centerY; filmstrip.spacing = 8
        filmstrip.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        filmstrip.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = filmstrip
        [preview, player, bar, scroll, status].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        recordingStripHeight = scroll.heightAnchor.constraint(equalToConstant: recordingStripVisible ? 82 : 0)
        recordingStripTopGap = preview.bottomAnchor.constraint(equalTo: scroll.topAnchor, constant: recordingStripVisible ? -6 : 0)
        scroll.isHidden = !recordingStripVisible
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: root.topAnchor), preview.leadingAnchor.constraint(equalTo: root.leadingAnchor), preview.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            recordingStripTopGap,
            player.topAnchor.constraint(equalTo: preview.topAnchor), player.bottomAnchor.constraint(equalTo: preview.bottomAnchor), player.leadingAnchor.constraint(equalTo: preview.leadingAnchor), player.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), recordingStripHeight, scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: recordButton.intrinsicContentSize.width),
            bar.centerXAnchor.constraint(equalTo: root.centerXAnchor), bar.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 12), bar.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12), bar.bottomAnchor.constraint(equalTo: preview.bottomAnchor, constant: -10), bar.heightAnchor.constraint(equalToConstant: recordButton.intrinsicContentSize.height),
            status.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 8), status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12), status.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            filmstrip.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor)
        ])
    }
    private func updateRecordControlVisibility() {
        recordControls.isHidden = !(hoveringVideo || recordingStripVisible || recording || busy || recordWhenReady)
    }
    @objc private func toggleRecording() {
        guard !recordWhenReady, !suspended else { return }
        if playing && !busy {
            goLive()
            recordWhenReady = true
            status.stringValue = "Starting camera to record…"
            return
        }
        if recording {
            recordButton.isEnabled = false
            status.stringValue = "Saving…"
            capture.finish()
        } else if !busy {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
                let url = folder.appendingPathComponent("Video \(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6)).mov")
                busy = true; recordButton.isEnabled = false
                status.stringValue = "Preparing recording…"
                capture.record(to: url)
            } catch { status.stringValue = error.localizedDescription; status.toolTip = error.localizedDescription }
        }
    }
    private func updateTime() {
        let seconds = Int(Date().timeIntervalSince(started ?? Date()))
        status.stringValue = String(format: "Recording %02d:%02d", seconds / 60, seconds % 60)
    }
    @objc private func goLive() {
        guard !busy else { return }
        player.player?.pause(); player.player = nil; player.isHidden = true
        playing = false; preview.isHidden = false
        selectedRecording = nil; updateSelection()
        status.stringValue = "Starting camera…"; recordButton.isEnabled = false
        capture.start()
    }
    @objc private func playRecording(_ sender: NSButton) {
        guard !busy, !recordWhenReady, recordings.indices.contains(sender.tag) else { return }
        playing = true; capture.stop()
        preview.isHidden = true; player.isHidden = false
        player.player?.pause(); player.player = AVPlayer(url: recordings[sender.tag]); player.player?.play()
        recordButton.isEnabled = !suspended
        selectedRecording = recordings[sender.tag]
        updateSelection()
        status.stringValue = ""
        status.toolTip = nil
    }
    private func loadLibrary() {
        libraryTask?.cancel()
        libraryGeneration += 1
        recordings = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension.lowercased() == "mov" && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        let current = Set(recordings)
        for url in Array(recordingButtons.keys) where !current.contains(url) {
            if let button = recordingButtons.removeValue(forKey: url) {
                filmstrip.removeArrangedSubview(button); button.removeFromSuperview()
            }
            loadedThumbnails.remove(url)
            recordingVersions.removeValue(forKey: url)
        }
        let formatter = DateFormatter(); formatter.dateFormat = "d MMM · HH:mm"
        for (index, url) in recordings.enumerated() {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let version = "\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            if recordingVersions[url] != version {
                loadedThumbnails.remove(url)
                recordingButtons[url]?.thumbnail = nil
                recordingButtons[url]?.durationLabel = ""
                recordingVersions[url] = version
            }
            if let existing = recordingButtons[url] {
                existing.tag = index
                existing.selected = selectedRecording == url
                continue
            }
            let button = RecordingButton(title: "", target: self, action: #selector(playRecording(_:)))
            button.tag = index; button.imagePosition = .imageAbove; button.imageScaling = .scaleProportionallyUpOrDown
            button.font = .systemFont(ofSize: 9); button.isBordered = false
            let date = recordingDate(url)
            button.dateLabel = formatter.string(from: date)
            button.toolTip = DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .short)
            button.setAccessibilityLabel("Play recording from \(button.toolTip ?? button.dateLabel)")
            button.onDelete = { [weak self] in self?.moveToTrash(url) }
            recordingButtons[url] = button
            button.selected = selectedRecording == url
            button.widthAnchor.constraint(equalToConstant: 124).isActive = true
            button.heightAnchor.constraint(equalToConstant: 90).isActive = true
            let menu = NSMenu(); let item = menu.addItem(withTitle: "Show in Finder", action: #selector(revealRecording(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = url
            let trash = menu.addItem(withTitle: "Move to Trash", action: #selector(deleteRecording(_:)), keyEquivalent: "")
            trash.target = self; trash.representedObject = url
            button.menu = menu
            filmstrip.insertArrangedSubview(button, at: index)
        }
        updateRecordingStripVisibility()
        loadPendingThumbnails()
    }
    private func loadPendingThumbnails() {
        libraryTask?.cancel()
        libraryGeneration += 1
        guard recordingStripVisible, panel.isVisible else { return }
        let generation = libraryGeneration
        let entries = recordings.compactMap { url -> (URL, RecordingButton)? in
            guard !loadedThumbnails.contains(url), let button = recordingButtons[url] else { return nil }
            return (url, button)
        }
        libraryTask = Task { @MainActor [weak self] in
            for (url, button) in entries {
                guard !Task.isCancelled else { return }
                let result = await ThumbnailCache.shared.load(url)
                guard let self, !Task.isCancelled, self.libraryGeneration == generation else { return }
                if let data = result.image, let image = NSImage(data: data) {
                    button.thumbnail = image
                }
                self.loadedThumbnails.insert(url)
                let seconds = result.seconds
                button.durationLabel = String(format: "%d:%02d", seconds / 60, seconds % 60)
            }
        }
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first?.title = recordingStripVisible ? "Hide past recordings" : "Show past recordings"
        menu.items.first?.isEnabled = !recordings.isEmpty
    }
    @objc private func togglePastRecordings() {
        showPastRecordings = !recordingStripVisible
        updateRecordingStripVisibility()
        loadPendingThumbnails()
    }
    private func updateRecordingStripVisibility() {
        defer { updateRecordControlVisibility() }
        if recordings.isEmpty { showPastRecordings = false }
        let visible = showPastRecordings && !recordings.isEmpty
        guard visible != recordingStripVisible else { return }
        let heightChange: CGFloat = visible ? 88 : -88
        recordingStripVisible = visible
        recordingScroll.isHidden = !visible
        if !visible { libraryTask?.cancel() }
        recordingStripHeight.constant = visible ? 82 : 0
        recordingStripTopGap.constant = visible ? -6 : 0
        panel.minSize = NSSize(width: 360, height: visible ? 306 : 218)
        var frame = panel.frame
        frame.size.height += heightChange
        frame.origin.y -= heightChange // Keep the video and top edge in place.
        panel.setFrame(frame, display: true)
        panel.saveFrame(usingName: "SimpleVideoRecorderWindow")
        UserDefaults.standard.set(visible, forKey: "RecordingStripVisible")
    }
    private func recordingDate(_ url: URL) -> Date {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let name = url.deletingPathExtension().lastPathComponent
        if name.hasPrefix("Video "), let date = formatter.date(from: String(name.dropFirst(6).prefix(19))) { return date }
        return (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }
    private func updateSelection() {
        for (url, button) in recordingButtons { button.selected = url == selectedRecording }
    }
    @objc private func deleteRecording(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { moveToTrash(url) }
    }
    private func moveToTrash(_ url: URL) {
        guard !busy else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            if selectedRecording == url { goLive() }
            loadedThumbnails.remove(url)
            loadLibrary()
            updateSelection()
        } catch {
            status.stringValue = "Couldn’t move recording to Trash"
            status.toolTip = error.localizedDescription
        }
    }
    @objc private func revealRecording(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    @objc private func showFolder() {
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); NSWorkspace.shared.open(folder) }
        catch { status.stringValue = error.localizedDescription }
    }
    @objc private func showWindow() { panel.makeKeyAndOrderFront(nil); loadLibrary(); if !playing && !busy { goLive() } }
    @objc private func showSettings() { settingsController.showSettings() }
    private func cancelPendingRecording() {
        recordWhenReady = false
    }
    @objc private func closeWindow() {
        if settingsController.window?.isKeyWindow == true {
            settingsController.close()
            return
        }
        cancelPendingRecording()
        player.player?.pause(); player.player = nil; player.isHidden = true
        playing = false; selectedRecording = nil; updateSelection()
        preview.isHidden = false
        libraryTask?.cancel()
        if busy { closing = true; recordButton.isEnabled = false; status.stringValue = "Saving…"; capture.stop() }
        else { capture.stop(); panel.orderOut(nil) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { closeWindow(); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        cancelPendingRecording()
        if busy { quitting = true; capture.stop(); return .terminateLater }
        capture.stop(); return .terminateNow
    }
    private func suspend() {
        cancelPendingRecording()
        suspended = true; player.player?.pause(); capture.stop(); recordButton.isEnabled = false
        status.stringValue = busy ? "Saving…" : "Camera paused"
    }
    private func resume() { suspended = false; if panel.isVisible && !playing && !busy { goLive() } }
    @objc private func captureFailed(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
        capture.handleRuntimeError("Camera interrupted. Reopen the window to reconnect." + (error.map { " " + $0.localizedDescription } ?? ""))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
