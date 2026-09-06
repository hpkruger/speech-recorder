import AppKit

final class ControlButton: NSButton {
    var symbol = "" { didSet { needsDisplay = true } }
    var prominent = false
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override var title: String { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: prominent && title.isEmpty ? 56 : (title.isEmpty ? 32 : (prominent ? 104 : 76)), height: prominent && title.isEmpty ? 48 : 34) }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let color: NSColor = prominent ? .systemRed : NSColor(white: 1, alpha: isHighlighted ? 0.17 : 0.08)
        color.withAlphaComponent(isEnabled ? (prominent ? 1 : (isHighlighted ? 0.17 : 0.08)) : 0.04).setFill()
        NSBezierPath(roundedRect: rect, xRadius: prominent ? 14 : 10, yRadius: prominent ? 14 : 10).fill()
        let foreground = NSColor.white.withAlphaComponent(isEnabled ? 0.95 : 0.28)
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
        let textSize = title.size(withAttributes: attributes)
        let iconSize: CGFloat = prominent && title.isEmpty ? 26 : 15
        let total = title.isEmpty ? iconSize : iconSize + 7 + textSize.width
        let x = (bounds.width - total) / 2
        if let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: iconSize - 2, weight: .semibold)) {
            let tinted = NSImage(size: icon.size, flipped: false) { rect in
                icon.draw(in: rect)
                foreground.setFill(); rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: x, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize))
        }
        title.draw(at: NSPoint(x: x + iconSize + 7, y: (bounds.height - textSize.height) / 2), withAttributes: attributes)
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: rect, xRadius: prominent ? 14 : 10, yRadius: prominent ? 14 : 10); ring.lineWidth = 2; ring.stroke()
        }
    }
}

final class RecordingButton: NSButton {
    override var isFlipped: Bool { false }
    var thumbnail: NSImage? { didSet { needsDisplay = true } }
    var onDelete: (() -> Void)?
    private let deleteControl = ThumbnailDeleteButton()
    override init(frame: NSRect) {
        super.init(frame: frame)
        deleteControl.target = self; deleteControl.action = #selector(deleteRecording)
        deleteControl.isBordered = false
        deleteControl.setAccessibilityLabel("Delete recording")
        deleteControl.toolTip = "Move this recording to Trash"
        deleteControl.isHidden = true
        addSubview(deleteControl)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        deleteControl.frame = NSRect(x: bounds.width - 28, y: bounds.height - 28, width: 24, height: 24)
    }
    @objc private func deleteRecording() { onDelete?() }
    var selected = false {
        didSet {
            needsDisplay = true
            deleteControl.isHidden = !selected
            setAccessibilityValue(selected ? "Selected" : "")
        }
    }
    var dateLabel = "" { didSet { needsDisplay = true } }
    var durationLabel = "" { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let frame = NSRect(x: 3, y: 23, width: bounds.width - 6, height: bounds.height - 26)
        let path = NSBezierPath(roundedRect: frame, xRadius: 7, yRadius: 7)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor(white: 0.17, alpha: 1).setFill(); frame.fill()
        if let thumbnail, thumbnail.size.width > 0, thumbnail.size.height > 0 {
            let scale = max(frame.width / thumbnail.size.width, frame.height / thumbnail.size.height)
            let size = NSSize(width: thumbnail.size.width * scale, height: thumbnail.size.height * scale)
            let imageRect = NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
            thumbnail.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        if !durationLabel.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.white]
            let size = durationLabel.size(withAttributes: attrs)
            let badge = NSRect(x: frame.maxX - size.width - 9, y: frame.minY + 4, width: size.width + 6, height: size.height + 3)
            NSColor.black.withAlphaComponent(0.65).setFill()
            NSBezierPath(roundedRect: badge, xRadius: 3, yRadius: 3).fill()
            durationLabel.draw(at: NSPoint(x: badge.minX + 3, y: badge.minY + 1), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        if selected || window?.firstResponder === self {
            (selected ? NSColor.systemBlue : NSColor.keyboardFocusIndicatorColor).setStroke()
            let border = NSBezierPath(roundedRect: frame.insetBy(dx: -1, dy: -1), xRadius: 8, yRadius: 8)
            border.lineWidth = 2.5; border.stroke()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: selected ? .semibold : .regular), .foregroundColor: selected ? NSColor.white : NSColor.secondaryLabelColor]
        let size = dateLabel.size(withAttributes: attrs)
        dateLabel.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: 5), withAttributes: attrs)
    }
}

private final class ThumbnailDeleteButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        (isHighlighted ? NSColor.systemRed.blended(withFraction: 0.18, of: .black)! : NSColor.systemRed).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
        NSColor.white.setStroke()
        let cross = NSBezierPath()
        cross.lineWidth = 1.8; cross.lineCapStyle = .round
        cross.move(to: NSPoint(x: 8, y: 8)); cross.line(to: NSPoint(x: 16, y: 16))
        cross.move(to: NSPoint(x: 8, y: 16)); cross.line(to: NSPoint(x: 16, y: 8))
        cross.stroke()
    }
}
