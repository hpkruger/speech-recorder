import AppKit
import AVFoundation

enum MicrophoneSettings {
    private static let key = "PreferredMicrophone"

    static var preference: [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static func select(_ device: AVCaptureDevice?) {
        if let device {
            UserDefaults.standard.set(["id": device.uniqueID, "name": device.localizedName], forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func availableDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.sorted { $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending }
    }

    static func recordingDevice() -> AVCaptureDevice? {
        if let id = preference["id"], let device = availableDevices().first(where: { $0.uniqueID == id }) {
            return device
        }
        return AVCaptureDevice.default(for: .audio)
    }
}

final class SettingsWindowController: NSWindowController {
    private let microphonePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let detail = NSTextField(wrappingLabelWithString: "")
    private var devices: [AVCaptureDevice] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        super.init(window: window)

        let title = NSTextField(labelWithString: "Default microphone")
        title.font = .boldSystemFont(ofSize: 13)
        microphonePicker.target = self
        microphonePicker.action = #selector(selectMicrophone)
        microphonePicker.setAccessibilityLabel("Default microphone")
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        let note = NSTextField(wrappingLabelWithString: "Changes are saved automatically and apply to your next recording. If your selected microphone is unavailable, the system default is used.")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, microphonePicker, detail, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            microphonePicker.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshDevices()
            })
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func showSettings() {
        refreshDevices()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshDevices() {
        devices = MicrophoneSettings.availableDevices()
        let preference = MicrophoneSettings.preference
        microphonePicker.removeAllItems()
        microphonePicker.addItem(withTitle: "System Default")
        for device in devices {
            // Add items individually so devices with identical names remain selectable.
            let item = NSMenuItem(title: device.localizedName, action: nil, keyEquivalent: "")
            item.representedObject = device.uniqueID
            microphonePicker.menu?.addItem(item)
        }
        if let id = preference["id"] {
            if let index = devices.firstIndex(where: { $0.uniqueID == id }) {
                microphonePicker.selectItem(at: index + 1)
            } else {
                let item = NSMenuItem(title: "\(preference["name"] ?? "Selected microphone") (unavailable)", action: nil, keyEquivalent: "")
                item.representedObject = id
                microphonePicker.menu?.addItem(item)
                microphonePicker.select(item)
            }
        } else {
            microphonePicker.selectItem(at: 0)
        }
        if let device = MicrophoneSettings.recordingDevice() {
            detail.stringValue = "Microphone for next recording: \(device.localizedName)"
        } else {
            detail.stringValue = "No microphone available. Connect a microphone to record audio."
        }
    }

    @objc private func selectMicrophone() {
        if microphonePicker.indexOfSelectedItem == 0 {
            MicrophoneSettings.select(nil)
        } else if let id = microphonePicker.selectedItem?.representedObject as? String,
                  let device = devices.first(where: { $0.uniqueID == id }) {
            MicrophoneSettings.select(device)
        }
        refreshDevices()
    }
}
