// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

@main
struct GateTreeApp: App {
    @StateObject private var workspaceStore = SecureWorkspaceStore()

    init() {
        if let appIcon = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = appIcon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workspaceStore)
                .frame(minWidth: 900, minHeight: 560)
                .background(WindowTitleSetter(title: AppBuildInfo.windowTitle))
        }
        .commands {
            CommandMenu("Connections") {
                Button("New Folder") {
                    workspaceStore.showFolderCreation()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!workspaceStore.isUnlocked || workspaceStore.isProcessing)
            }
            CommandMenu("Security") {
                if workspaceStore.storageMode == .encrypted {
                    Button("Change Master Password…") {
                        workspaceStore.showPasswordChange()
                    }
                    Button("Decrypt Workspace…") {
                        workspaceStore.showDecryptionConfirmation()
                    }
                } else {
                    Button("Encrypt Workspace…") {
                        workspaceStore.showEncryptionSetup()
                    }
                }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Workspace") {
                    workspaceStore.save()
                }
                .keyboardShortcut("s")
                .disabled(!workspaceStore.isUnlocked)

                Button("Save Workspace As…") {
                    workspaceStore.saveWorkspaceAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!workspaceStore.isUnlocked || workspaceStore.isProcessing)
            }
            CommandGroup(replacing: .help) {
                Button("GateTree Help") {
                    workspaceStore.isShowingHelp = true
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}
