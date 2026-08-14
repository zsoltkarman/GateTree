// SPDX-License-Identifier: Apache-2.0

import AppKit
import QuartzCore
import SwiftUI

struct RDPConnectionPane: NSViewRepresentable {
    let connection: SSHConnection
    let password: String?
    let onClose: () -> Void

    func makeNSView(context: Context) -> EmbeddedRDPView {
        EmbeddedRDPView(connection: connection, password: password, onClose: onClose)
    }

    func updateNSView(_ nsView: EmbeddedRDPView, context: Context) {}

    static func dismantleNSView(_ nsView: EmbeddedRDPView, coordinator: ()) {
        nsView.stop()
    }
}

final class EmbeddedRDPView: NSView, GateTreeRDPClientDelegate {
    private let connection: SSHConnection
    private let password: String
    private let onClose: () -> Void
    private var client: GateTreeRDPClient?
    private var started = false
    private var desktopSize = CGSize(width: 1280, height: 800)
    private let statusLayer = CATextLayer()

    init(connection: SSHConnection, password: String?, onClose: @escaping () -> Void) {
        self.connection = connection
        self.password = password ?? ""
        self.onClose = onClose
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
        statusLayer.string = "Connecting to \(connection.host)…"
        statusLayer.alignmentMode = .center
        statusLayer.fontSize = 14
        statusLayer.foregroundColor = NSColor.white.cgColor
        statusLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        statusLayer.frame = bounds
        layer?.addSublayer(statusLayer)
    }

    required init?(coder: NSCoder) { nil }
    deinit { stop() }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); startIfNeeded() }
    override func layout() { super.layout(); statusLayer.frame = bounds; startIfNeeded() }

    private func startIfNeeded() {
        guard !started, window != nil, bounds.width > 100, bounds.height > 100 else { return }
        started = true
        let scale = window?.backingScaleFactor ?? 2
        let width = max(640, Int((bounds.width * scale).rounded()))
        let height = max(480, Int((bounds.height * scale).rounded()))
        desktopSize = CGSize(width: width, height: height)
        guard let client = GateTreeRDPClient(host: connection.host, port: connection.port, username: connection.username,
                                             domain: connection.domain, password: password, width: width, height: height) else {
            statusLayer.string = "Could not initialize the embedded RDP client."
            return
        }
        client.delegate = self
        self.client = client
        client.start()
        window?.makeFirstResponder(self)
    }

    func stop() { client?.stop(); client = nil }

    func rdpClientDidUpdateFrame(_ image: CGImage) {
        desktopSize = CGSize(width: image.width, height: image.height)
        statusLayer.removeFromSuperlayer()
        layer?.contents = image
    }

    func rdpClientDidDisconnect(_ message: String?) {
        statusLayer.string = message ?? "RDP session disconnected."
        if statusLayer.superlayer == nil { layer?.addSublayer(statusLayer) }
    }

    private func point(for event: NSEvent) -> (Int, Int) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0, bounds.height > 0 else { return (0, 0) }
        let x = Int((point.x / bounds.width * desktopSize.width).rounded())
        let y = Int(((bounds.height - point.y) / bounds.height * desktopSize.height).rounded())
        return (max(0, min(Int(desktopSize.width) - 1, x)), max(0, min(Int(desktopSize.height) - 1, y)))
    }

    override func mouseMoved(with event: NSEvent) { let p = point(for: event); client?.sendMouseMoveX(p.0, y: p.1) }
    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseDown(with event: NSEvent) { let p = point(for: event); client?.sendMouseButton(1, down: true, x: p.0, y: p.1) }
    override func mouseUp(with event: NSEvent) { let p = point(for: event); client?.sendMouseButton(1, down: false, x: p.0, y: p.1) }
    override func rightMouseDown(with event: NSEvent) { let p = point(for: event); client?.sendMouseButton(2, down: true, x: p.0, y: p.1) }
    override func rightMouseUp(with event: NSEvent) { let p = point(for: event); client?.sendMouseButton(2, down: false, x: p.0, y: p.1) }
    override func keyDown(with event: NSEvent) { event.characters?.unicodeScalars.forEach { client?.sendUnicode($0.value <= 0xFFFF ? unichar($0.value) : 0) } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect], owner: self, userInfo: nil))
    }
}
