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

/// Grants the sandboxed app explicit access to the user's OpenSSH config.
/// OpenSSH then receives it through `-F`, so existing Host / ProxyJump rules
/// continue to work in a TestFlight build.
private enum GateTreeSSHConfigStore {
    private static let bookmarkKey = "GateTree.sshConfigBookmark"

    static func beginAccess() -> URL? {
        if let bookmark = UserDefaults.standard.data(forKey: bookmarkKey),
           let url = resolve(bookmark), url.startAccessingSecurityScopedResource() {
            return url
        }

        let panel = NSOpenPanel()
        panel.title = "Allow SSH Configuration Access"
        panel.message = "Choose ~/.ssh/config so GateTree can use your SSH hosts and gateways."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
              ) else {
            return nil
        }
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        return url.startAccessingSecurityScopedResource() ? url : nil
    }

    private static func resolve(_ bookmark: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
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
                    Text(password?.isEmpty == false ? "Using the saved SSH password." : "Enter the SSH password in the terminal when prompted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    final class Coordinator {
        var sshConfigURL: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = GateTreeTerminalView(frame: .zero)
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let knownHostsURL = GateTreeSSHHostKeyStore.knownHostsURL()
        let sshConfigURL = GateTreeSSHConfigStore.beginAccess()
        context.coordinator.sshConfigURL = sshConfigURL
        var arguments = [
            "-p", String(connection.port),
            "-o", "UserKnownHostsFile=\(knownHostsURL.path)",
            "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "StrictHostKeyChecking=accept-new"
        ]
        if let sshConfigURL {
            arguments += ["-F", sshConfigURL.path]
        }
        if password?.isEmpty == false {
            arguments += [
                "-o", "PubkeyAuthentication=no",
                "-o", "GSSAPIAuthentication=no",
                "-o", "PreferredAuthentications=keyboard-interactive,password"
            ]
        }
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
        terminal.useSavedPassword(password)
        terminal.startProcess(
            executable: "/usr/bin/ssh",
            args: arguments,
            environment: nil,
            execName: nil
        )
        if isActive {
            DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) }
        }
        return terminal
    }

    static func dismantleNSView(_ terminal: LocalProcessTerminalView, coordinator: Coordinator) {
        coordinator.sshConfigURL?.stopAccessingSecurityScopedResource()
        terminal.terminate()
    }

    func updateNSView(_ terminal: LocalProcessTerminalView, context: Context) {
        guard isActive else { return }
        DispatchQueue.main.async {
            if terminal.window?.firstResponder !== terminal {
                terminal.window?.makeFirstResponder(terminal)
            }
        }
    }
}

/// Adds the familiar terminal clipboard interactions on top of SwiftTerm.
/// A left-button drag selects and copies; right-click provides copy/paste.
/// Hold Shift while right-clicking when a remote TUI needs the mouse event.
private final class GateTreeTerminalView: LocalProcessTerminalView {
    private var didDragWithPrimaryButton = false
    private var forwardsRightClickToRemote = false
    private var savedPassword: String?
    private var hasSentSavedPassword = false
    private var recentOutput = ""

    func useSavedPassword(_ password: String?) {
        savedPassword = password?.isEmpty == false ? password : nil
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        guard !hasSentSavedPassword, let savedPassword else { return }

        recentOutput += String(decoding: slice, as: UTF8.self).lowercased()
        recentOutput = String(recentOutput.suffix(512))
        guard recentOutput.contains("password:") else { return }

        hasSentSavedPassword = true
        self.savedPassword = nil
        let input = Array((savedPassword + "\n").utf8)
        process.send(data: input[...])
    }

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
