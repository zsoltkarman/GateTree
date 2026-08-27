// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftTerm
import SwiftUI

struct SSHSessionPane: View {
    let connection: SSHConnection
    let password: String?
    let isActive: Bool
    let close: () -> Void

    var body: some View {
        EmbeddedSSHTerminal(connection: connection, password: password, isActive: isActive)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
    }
}

private struct EmbeddedSSHTerminal: NSViewRepresentable {
    let connection: SSHConnection
    let password: String?
    let isActive: Bool

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = GateTreeTerminalView(frame: .zero)
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        // On Hungarian and other international layouts Option is used to type
        // characters such as |, @ and €. Keep it as the macOS compose key
        // instead of treating it as the terminal Meta modifier.
        terminal.optionAsMetaKey = false
        var arguments = ["-p", String(connection.port)]
        if !connection.username.isEmpty { arguments += ["-l", connection.username] }
        if let tunnel = connection.localTunnel {
            arguments += ["-o", "ExitOnForwardFailure=yes", "-L", "\(tunnel.localPort):\(tunnel.remoteHost):\(tunnel.remotePort)"]
        }
        arguments.append(connection.host)
        terminal.startProcess(executable: "/usr/bin/ssh", args: arguments, environment: askPassEnvironment(password: password), execName: nil)
        if isActive { DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) } }
        return terminal
    }

    func updateNSView(_ terminal: LocalProcessTerminalView, context: Context) {
        guard isActive else { return }
        DispatchQueue.main.async {
            if terminal.window?.firstResponder !== terminal { terminal.window?.makeFirstResponder(terminal) }
        }
    }

    private func askPassEnvironment(password: String?) -> [String]? {
        guard let password, !password.isEmpty else { return nil }
        let helperURL = FileManager.default.temporaryDirectory.appendingPathComponent("gatetree-ssh-askpass-\(UUID().uuidString)")
        let script = "#!/bin/sh\nprintf '%s\\n' \"$GATETREE_SSH_PASSWORD\"\n"
        do {
            try script.write(to: helperURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        } catch { return nil }
        var environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        environment += ["SSH_ASKPASS=\(helperURL.path)", "SSH_ASKPASS_REQUIRE=force", "DISPLAY=gatetree:0", "GATETREE_SSH_PASSWORD=\(password)"]
        return environment
    }
}

private final class GateTreeTerminalView: LocalProcessTerminalView {
    private var didDragWithPrimaryButton = false
    private var forwardsRightClickToRemote = false
    override func mouseDown(with event: NSEvent) { didDragWithPrimaryButton = false; super.mouseDown(with: event) }
    override func mouseDragged(with event: NSEvent) { didDragWithPrimaryButton = true; super.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { super.mouseUp(with: event); if didDragWithPrimaryButton, terminal.mouseMode == .off { copy(self) } }
    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        forwardsRightClickToRemote = event.modifierFlags.contains(.shift)
        guard !forwardsRightClickToRemote else { super.mouseDown(with: event); return }
        let menu = NSMenu(); menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: ""); menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        menu.items.forEach { $0.target = self }; NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    override func rightMouseUp(with event: NSEvent) { guard forwardsRightClickToRemote else { return }; super.mouseUp(with: event); forwardsRightClickToRemote = false }
}
