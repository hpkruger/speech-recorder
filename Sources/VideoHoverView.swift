import AppKit

/// Track the video region, including its overlay controls, even when another app has focus.
final class VideoHoverView: NSView {
    weak var videoView: NSView?
    var onHoverChanged: ((Bool) -> Void)?
    private var videoTrackingArea: NSTrackingArea?
    private var hovering = false
    private var mouseMonitor: Any?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor); self.mouseMonitor = nil }
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged]) { [weak self] event in
            guard let self, event.window === self.window, let video = self.videoView else { return event }
            self.setHovering(self.convert(video.bounds, from: video).contains(self.convert(event.locationInWindow, from: nil)))
            return event
        }
    }
    deinit { if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) } }

    override func layout() {
        super.layout()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let videoTrackingArea { removeTrackingArea(videoTrackingArea) }
        guard let videoView else { return }
        let videoRect = convert(videoView.bounds, from: videoView)
        let area = NSTrackingArea(rect: videoRect, options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area)
        videoTrackingArea = area
        if let window, window.isVisible {
            setHovering(videoRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)))
        } else { setHovering(false) }
    }
    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }
    private func setHovering(_ value: Bool) {
        guard value != hovering else { return }
        hovering = value
        onHoverChanged?(value)
    }
}
