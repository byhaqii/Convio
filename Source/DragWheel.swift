import AppKit
import CoreGraphics

enum WheelGeometry {
    static let size: CGFloat = 280
    static let innerRadius: CGFloat = 60
    static let outerRadius: CGFloat = 132

    static func sector(at point: CGPoint) -> Int? {
        let x = point.x - size / 2, y = point.y - size / 2
        let distance = hypot(x, y)
        guard distance >= innerRadius, distance <= outerRadius else { return nil }
        let angle = atan2(y, x)
        let clockwise = (CGFloat.pi / 2 - angle + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        let centered = (clockwise + .pi / 4).truncatingRemainder(dividingBy: 2 * .pi)
        let index = Int(centered / (.pi / 2))
        let offset = centered.truncatingRemainder(dividingBy: .pi / 2)
        guard offset > 0.025, offset < .pi / 2 - 0.025 else { return nil }
        guard path(for: index).contains(point) else { return nil }
        return index
    }

    static func path(for index: Int) -> CGPath {
        let center = CGPoint(x: size / 2, y: size / 2)
        let angle = CGFloat.pi / 2 - CGFloat(index) * .pi / 2
        let start = angle - .pi / 4 + 0.025, end = angle + .pi / 4 - 0.025
        let corner: CGFloat = 14
        func point(_ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
            CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        let path = CGMutablePath()
        path.addArc(center: center, radius: outerRadius, startAngle: start + corner / outerRadius, endAngle: end - corner / outerRadius, clockwise: false)
        path.addQuadCurve(to: point(outerRadius - corner, end), control: point(outerRadius, end))
        path.addLine(to: point(innerRadius + corner, end))
        path.addQuadCurve(to: point(innerRadius, end - corner / innerRadius), control: point(innerRadius, end))
        path.addArc(center: center, radius: innerRadius, startAngle: end - corner / innerRadius, endAngle: start + corner / innerRadius, clockwise: true)
        path.addQuadCurve(to: point(innerRadius + corner, start), control: point(innerRadius, start))
        path.addLine(to: point(outerRadius - corner, start))
        path.addQuadCurve(to: point(outerRadius, start + corner / outerRadius), control: point(outerRadius, start))
        path.closeSubpath()
        return path
    }
}

@MainActor private final class WheelPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }
}

