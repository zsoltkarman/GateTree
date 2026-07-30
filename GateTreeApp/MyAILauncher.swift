// SPDX-License-Identifier: Apache-2.0

import AppKit

enum MyAILauncher {
    static func openMenuInTerminal() {
        let codexPath = preferredCodexPath()
        let command = "clear; \(codexPath) 'my-ai'; exec /bin/zsh -l"
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
            alert.messageText = "Could Not Open My AI"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private static func preferredCodexPath() -> String {
        let candidates = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        if let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
            return path
        }
        return "/usr/bin/env codex"
    }

    private static func appleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
