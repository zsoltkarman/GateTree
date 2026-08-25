// SPDX-License-Identifier: Apache-2.0

import AppKit
import Foundation
import SwiftUI

/// OpenSSH invokes this same signed executable for nested ProxyJump prompts.
/// Unlike a temporary shell script, an executable inside the app bundle is
/// allowed by the App Sandbox and can safely show a native macOS dialog.
private func runSSHAskPass() -> Never {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.activate(ignoringOtherApps: true)

    let prompt = CommandLine.arguments.dropFirst().joined(separator: " ")
    let alert = NSAlert()
    alert.messageText = "SSH verification required"
    alert.informativeText = prompt.isEmpty ? "Enter the verification code to continue." : prompt
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Cancel")
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
    field.placeholderString = "Verification code"
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    DispatchQueue.main.async {
        alert.window.makeFirstResponder(field)
    }

    guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else {
        exit(1)
    }
    FileHandle.standardOutput.write(Data((field.stringValue + "\n").utf8))
    exit(0)
}

if ProcessInfo.processInfo.environment["GATETREE_SSH_ASKPASS"] == "1" {
    runSSHAskPass()
} else {
    GateTreeApp.main()
}
