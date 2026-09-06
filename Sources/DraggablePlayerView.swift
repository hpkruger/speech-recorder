import AppKit
import AVKit

/// AVKit consumes background mouse events, so observe local events before they reach it.
/// Interactive controls keep their normal clicks and drags; only video-surface drags move the window.
final class DraggablePlayerView: AVPlayerView {
    var videoContextMenu: NSMenu?
    private var eventMonitor: Any?
    private var dragAnchor: (mouse: NSPoint, origin: NSPoint)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        dragAnchor = nil
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]) { [weak self] event in
            guard let self, !self.isHidden, let window = self.window, event.window === window else { return event }
            switch event.type {
            case .rightMouseDown:
                guard self.canDrag(at: event.locationInWindow), let menu = self.videoContextMenu else { return event }
                NSMenu.popUpContextMenu(menu, with: event, for: self)
                return nil
            case .leftMouseDown:
                guard self.canDrag(at: event.locationInWindow) else { self.dragAnchor = nil; return event }
                self.dragAnchor = (window.convertPoint(toScreen: event.locationInWindow), window.frame.origin)
                return nil
            case .leftMouseDragged:
                guard let anchor = self.dragAnchor else { return event }
                let point = window.convertPoint(toScreen: event.locationInWindow)
                window.setFrameOrigin(NSPoint(x: anchor.origin.x + point.x - anchor.mouse.x, y: anchor.origin.y + point.y - anchor.mouse.y))
                return nil
            case .leftMouseUp:
                guard self.dragAnchor != nil else { return event }
                self.dragAnchor = nil
                window.saveFrame(usingName: "SpeechRecorderWindow")
                return nil
            default: return event
            }
        }
    }
    deinit { if let eventMonitor { NSEvent.removeMonitor(eventMonitor) } }

    private func canDrag(at windowPoint: NSPoint) -> Bool {
        guard bounds.contains(convert(windowPoint, from: nil)), let superview else { return false }
        // Check the actual topmost view, including sibling overlay controls.
        let parentPoint = superview.superview?.convert(windowPoint, from: nil) ?? windowPoint
        guard let hit = superview.hitTest(parentPoint), hit === self || hit.isDescendant(of: self) else { return false }
        var view: NSView? = hit
        while let candidate = view, candidate !== self {
            let coversVideo = candidate.bounds.width >= bounds.width * 0.95 && candidate.bounds.height >= bounds.height * 0.95
            let role = candidate.accessibilityRole()
            let interactive = candidate is NSControl || role == .button || role == .slider || role == .popUpButton || role == .textField || role == .menuButton
            if interactive && !coversVideo { return false }
            view = candidate.superview
        }
        return true
    }
}
