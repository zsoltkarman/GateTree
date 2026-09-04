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
        // `makeNSView` creates the terminal with a .zero frame.  Starting ssh
        // here can therefore give its pseudo-terminal a 0-row/0-column size.
        // Interactive shells use that size while redrawing a history entry, so
        // a later Up-arrow could place the prompt and command on one line.
        // Queue the process until AppKit has assigned a real terminal frame.
        terminal.startProcessWhenLaidOut(
            executable: "/usr/bin/ssh",
            args: arguments,
            environment: sshEnvironment(password: password)
        )
        if isActive { DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) } }
        return terminal
    }

    func updateNSView(_ terminal: LocalProcessTerminalView, context: Context) {
        guard isActive else { return }
        DispatchQueue.main.async {
            if terminal.window?.firstResponder !== terminal { terminal.window?.makeFirstResponder(terminal) }
        }
    }

    private func sshEnvironment(password: String?) -> [String] {
        var environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        // Minimal Oracle Linux installations often include `xterm` but not
        // the extended `xterm-256color` terminfo entry.  Advertising xterm
        // keeps curses applications such as `watch` usable on both minimal
        // and full remote hosts.
        environment.removeAll { $0.hasPrefix("TERM=") }
        environment.append("TERM=xterm")

        guard let password, !password.isEmpty else { return environment }
        let helperURL = FileManager.default.temporaryDirectory.appendingPathComponent("gatetree-ssh-askpass-\(UUID().uuidString)")
        let script = "#!/bin/sh\nprintf '%s\\n' \"$GATETREE_SSH_PASSWORD\"\n"
        do {
            try script.write(to: helperURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
        } catch { return environment }
        environment += ["SSH_ASKPASS=\(helperURL.path)", "SSH_ASKPASS_REQUIRE=force", "DISPLAY=gatetree:0", "GATETREE_SSH_PASSWORD=\(password)"]
        return environment
    }
}

private final class GateTreeTerminalView: LocalProcessTerminalView {
    private var pendingProcessLaunch: (executable: String, arguments: [String], environment: [String]?)?
    private var isProcessLaunchScheduled = false
    private var cursorKeyMonitor: Any?
    private var didDragWithPrimaryButton = false
    private var forwardsRightClickToRemote = false

    func startProcessWhenLaidOut(executable: String, args: [String], environment: [String]?) {
        pendingProcessLaunch = (executable, args, environment)
        launchProcessWhenReady()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        launchProcessWhenReady()
    }

    override func layout() {
        super.layout()
        launchProcessWhenReady()
    }

    private func launchProcessWhenReady() {
        guard pendingProcessLaunch != nil,
              !isProcessLaunchScheduled,
              window != nil,
              bounds.width > 0,
              bounds.height > 0 else { return }

        isProcessLaunchScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self, let launch = self.pendingProcessLaunch else { return }
            self.isProcessLaunchScheduled = false
            guard self.window != nil, self.bounds.width > 0, self.bounds.height > 0,
                  self.terminal.cols > 0, self.terminal.rows > 0 else {
                self.launchProcessWhenReady()
                return
            }
            self.pendingProcessLaunch = nil
            self.startProcess(executable: launch.executable, args: launch.arguments, environment: launch.environment, execName: nil)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cursorKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.window?.firstResponder === self else { return event }
            return self.handleCursorKey(event) ? nil : event
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        cursorKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.window?.firstResponder === self else { return event }
            return self.handleCursorKey(event) ? nil : event
        }
    }

    deinit {
        if let cursorKeyMonitor { NSEvent.removeMonitor(cursorKeyMonitor) }
    }

    private func handleCursorKey(_ event: NSEvent) -> Bool {
        // Send unmodified cursor keys straight to the remote TTY.  Going
        // through AppKit's text-input command selectors has caused the left
        // arrow to arrive as right-arrow input in some embedded SSH sessions.
        // VT100 sequences are what zsh/readline expect for command history and
        // in-line editing.
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty else {
            return false
        }
        switch event.keyCode {
        case 126:
            send([0x1B, 0x5B, 0x41]) // Up: ESC [ A
            return true
        case 125:
            send([0x1B, 0x5B, 0x42]) // Down: ESC [ B
            return true
        case 123:
            send([0x1B, 0x5B, 0x44]) // Left: ESC [ D
            return true
        case 124:
            send([0x1B, 0x5B, 0x43]) // Right: ESC [ C
            return true
        default: return false
        }
    }

    override func mouseDown(with event: NSEvent) { didDragWithPrimaryButton = false; super.mouseDown(with: event) }
    override func mouseDragged(with event: NSEvent) { didDragWithPrimaryButton = true; super.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        // A remote program can leave mouse reporting enabled while it is
        // updating progress output (for example `podman pull`).  Dragging in
        // GateTree is nevertheless a local selection gesture, so always copy
        // it.  Shift-right-click remains the explicit way to send a mouse
        // event to the remote terminal application.
        if didDragWithPrimaryButton { copy(self) }
    }
    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        forwardsRightClickToRemote = event.modifierFlags.contains(.shift)
        guard !forwardsRightClickToRemote else { super.mouseDown(with: event); return }
        let menu = NSMenu(); menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: ""); menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        menu.items.forEach { $0.target = self }; NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    override func rightMouseUp(with event: NSEvent) { guard forwardsRightClickToRemote else { return }; super.mouseUp(with: event); forwardsRightClickToRemote = false }
}
