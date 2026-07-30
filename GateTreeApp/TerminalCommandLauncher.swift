// SPDX-License-Identifier: Apache-2.0

import AppKit

enum TerminalCommandLauncher {
    static func openInTerminal(_ command: String) {
        let source = """
        tell application "Terminal"
            activate
            do script "\(appleScriptString(command))"
        end tell
        """

        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)

        if let error {
            let message = error[NSAppleScript.errorMessage] as? String
                ?? "macOS could not open Terminal."
            let alert = NSAlert()
            alert.messageText = "Could Not Open Terminal"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