@MainActor final class DragWheelController {
    private var timer: Timer?
    private var panel: NSPanel?
    private var wheel: WheelView?
    private var idleChange = NSPasteboard(name: .drag).changeCount
    private var dismissed = false
    private var processing = false
    var isProcessing: Bool { processing }
    var updating = false {
        didSet { if updating && !processing { hide() } }
    }
    private var dismissing = false
    private var releaseAt: Date?
    private var manualUntil: Date?
    var enabled = true {
        didSet { if !enabled && !processing { hide() } }
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func poll() {
        guard !dismissing, !updating else { return }
        if !processing, panel?.isVisible == true, CGEventSource.keyState(.combinedSessionState, key: 53) {
            manualUntil = nil; dismissed = true; hide(); return
        }
        if let until = manualUntil {
            if Date() < until || processing { return }
            manualUntil = nil; hide()
        }
        let board = NSPasteboard(name: .drag)
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        if !pressed {
            idleChange = board.changeCount
            dismissed = false
            if panel?.isVisible == true && !processing {
                if releaseAt == nil { releaseAt = Date() }
                if Date().timeIntervalSince(releaseAt ?? Date()) > 0.25 { hide() }
            }
            return
        }
        releaseAt = nil
        guard enabled, !processing else { return }
        if CGEventSource.keyState(.combinedSessionState, key: 53) {
            dismissed = true; hide(); return
        }
        guard NSEvent.modifierFlags.contains(.shift) else { hide(); return }
        guard !dismissed, board.changeCount != idleChange else { return }
        let urls = Self.files(from: board)
        guard !urls.isEmpty else { return }
        if panel?.isVisible != true { show(urls) }
    }

    func openWheel() {
        guard !processing, !dismissing, !updating else { return }
        manualUntil = Date().addingTimeInterval(20)
        show([])
        panel?.makeKeyAndOrderFront(nil)
        panel?.makeMain()
    }

    static func files(from board: NSPasteboard) -> [URL] {
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { $0.isFileURL }
    }

    func show(_ urls: [URL]) {
        guard !dismissing else { return }
        if panel == nil {
            let panel = WheelPanel(contentRect: NSRect(x: 0, y: 0, width: WheelGeometry.size, height: WheelGeometry.size),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.title = "Convy Quick Convert"
            panel.onCancel = { [weak self] in
                guard let self, !processing else { return }
                manualUntil = nil; dismissed = true; hide()
            }
            let wheel = WheelView(frame: panel.contentView?.bounds ?? .zero)
            wheel.onDrop = { [weak self] urls, format in self?.convert(urls, format: format) }
            panel.contentView = wheel
            self.wheel = wheel; self.panel = panel
        }
        guard let panel, let wheel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = WheelGeometry.size
        panel.setFrameOrigin(NSPoint(x: min(max(mouse.x - size / 2, visible.minX), visible.maxX - size),
            y: min(max(mouse.y - size / 2, visible.minY), visible.maxY - size)))
        wheel.showCount(urls.count)
        panel.orderFrontRegardless()
        wheel.animate(appearing: true)
    }

    private func hide(completion: @escaping @MainActor () -> Void = {}) {
        guard let panel, let wheel, panel.isVisible, !dismissing else { return }
        dismissing = true
        wheel.stopAcceptingDrops()
        wheel.animate(appearing: false) { [weak self] in
            panel.orderOut(nil)
            self?.dismissing = false
            self?.releaseAt = nil
            wheel.highlight(nil)
            completion()
        }
    }

    private func convert(_ urls: [URL], format: ImageFormat) {
        guard !processing, !updating else { return }
        processing = true
        manualUntil = nil
        dismissed = true
        wheel?.showStatus("Memproses…", detail: "\(urls.count) file · \(format.rawValue)")
        Task {
            var failures: [String] = []
            for url in urls {
                do {
                    _ = try await Converter.convert(url, to: format, quality: 0.85,
                        folder: url.deletingLastPathComponent())
                } catch { failures.append(url.lastPathComponent + ": " + error.localizedDescription) }
            }
            processing = false
            hide {
                if let failure = failures.first {
                    let alert = NSAlert()
                    alert.messageText = "Konversi gagal"
                    alert.informativeText = "\(failures.count) file gagal.\n" + failure
                    alert.runModal()
                }
            }
        }
    }
}

@MainActor final class WheelView: NSView {
    var onDrop: (([URL], ImageFormat) -> Void)?
    private var highlights: [CAShapeLayer] = []
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private var accepting = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Konversi cepat. Tahan Shift, lepas gambar pada format. Escape untuk batal.")
        for (index, format) in ImageFormat.allCases.enumerated() {
            let surface = glass(frame: bounds)
            surface.wantsLayer = true
            let shape = WheelGeometry.path(for: index)
            let mask = CAShapeLayer(); mask.path = shape
            surface.layer?.mask = mask
            addSubview(surface)
            let tint = CAShapeLayer(); tint.path = shape; tint.fillColor = NSColor.clear.cgColor
            layer?.addSublayer(tint); highlights.append(tint)
            let edge = CAShapeLayer(); edge.path = shape
            edge.fillColor = NSColor.clear.cgColor
            edge.strokeColor = NSColor.white.withAlphaComponent(0.5).cgColor; edge.lineWidth = 1
            layer?.addSublayer(edge)
            let label = NSTextField(labelWithString: format.rawValue)
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            label.textColor = .labelColor; label.alignment = .center
            let angle = CGFloat.pi / 2 - CGFloat(index) * .pi / 2
            label.frame = NSRect(x: 140 + cos(angle) * 98 - 36, y: 140 + sin(angle) * 98 - 11, width: 72, height: 22)
            addSubview(label)
        }
        let center = glass(frame: NSRect(x: 86, y: 86, width: 108, height: 108))
        center.wantsLayer = true; center.layer?.cornerRadius = 54; center.layer?.masksToBounds = true
        addSubview(center)
        title.font = .systemFont(ofSize: 14, weight: .semibold); title.alignment = .center
        title.frame = NSRect(x: 89, y: 143, width: 102, height: 22)
        detail.font = .systemFont(ofSize: 10); detail.alignment = .center
        detail.frame = NSRect(x: 97, y: 108, width: 86, height: 33)
        addSubview(title); addSubview(detail)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func glass(frame: NSRect) -> NSView {
        if #available(macOS 26, *) {
            let view = NSGlassEffectView(frame: frame)
            view.style = .regular
            return view
        }
        let view = NSVisualEffectView(frame: frame)
        view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
        return view
    }

    func showCount(_ count: Int) {
        accepting = true
        title.stringValue = count == 0 ? "Tarik file" : "\(count) file"
        detail.stringValue = "Pilih format\nEsc: batal"
        highlight(nil)
    }

    func showStatus(_ text: String, detail: String) {
        accepting = false
        title.stringValue = text
        self.detail.stringValue = detail
        highlight(nil)
        NSAccessibility.post(element: self, notification: .announcementRequested,
            userInfo: [.announcement: text + ". " + detail, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func highlight(_ index: Int?) {
        for i in highlights.indices {
            highlights[i].fillColor = (i == index ? NSColor.controlAccentColor.withAlphaComponent(0.32) : .clear).cgColor
        }
    }

    private func update(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard accepting, !DragWheelController.files(from: sender.draggingPasteboard).isEmpty else { return [] }
        let index = WheelGeometry.sector(at: convert(sender.draggingLocation, from: nil))
        highlight(index)
        return index == nil ? [] : .copy
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { highlight(nil) }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { update(sender) == .copy }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard accepting, let index = WheelGeometry.sector(at: convert(sender.draggingLocation, from: nil)) else { return false }
        let urls = DragWheelController.files(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onDrop?(urls, ImageFormat.allCases[index])
        return true
    }
    func stopAcceptingDrops() { accepting = false }

    func animate(appearing: Bool, completion: @escaping @MainActor () -> Void = {}) {
        guard let layer else { completion(); return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = reduced ? 0.08 : appearing ? 0.18 : 0.12
        func transform(_ scale: CGFloat) -> CATransform3D {
            var value = CATransform3DIdentity
            value.m11 = scale; value.m22 = scale
            value.m41 = bounds.midX * (1 - scale); value.m42 = bounds.midY * (1 - scale)
            return value
        }
        let from = appearing ? transform(reduced ? 1 : 0.9) : layer.presentation()?.sublayerTransform ?? transform(1)
        let to = transform(appearing || reduced ? 1 : 0.82)
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = appearing ? 0 : layer.presentation()?.opacity ?? 1
        opacity.toValue = appearing ? 1 : 0
        let scale = CABasicAnimation(keyPath: "sublayerTransform")
        scale.fromValue = NSValue(caTransform3D: from); scale.toValue = NSValue(caTransform3D: to)
        let group = CAAnimationGroup(); group.animations = [opacity, scale]
        group.duration = duration; group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
        layer.opacity = appearing ? 1 : 0; layer.sublayerTransform = to
        layer.add(group, forKey: "wheelVisibility")
        CATransaction.commit()
    }
}
