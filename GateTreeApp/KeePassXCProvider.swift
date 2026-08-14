// SPDX-License-Identifier: Apache-2.0

import Foundation

struct KeePassXCEntry: Sendable {
    let username: String
    let password: String
}

enum KeePassXCProvider {
    static let cliURL = URL(fileURLWithPath: "/Applications/KeePassXC.app/Contents/MacOS/keepassxc-cli")

    static func readEntry(databaseURL: URL, entryPath: String, masterPassword: String) throws -> KeePassXCEntry {
        guard FileManager.default.isExecutableFile(atPath: cliURL.path) else { throw Error.cliUnavailable }
        let firstAttempt = runShow(databaseURL: databaseURL, entryPath: entryPath, masterPassword: masterPassword)
        if firstAttempt.status == 0, let entry = firstAttempt.entry {
            return entry
        }

        // KeePassXC's Group Path column includes the database root-group name,
        // while `keepassxc-cli show` resolves paths relative to that root.
        // Retry with that first component removed so either form works in GateTree.
        let components = entryPath.split(separator: "/", omittingEmptySubsequences: true)
        if components.count > 1 {
            let rootRelativePath = components.dropFirst().joined(separator: "/")
            let secondAttempt = runShow(databaseURL: databaseURL, entryPath: rootRelativePath, masterPassword: masterPassword)
            if secondAttempt.status == 0, let entry = secondAttempt.entry {
                return entry
            }
            throw Error.entryUnavailable(secondAttempt.error)
        }
        throw Error.entryUnavailable(firstAttempt.error)
    }

    private static func runShow(databaseURL: URL, entryPath: String, masterPassword: String) -> (status: Int32, entry: KeePassXCEntry?, error: String?) {
        let process = Process()
        process.executableURL = cliURL
        process.arguments = ["show", "--show-protected", "--attributes", "UserName", "--attributes", "Password", databaseURL.path, entryPath]
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return (1, nil, error.localizedDescription)
        }
        input.fileHandleForWriting.write(Data((masterPassword + "\n").utf8))
        input.fileHandleForWriting.closeFile()
        process.waitUntilExit()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        let details = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0,
              let text = String(data: outputData, encoding: .utf8) else {
            return (process.terminationStatus, nil, details)
        }
        let values = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard values.count >= 2 else { return (process.terminationStatus, nil, details) }
        return (process.terminationStatus, KeePassXCEntry(username: values[0], password: values[1]), details)
    }

    enum Error: LocalizedError {
        case cliUnavailable
        case entryUnavailable(String?)
        var errorDescription: String? {
            switch self {
            case .cliUnavailable: return "KeePassXC CLI is not available."
            case .entryUnavailable(let details):
                let fallback = "Could not read the KeePassXC entry. Check the database password and entry path."
                return details?.isEmpty == false ? "\(fallback) KeePassXC: \(details!)" : fallback
            }
        }
    }
}
