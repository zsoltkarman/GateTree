// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftTerm
import SwiftUI

struct SSHSessionPane: View {
    let connection: SSHConnection
    let password: String?
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image("OracleLinuxServer")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(connection.name)
                        .font(.headline)
                    Text("SSH · \(connection.username)@\(connection.host):\(connection.port)")
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

            EmbeddedSSHTerminal(connection: connection, password: password)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }
}

private struct EmbeddedSSHTerminal: NSViewRepresentable {
    let connection: SSHConnection
    let password: String?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        var arguments = ["-p", String(connection.port)]
        if !connection.username.isEmpty {
            arguments += ["-l", connection.username]
        }
        arguments.append(connection.host)
        terminal.startProcess(
            executable: "/usr/bin/ssh",
            args: arguments,
            environment: askPassEnvironment(password: password),
            execName: nil
        )
        DispatchQueue.main.async {
            terminal.window?.makeFirstResponder(terminal)
        }
        return terminal
    }

    func updateNSView(_ terminal: LocalProcessTerminalView, context: Context) {
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
