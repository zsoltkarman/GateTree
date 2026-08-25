// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftTerm
import SwiftUI

/// Stores SSH host fingerprints in GateTree's sandbox container instead of the
/// user's `~/.ssh/known_hosts`, which a TestFlight build is not allowed to read.
private enum GateTreeSSHHostKeyStore {
    static func knownHostsURL() -> URL {
        let manager = FileManager.default
        let directory = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GateTree", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("known_hosts")
        if !manager.fileExists(atPath: fileURL.path) {
            manager.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        return fileURL
    }
}

struct SSHSessionPane: View {
    let connection: SSHConnection
    let password: String?
    let isActive: Bool
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "terminal")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(connection.name)
                        .font(.headline)
                    Text("SSH · \(connection.username)@\(connection.host):\(connection.port)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let tunnel = connection.localTunnel {
                        Text("Tunnel · localhost:\(tunnel.localPort) → \(tunnel.remoteHost):\(tunnel.remotePort)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .help("Close connection")
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            EmbeddedSSHTerminal(connection: connection, password: password, isActive: isActive)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }
}

private struct EmbeddedSSHTerminal: NSViewRepresentable {
    let connection: SSHConnection
    let password: String?
    let isActive: Bool

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = GateTreeTerminalView(frame: .zero)
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let knownHostsURL = GateTreeSSHHostKeyStore.knownHostsURL()
        var arguments = [
            "-p", String(connection.port),
            "-o", "UserKnownHostsFile=\(knownHostsURL.path)",
            "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "StrictHostKeyChecking=accept-new"
        ]
        if !connection.username.isEmpty {
            arguments += ["-l", connection.username]
        }
        if let tunnel = connection.localTunnel {
            arguments += [
                "-o", "ExitOnForwardFailure=yes",
                "-L", "\(tunnel.localPort):\(tunnel.remoteHost):\(tunnel.remotePort)"
            ]
        }
        arguments.append(connection.host)
        terminal.startProcess(
            executable: "/usr/bin/ssh",
            args: arguments,
            environment: askPassEnvironment(password: password),
            execName: nil
        )
        if isActive {
            DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) }
        }
        return terminal
    }

    func updateNSView(_ terminal: LocalProcessTerminalView, context: Context) {
        guard isActive else { return }
        DispatchQueue.main.async {
            if terminal.window?.firstResponder !== terminal {
                terminal.window?.makeFirstResponder(terminal)
            }
        }
    }

    private func askPassEnvironment(password: String?) -> [String]? {
        guard let password, !password.isEmpty else { return nil }

        let helperURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("gatetree-ssh-askpass-\(UUID().uuidString)")
        let script = "#!/bin/sh\nprintf '%s\\n' \"$GATETREE_SSH_PASSWORD\"\n"
        do {
            try script.write(to: helperURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        } catch {
            return nil
        }

        var environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        environment.append("SSH_ASKPASS=\(helperURL.path)")
        environment.append("SSH_ASKPASS_REQUIRE=force")
        environment.append("DISPLAY=gatetree:0")
        environment.append("GATETREE_SSH_PASSWORD=\(password)")
        return environment
    }
}

/// Adds the familiar terminal clipboard interactions on top of SwiftTerm.
/// A left-button drag selects and copies; right-click provides copy/paste.
/// Hold Shift while right-clicking when a remote TUI needs the mouse event.
private final class GateTreeTerminalView: LocalProcessTerminalView {
    private var didDragWithPrimaryButton = false
    private var forwardsRightClickToRemote = false

    override func mouseDown(with event: NSEvent) {
        didDragWithPrimaryButton = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        didDragWithPrimaryButton = true
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard didDragWithPrimaryButton, terminal.mouseMode == .off else { return }
        copy(self)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        forwardsRightClickToRemote = event.modifierFlags.contains(.shift)
        guard !forwardsRightClickToRemote else {
            super.mouseDown(with: event)
            return
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard forwardsRightClickToRemote else { return }
        super.mouseUp(with: event)
        forwardsRightClickToRemote = false
    }
}
