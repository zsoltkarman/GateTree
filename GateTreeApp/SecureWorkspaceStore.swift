// SPDX-License-Identifier: Apache-2.0

import CommonCrypto
import CryptoKit
import Dispatch
import Darwin
import Foundation
import Security
import AppKit

@MainActor
final class SecureWorkspaceStore: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var needsMasterPasswordSetup = false
    @Published private(set) var isProcessing = false
    @Published var errorMessage: String?
    @Published private(set) var folders: [WorkspaceFolder] = []
    @Published private(set) var rootConnections: [SSHConnection] = []
    @Published private(set) var rootWebLinks: [WebLink] = []
    @Published private(set) var rootTerminalCommands: [TerminalCommand] = []
    @Published private(set) var credentials: [Credential] = []
    @Published private(set) var quickAccessWebLinkIDs: [UUID] = []
    @Published private(set) var selectedSSHConnection: SSHConnection?
    @Published private(set) var openSSHConnections: [SSHConnection] = []
    @Published private(set) var selectedRDPConnection: SSHConnection?
    @Published private(set) var openRDPConnections: [SSHConnection] = []
    @Published private(set) var activeSessionID: UUID?
    @Published private(set) var activeSessionProtocol: ConnectionProtocol?
    @Published private(set) var selectedWebLink: WebLink?
    @Published private(set) var activeExternalWebLink: WebLink?
    @Published private(set) var openExternalWebLinks: [WebLink] = []
    @Published private(set) var selectedSSHPassword: String?
    @Published private(set) var isShowingCredentials = false
    @Published private(set) var selectedTreeItemID: UUID?
    @Published private(set) var selectedTreeItemIDs: Set<UUID> = []
    @Published private(set) var expandedFolderIDs: Set<UUID> = []
    @Published var isShowingFolderCreation = false
    @Published var isShowingPasswordChange = false
    @Published var isShowingEncryptionSetup = false
    @Published var isShowingDecryptionConfirmation = false
    @Published var isShowingFolderEditor = false
    @Published var isShowingFolderDeletionConfirmation = false
    @Published var isShowingEmptyTrashConfirmation = false
    @Published var isShowingHelp = false
    @Published var editingFolderName = ""
    @Published var editingFolderCredentialID: UUID?
    @Published var editingFolderTags = ""
    @Published var isShowingSSHConnectionCreation = false
    @Published var isShowingRDPConnectionCreation = false
    @Published var isShowingRDPConnectionEditor = false
    @Published var isShowingWebLinkCreation = false
    @Published var isShowingTerminalCommandCreation = false
    @Published var isShowingTerminalCommandEditor = false
    @Published var isShowingTerminalCommandInput = false
    @Published var terminalCommandInput = ""
    @Published private(set) var isCodexRunning = false
    @Published private(set) var codexResult = ""
    @Published private(set) var codexStatus = ""
    @Published var isShowingCodexResult = false
    @Published var isShowingWebLinkEditor = false
    @Published var isShowingSSHConnectionEditor = false
    @Published var isShowingSSHConnectionDeletionConfirmation = false
    @Published var isShowingSSHUsernamePrompt = false
    @Published var promptedSSHUsername = ""
    @Published var isShowingRDPUsernamePrompt = false
    @Published var promptedRDPUsername = ""
    @Published var isPromptingRDPPassword = false
    @Published var promptedRDPPassword = ""
    @Published var isShowingCredentialCreation = false
    @Published var isShowingCredentialEditor = false
    @Published var isShowingCredentialDeletionConfirmation = false
    @Published var isShowingCredentialAssignment = false
    @Published var selectedCredentialAssignmentID: UUID?
    @Published private(set) var storageMode: WorkspaceStorageMode = .encrypted

    private var masterPassword: String?
    private var workspace = Workspace()
    private var folderParentID: UUID?
    private var editingFolderID: UUID?
    private var deletingFolderID: UUID?
    private var sshConnectionParentFolderID: UUID?
    private var rdpConnectionParentFolderID: UUID?
    private var webLinkParentFolderID: UUID?
    private var terminalCommandParentFolderID: UUID?
    private var terminalCommandAwaitingInput: TerminalCommand?
    private var codexProcess: Process?
    @Published private(set) var editingTerminalCommand: TerminalCommand?
    @Published private(set) var editingWebLink: WebLink?
    @Published private(set) var editingSSHConnection: SSHConnection?
    @Published private(set) var editingRDPConnection: SSHConnection?
    private var deletingSSHConnectionID: UUID?
    private var pendingSSHConnection: SSHConnection?
    private var pendingRDPConnection: SSHConnection?
    private var pendingRDPUsername = ""
    private var pendingRDPWasAlreadyOpen = false
    private var deletingCredentialID: UUID?
    @Published private(set) var editingCredential: Credential?
    private var webLinksBeingOpened: Set<UUID> = []
    private var chromeTabIDsByWebLinkID: [UUID: Int] = [:]
    private var sshPasswordsByConnectionID: [UUID: String] = [:]
    private var rdpPasswordsByConnectionID: [UUID: String] = [:]
    private var keepassMasterPasswords: [String: String] = [:]
    private var workspaceWatcher: DispatchSourceFileSystemObject?
    private var workspaceReloadTask: Task<Void, Never>?
    private var workspaceReloadTimer: Timer?
    private var workspaceModificationDate: Date?

    init(fileManager: FileManager = .default) {
        chromeTabIDsByWebLinkID = Dictionary(
            uniqueKeysWithValues: (UserDefaults.standard.dictionary(forKey: "GateTree.chromeTabIDs") ?? [:]).compactMap { key, value in
                guard let id = UUID(uuidString: key), let tabID = value as? Int else { return nil }
                return (id, tabID)
            }
        )
        expandedFolderIDs = Set(
            UserDefaults.standard.stringArray(forKey: "GateTree.expandedFolderIDs")?.compactMap { UUID(uuidString: $0) } ?? []
        )
        let restoredSelectedTreeItemID = UserDefaults.standard.string(forKey: "GateTree.lastSelectedTreeItemID").flatMap { UUID(uuidString: $0) }
        selectedTreeItemID = restoredSelectedTreeItemID
        if let restoredSelectedTreeItemID {
            selectedTreeItemIDs = [restoredSelectedTreeItemID]
        }
        startWorkspaceWatcher()
        startWorkspacePolling()
        guard fileManager.fileExists(atPath: WorkspaceCrypto.configURL.path) else {
            needsMasterPasswordSetup = true
            return
        }

        if WorkspaceCrypto.isEncryptedFile() {
            needsMasterPasswordSetup = false
        } else {
            do {
                let loadedWorkspace = try WorkspaceCrypto.loadPlaintext()
                workspace = loadedWorkspace
                folders = loadedWorkspace.folders
                rootConnections = loadedWorkspace.rootConnections
                rootWebLinks = loadedWorkspace.rootWebLinks
                rootTerminalCommands = loadedWorkspace.rootTerminalCommands
                credentials = loadedWorkspace.credentials
                quickAccessWebLinkIDs = loadedWorkspace.quickAccessWebLinkIDs
                storageMode = .plaintext
                needsMasterPasswordSetup = false
                isUnlocked = true
                workspaceModificationDate = currentWorkspaceModificationDate()
            } catch {
                needsMasterPasswordSetup = false
                errorMessage = "The workspace file is not readable."
            }
        }
    }

    deinit {
        workspaceReloadTask?.cancel()
        workspaceWatcher?.cancel()
        workspaceReloadTimer?.invalidate()
    }

    private func startWorkspaceWatcher() {
        let directoryURL = WorkspaceCrypto.configURL.deletingLastPathComponent()
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleWorkspaceReload()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        workspaceWatcher = source
        source.resume()
    }

    private func scheduleWorkspaceReload() {
        guard isUnlocked, !isProcessing else { return }
        workspaceReloadTask?.cancel()
        workspaceReloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.reloadWorkspaceFromDisk()
        }
    }

    private func startWorkspacePolling() {
        workspaceReloadTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.reloadWorkspaceIfChanged()
        }
    }

    private func reloadWorkspaceIfChanged() {
        guard isUnlocked, !isProcessing,
              !isShowingFolderCreation,
              !isShowingFolderEditor,
              !isShowingSSHConnectionCreation,
              !isShowingSSHConnectionEditor,
              !isShowingWebLinkCreation,
              !isShowingWebLinkEditor,
              !isShowingTerminalCommandCreation,
              !isShowingTerminalCommandEditor,
              !isShowingCredentialCreation,
              !isShowingCredentialEditor,
              let modificationDate = currentWorkspaceModificationDate(),
              modificationDate != workspaceModificationDate else {
            return
        }

        scheduleWorkspaceReload()
    }

    private func currentWorkspaceModificationDate() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: WorkspaceCrypto.configURL.path)[.modificationDate] as? Date
    }

    private func reloadWorkspaceFromDisk() {
        guard isUnlocked, !isProcessing else { return }
        do {
            let loadedWorkspace: Workspace
            switch storageMode {
            case .encrypted:
                guard let masterPassword else { return }
                loadedWorkspace = try WorkspaceCrypto.load(password: masterPassword)
            case .plaintext:
                loadedWorkspace = try WorkspaceCrypto.loadPlaintext()
            }
            workspace = loadedWorkspace
            folders = loadedWorkspace.folders
            rootConnections = loadedWorkspace.rootConnections
            rootWebLinks = loadedWorkspace.rootWebLinks
            rootTerminalCommands = loadedWorkspace.rootTerminalCommands
            credentials = loadedWorkspace.credentials
            quickAccessWebLinkIDs = loadedWorkspace.quickAccessWebLinkIDs
            workspaceModificationDate = currentWorkspaceModificationDate()
        } catch {
            errorMessage = "The workspace changed outside GateTree but could not be reloaded."
        }
    }

    func createWorkspace(masterPassword: String) {
        guard masterPassword.count >= 12 else {
            errorMessage = "Use at least 12 characters for the master password."
            return
        }

        isProcessing = true
        let newWorkspace = Workspace()

        Task.detached {
            do {
                try WorkspaceCrypto.save(newWorkspace, password: masterPassword)
                await MainActor.run {
                    self.workspace = newWorkspace
                    self.folders = []
                    self.rootConnections = []
                    self.rootWebLinks = []
                    self.rootTerminalCommands = []
                    self.credentials = []
                    self.quickAccessWebLinkIDs = []
                    self.masterPassword = masterPassword
                    self.storageMode = .encrypted
                    self.needsMasterPasswordSetup = false
                    self.isUnlocked = true
                    self.isProcessing = false
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = "Could not create the encrypted workspace."
                }
            }
        }
    }

    func unlock(masterPassword: String) {
        isProcessing = true

        Task.detached {
            do {
                let loadedWorkspace = try WorkspaceCrypto.load(password: masterPassword)
                await MainActor.run {
                    self.workspace = loadedWorkspace
                    self.folders = loadedWorkspace.folders
                    self.rootConnections = loadedWorkspace.rootConnections
                    self.rootWebLinks = loadedWorkspace.rootWebLinks
                    self.rootTerminalCommands = loadedWorkspace.rootTerminalCommands
                    self.credentials = loadedWorkspace.credentials
                    self.quickAccessWebLinkIDs = loadedWorkspace.quickAccessWebLinkIDs
                    self.masterPassword = masterPassword
                    self.storageMode = .encrypted
                    self.isUnlocked = true
                    self.isProcessing = false
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = "Could not unlock the workspace. Check the master password."
                }
            }
        }
    }

    func save() {
        guard !isProcessing else { return }

        isProcessing = true
        let currentWorkspace = workspace
        let currentPassword = masterPassword
        let mode = storageMode

        Task.detached {
            do {
                switch mode {
                case .encrypted:
                    guard let currentPassword else { throw WorkspaceCrypto.CryptoError.invalidFile }
                    try WorkspaceCrypto.save(currentWorkspace, password: currentPassword)
                case .plaintext:
                    try WorkspaceCrypto.savePlaintext(currentWorkspace)
                }
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = nil
                    self.workspaceModificationDate = self.currentWorkspaceModificationDate()
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = "Could not save the encrypted workspace."
                }
            }
        }
    }

    func saveWorkspaceAs() {
        guard isUnlocked, !isProcessing else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Workspace.gatetree"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        saveCopy(to: destination)
    }

    private func saveCopy(to destination: URL) {
        guard !isProcessing else { return }

        isProcessing = true
        let currentWorkspace = workspace
        let currentPassword = masterPassword
        let mode = storageMode

        Task.detached {
            do {
                switch mode {
                case .encrypted:
                    guard let currentPassword else { throw WorkspaceCrypto.CryptoError.invalidFile }
                    try WorkspaceCrypto.save(currentWorkspace, password: currentPassword, to: destination)
                case .plaintext:
                    try WorkspaceCrypto.savePlaintext(currentWorkspace, to: destination)
                }
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = "Could not save the workspace copy."
                }
            }
        }
    }

    var configPath: String { WorkspaceCrypto.configURL.path }

    func showPasswordChange() { isShowingPasswordChange = true }
    func showEncryptionSetup() { isShowingEncryptionSetup = true }
    func showDecryptionConfirmation() { isShowingDecryptionConfirmation = true }

    func showCredentials() {
        selectedSSHConnection = nil
        activeExternalWebLink = nil
        isShowingCredentials = true
    }

    func showCredentialCreation() {
        guard !isProcessing else { return }
        isShowingCredentialCreation = true
    }

    func createCredential(name: String, username: String, databasePath: String, databaseBookmark: Data?, entryPath: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let databasePath = databasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let entryPath = entryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !databasePath.isEmpty, !entryPath.isEmpty, !isProcessing else { return }
        credentials.append(Credential(
            name: trimmedName,
            username: trimmedUsername,
            keepassDatabasePath: databasePath,
            keepassDatabaseBookmark: databaseBookmark,
            keepassEntryPath: entryPath
        ))
        synchronizeWorkspace()
        isShowingCredentialCreation = false
        save()
    }

    func cancelCredentialCreation() { isShowingCredentialCreation = false }

    func showCredentialEditor(_ credential: Credential) {
        guard !isProcessing else { return }
        editingCredential = credential
        isShowingCredentialEditor = true
    }

    func updateCredential(name: String, username: String, databasePath: String, databaseBookmark: Data?, entryPath: String) {
        guard let editingCredential, !isProcessing else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let databasePath = databasePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let entryPath = entryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !databasePath.isEmpty, !entryPath.isEmpty,
              let index = credentials.firstIndex(where: { $0.id == editingCredential.id }) else { return }
        let bookmark = databaseBookmark ?? (databasePath == editingCredential.keepassDatabasePath ? editingCredential.keepassDatabaseBookmark : nil)
        credentials[index] = Credential(
            id: editingCredential.id,
            name: trimmedName,
            username: trimmedUsername,
            keepassDatabasePath: databasePath,
            keepassDatabaseBookmark: bookmark,
            keepassEntryPath: entryPath
        )
        synchronizeWorkspace()
        self.editingCredential = nil
        isShowingCredentialEditor = false
        save()
    }

    func cancelCredentialEditor() {
        editingCredential = nil
        isShowingCredentialEditor = false
    }

    func showCredentialDeletionConfirmation(_ credential: Credential) {
        guard !isProcessing else { return }
        guard !isCredentialInUse(credential.id) else {
            errorMessage = "This credential is assigned to a folder or connection. Remove those assignments before deleting it."
            return
        }
        deletingCredentialID = credential.id
        isShowingCredentialDeletionConfirmation = true
    }

    func deleteConfirmedCredential() {
        guard let deletingCredentialID, !isProcessing else { return }
        guard !isCredentialInUse(deletingCredentialID) else {
            self.deletingCredentialID = nil
            isShowingCredentialDeletionConfirmation = false
            errorMessage = "This credential is assigned to a folder or connection. Remove those assignments before deleting it."
            return
        }
        credentials.removeAll { $0.id == deletingCredentialID }
        synchronizeWorkspace()
        self.deletingCredentialID = nil
        isShowingCredentialDeletionConfirmation = false
        save()
    }

    func changeMasterPassword(currentPassword: String, newPassword: String) {
        guard newPassword.count >= 12 else {
            errorMessage = "Use at least 12 characters for the new master password."
            return
        }
        isProcessing = true

        Task.detached {
            do {
                let loadedWorkspace = try WorkspaceCrypto.load(password: currentPassword)
                try WorkspaceCrypto.save(loadedWorkspace, password: newPassword)
                await MainActor.run {
                    self.workspace = loadedWorkspace
                    self.masterPassword = newPassword
                    self.isShowingPasswordChange = false
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = "The current master password is incorrect."
                }
            }
        }
    }

    func encryptWorkspace(masterPassword: String) {
        guard masterPassword.count >= 12 else {
            errorMessage = "Use at least 12 characters for the master password."
            return
        }
        isProcessing = true
        let currentWorkspace = workspace

        Task.detached {
            do {
                try WorkspaceCrypto.save(currentWorkspace, password: masterPassword)
                await MainActor.run {
                    self.masterPassword = masterPassword
                    self.storageMode = .encrypted
                    self.isShowingEncryptionSetup = false
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = "Could not encrypt the workspace."
                }
            }
        }
    }

    func decryptWorkspace() {
        guard storageMode == .encrypted else { return }
        isProcessing = true
        let currentWorkspace = workspace

        Task.detached {
            do {
                try WorkspaceCrypto.savePlaintext(currentWorkspace)
                await MainActor.run {
                    self.masterPassword = nil
                    self.storageMode = .plaintext
                    self.isShowingDecryptionConfirmation = false
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = "Could not decrypt the workspace."
                }
            }
        }
    }

    func showFolderCreation(parentID: UUID? = nil) {
        guard isUnlocked, !isProcessing else { return }
        folderParentID = parentID
        isShowingFolderCreation = true
    }

    func showSSHConnectionCreation(in folder: WorkspaceFolder? = nil) {
        guard !isProcessing else { return }
        sshConnectionParentFolderID = folder?.id
        isShowingSSHConnectionCreation = true
    }

    func showRDPConnectionCreation(in folder: WorkspaceFolder? = nil) {
        guard !isProcessing else { return }
        rdpConnectionParentFolderID = folder?.id
        isShowingRDPConnectionCreation = true
    }

    func showWebLinkCreation(in folder: WorkspaceFolder? = nil) {
        guard !isProcessing else { return }
        webLinkParentFolderID = folder?.id
        isShowingWebLinkCreation = true
    }

    func showTerminalCommandCreation(in folder: WorkspaceFolder? = nil) {
        guard !isProcessing else { return }
        terminalCommandParentFolderID = folder?.id
        isShowingTerminalCommandCreation = true
    }

    func createTerminalCommand(name: String, command: String, tags: [String]) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedCommand.isEmpty, !isProcessing else { return }

        let terminalCommand = TerminalCommand(name: trimmedName, command: trimmedCommand, tags: normalizedTags(tags))
        if let terminalCommandParentFolderID {
            guard insert(terminalCommand, into: &folders, below: terminalCommandParentFolderID) else {
                errorMessage = "The destination folder is no longer available."
                return
            }
        } else {
            rootTerminalCommands.append(terminalCommand)
        }
        synchronizeWorkspace()
        self.terminalCommandParentFolderID = nil
        isShowingTerminalCommandCreation = false
        save()
    }

    func cancelTerminalCommandCreation() {
        terminalCommandParentFolderID = nil
        isShowingTerminalCommandCreation = false
    }

    func showTerminalCommandEditor(_ terminalCommand: TerminalCommand) {
        guard !isProcessing else { return }
        editingTerminalCommand = terminalCommand
        isShowingTerminalCommandEditor = true
    }

    func updateTerminalCommand(name: String, command: String, tags: [String]) {
        guard let editingTerminalCommand, !isProcessing else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedCommand.isEmpty else { return }

        let updated = TerminalCommand(id: editingTerminalCommand.id, name: trimmedName, command: trimmedCommand, tags: normalizedTags(tags))
        if let index = rootTerminalCommands.firstIndex(where: { $0.id == updated.id }) {
            rootTerminalCommands[index] = updated
        } else if !updateTerminalCommand(updated, in: &folders) {
            errorMessage = "The terminal connection is no longer available."
            return
        }
        synchronizeWorkspace()
        self.editingTerminalCommand = nil
        isShowingTerminalCommandEditor = false
        save()
    }

    func cancelTerminalCommandEditor() {
        editingTerminalCommand = nil
        isShowingTerminalCommandEditor = false
    }

    func createWebLink(name: String, urlString: String, tags: [String], icon: WebLinkIcon = .icon12) {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              !isProcessing else {
            errorMessage = "Enter a valid http or https URL."
            return
        }

        let webLink = WebLink(name: trimmedName.isEmpty ? (url.host ?? trimmedURL) : trimmedName, url: trimmedURL, tags: normalizedTags(tags), icon: icon)
        if let webLinkParentFolderID {
            guard insert(webLink, into: &folders, below: webLinkParentFolderID) else {
                errorMessage = "The destination folder is no longer available."
                return
            }
        } else {
            rootWebLinks.append(webLink)
        }
        synchronizeWorkspace()
        self.webLinkParentFolderID = nil
        isShowingWebLinkCreation = false
        save()
    }

    func cancelWebLinkCreation() {
        webLinkParentFolderID = nil
        isShowingWebLinkCreation = false
    }

    func showWebLinkEditor(_ webLink: WebLink) {
        guard !isProcessing else { return }
        editingWebLink = webLink
        isShowingWebLinkEditor = true
    }

    func updateWebLink(name: String, urlString: String, tags: [String], icon: WebLinkIcon) {
        guard let editingWebLink, !isProcessing else { return }
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            errorMessage = "Enter a valid http or https URL."
            return
        }
        let updated = WebLink(
            id: editingWebLink.id,
            name: trimmedName.isEmpty ? (url.host ?? trimmedURL) : trimmedName,
            url: trimmedURL,
            tags: normalizedTags(tags),
            icon: icon
        )
        if let index = rootWebLinks.firstIndex(where: { $0.id == updated.id }) {
            rootWebLinks[index] = updated
        } else if !updateWebLink(updated, in: &folders) {
            errorMessage = "The web bookmark is no longer available."
            return
        }
        synchronizeWorkspace()
        self.editingWebLink = nil
        isShowingWebLinkEditor = false
        save()
    }

    func cancelWebLinkEditor() {
        editingWebLink = nil
        isShowingWebLinkEditor = false
    }

    func launchTerminalCommand(_ terminalCommand: TerminalCommand) {
        guard !isProcessing else { return }
        guard terminalCommand.command.contains("my-ai") else {
            TerminalCommandLauncher.openInTerminal(terminalCommand.command)
            return
        }

        if terminalCommand.command.contains("my-ai 21") {
            terminalCommandAwaitingInput = terminalCommand
            terminalCommandInput = ""
            isShowingTerminalCommandInput = true
        } else {
            runCodex(prompt: codexPrompt(from: terminalCommand.command))
        }
    }

    func runTerminalCommandWithInput() {
        guard let terminalCommandAwaitingInput else { return }
        let details = terminalCommandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = details.isEmpty ? "my-ai 21" : "my-ai 21 \(details)"
        self.terminalCommandAwaitingInput = nil
        terminalCommandInput = ""
        isShowingTerminalCommandInput = false
        runCodex(prompt: prompt)
    }

    func cancelTerminalCommandInput() {
        terminalCommandAwaitingInput = nil
        terminalCommandInput = ""
        isShowingTerminalCommandInput = false
    }

    func cancelCodexRun() {
        codexProcess?.terminate()
    }

    func closeCodexResult() {
        guard !isCodexRunning else { return }
        isShowingCodexResult = false
        codexResult = ""
        codexStatus = ""
    }

    private func runCodex(prompt: String) {
        guard !isCodexRunning else { return }
        let executable = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            errorMessage = "Codex CLI was not found at /opt/homebrew/bin/codex."
            return
        }

        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = [
            "exec", "--sandbox", "read-only", "--color", "never",
            "--skip-git-repo-check", prompt
        ]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardOutput = output
        process.standardError = errors

        codexResult = ""
        codexStatus = "Running Codex incident triage…"
        isCodexRunning = true
        isShowingCodexResult = true
        codexProcess = process

        let appendOutput: (Data) -> Void = { [weak self] data in
            let text = String(decoding: data, as: UTF8.self)
            guard !text.isEmpty else { return }
            Task { @MainActor in self?.codexResult.append(text) }
        }
        output.fileHandleForReading.readabilityHandler = { handle in appendOutput(handle.availableData) }
        errors.fileHandleForReading.readabilityHandler = { handle in appendOutput(handle.availableData) }

        process.terminationHandler = { [weak self, weak output, weak errors] process in
            output?.fileHandleForReading.readabilityHandler = nil
            errors?.fileHandleForReading.readabilityHandler = nil
            let finalOutput = output?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            let finalErrors = errors?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            Task { @MainActor in
                appendOutput(finalOutput)
                appendOutput(finalErrors)
                guard let self else { return }
                self.isCodexRunning = false
                self.codexProcess = nil
                self.codexStatus = process.terminationReason == .uncaughtSignal
                    ? "Cancelled."
                    : "Finished (exit code \(process.terminationStatus))."
                if self.codexResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.codexResult = "Codex returned no output."
                }
            }
        }

        do {
            try process.run()
        } catch {
            isCodexRunning = false
            codexProcess = nil
            codexStatus = "Could not start Codex."
            codexResult = error.localizedDescription
        }
    }

    private func codexPrompt(from command: String) -> String {
        command
            .replacingOccurrences(of: "codex", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\\\"'"))
    }

    func createSSHConnection(name: String, host: String, username: String, port: Int, tags: [String], localTunnel: SSHLocalTunnel?) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty,
              (1...65_535).contains(port),
              isValid(localTunnel: localTunnel),
              !isProcessing else { return }

        let connection = SSHConnection(
            name: trimmedName.isEmpty ? trimmedHost : trimmedName,
            host: trimmedHost,
            username: trimmedUsername,
            port: port,
            credentialID: pendingConnectionCredentialID,
            tags: normalizedTags(tags),
            localTunnel: localTunnel
        )
        if let sshConnectionParentFolderID {
            guard insert(connection, into: &folders, below: sshConnectionParentFolderID) else {
                errorMessage = "The destination folder is no longer available."
                return
            }
        } else {
            rootConnections.append(connection)
        }

        synchronizeWorkspace()
        self.sshConnectionParentFolderID = nil
        isShowingSSHConnectionCreation = false
        save()
    }

    private var pendingConnectionCredentialID: UUID?

    func setNewConnectionCredential(_ credentialID: UUID?) {
        pendingConnectionCredentialID = credentialID
    }

    func cancelSSHConnectionCreation() {
        sshConnectionParentFolderID = nil
        pendingConnectionCredentialID = nil
        isShowingSSHConnectionCreation = false
    }

    func createRDPConnection(name: String, host: String, username: String, domain: String, port: Int, credentialID: UUID?, tags: [String]) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, (1...65_535).contains(port), !isProcessing else { return }

        let connection = SSHConnection(
            name: trimmedName.isEmpty ? trimmedHost : trimmedName,
            host: trimmedHost,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            credentialID: credentialID,
            tags: normalizedTags(tags),
            connectionType: .rdp,
            domain: normalizedRDPDomain(domain)
        )
        if let rdpConnectionParentFolderID {
            guard insert(connection, into: &folders, below: rdpConnectionParentFolderID) else {
                errorMessage = "The destination folder is no longer available."
                return
            }
        } else {
            rootConnections.append(connection)
        }
        synchronizeWorkspace()
        rdpConnectionParentFolderID = nil
        isShowingRDPConnectionCreation = false
        save()
    }

    func cancelRDPConnectionCreation() {
        rdpConnectionParentFolderID = nil
        isShowingRDPConnectionCreation = false
    }

    func launchRDPConnection(_ connection: SSHConnection) {
        guard connection.connectionType == .rdp, !isProcessing else { return }
        pendingRDPWasAlreadyOpen = openRDPConnections.contains(where: { $0.id == connection.id })
        activateRDPConnection(connection, password: rdpPasswordsByConnectionID[connection.id])
        let credential = effectiveCredential(for: connection)
        let entry = credential.flatMap(keepassEntry(for:))
        let username = connection.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (entry?.username ?? credential?.username ?? "")
            : connection.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            pendingRDPConnection = connection
            promptedRDPUsername = ""
            isShowingRDPUsernamePrompt = true
            return
        }

        startRDPConnection(connection, username: username)
    }

    func connectWithPromptedRDPUsername() {
        let username = promptedRDPUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pendingRDPConnection, !username.isEmpty else { return }
        promptedRDPUsername = ""
        isShowingRDPUsernamePrompt = false
        startRDPConnection(pendingRDPConnection, username: username)
    }

    func connectWithPromptedRDPPassword() {
        guard let pendingRDPConnection, !pendingRDPUsername.isEmpty else { return }
        let sessionConnection = rdpSessionConnection(pendingRDPConnection, username: pendingRDPUsername)
        activateRDPConnection(sessionConnection, password: promptedRDPPassword)
        self.pendingRDPConnection = nil
        pendingRDPUsername = ""
        promptedRDPPassword = ""
        isPromptingRDPPassword = false
    }

    func cancelRDPUsernamePrompt() {
        if !pendingRDPWasAlreadyOpen, let pendingRDPConnection {
            closeRDPConnection(pendingRDPConnection.id)
        }
        pendingRDPConnection = nil
        pendingRDPUsername = ""
        pendingRDPWasAlreadyOpen = false
        promptedRDPUsername = ""
        promptedRDPPassword = ""
        isShowingRDPUsernamePrompt = false
        isPromptingRDPPassword = false
    }

    private func startRDPConnection(_ connection: SSHConnection, username: String) {
        let sessionConnection = rdpSessionConnection(connection, username: username)
        if let password = effectiveCredential(for: connection).flatMap(keepassEntry(for:))?.password {
            activateRDPConnection(sessionConnection, password: password)
        } else {
            pendingRDPConnection = connection
            pendingRDPUsername = username
            promptedRDPPassword = ""
            isPromptingRDPPassword = true
        }
    }

    private func rdpSessionConnection(_ connection: SSHConnection, username: String) -> SSHConnection {
        let rawUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        var normalizedUsername = rawUsername
        var normalizedDomain = connection.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = rawUsername.firstIndex(of: "\\") {
            normalizedDomain = String(rawUsername[..<separator])
            normalizedUsername = String(rawUsername[rawUsername.index(after: separator)...])
        }
        return SSHConnection(
            id: connection.id,
            name: connection.name,
            host: connection.host,
            username: normalizedUsername,
            port: connection.port,
            credentialID: connection.credentialID,
            tags: connection.tags,
            connectionType: .rdp,
            domain: normalizedDomain
        )
    }

    func rdpDomainForEditor(_ connection: SSHConnection) -> String {
        normalizedRDPDomain(connection.domain)
    }

    private func normalizedRDPDomain(_ value: String) -> String {
        let domain = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // A Windows domain never contains '='. Older experimental RDP records
        // could contain an encoded password in this newly added field; do not
        // show or save such a value as a domain.
        guard !domain.contains("="), domain.count <= 63 else { return "" }
        return domain
    }

    func showSSHConnectionEditor(_ connection: SSHConnection) {
        guard !isProcessing else { return }
        editingSSHConnection = connection
        isShowingSSHConnectionEditor = true
    }

    func showRDPConnectionEditor(_ connection: SSHConnection) {
        guard connection.connectionType == .rdp, !isProcessing else { return }
        editingRDPConnection = connection
        isShowingRDPConnectionEditor = true
    }

    func updateRDPConnection(name: String, host: String, username: String, domain: String, port: Int, credentialID: UUID?, tags: [String]) {
        guard let editingRDPConnection,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...65_535).contains(port), !isProcessing else { return }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = SSHConnection(id: editingRDPConnection.id, name: trimmedName.isEmpty ? trimmedHost : trimmedName, host: trimmedHost, username: username.trimmingCharacters(in: .whitespacesAndNewlines), port: port, credentialID: credentialID, tags: normalizedTags(tags), connectionType: .rdp, domain: normalizedRDPDomain(domain))
        if let index = rootConnections.firstIndex(where: { $0.id == updated.id }) {
            rootConnections[index] = updated
        } else if !updateConnection(updated, in: &folders) {
            errorMessage = "The RDP connection is no longer available."
            return
        }
        synchronizeWorkspace()
        self.editingRDPConnection = nil
        isShowingRDPConnectionEditor = false
        save()
    }

    func cancelRDPConnectionEditor() {
        editingRDPConnection = nil
        isShowingRDPConnectionEditor = false
    }

    func updateSSHConnection(name: String, host: String, username: String, port: Int, credentialID: UUID?, tags: [String], localTunnel: SSHLocalTunnel?) {
        guard let editingSSHConnection,
              !isProcessing,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...65_535).contains(port),
              isValid(localTunnel: localTunnel) else { return }

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = SSHConnection(
            id: editingSSHConnection.id,
            name: trimmedName.isEmpty ? trimmedHost : trimmedName,
            host: trimmedHost,
            username: trimmedUsername,
            port: port,
            credentialID: credentialID,
            tags: normalizedTags(tags),
            localTunnel: localTunnel
        )

        if let index = rootConnections.firstIndex(where: { $0.id == updated.id }) {
            rootConnections[index] = updated
        } else if !updateConnection(updated, in: &folders) {
            errorMessage = "The connection is no longer available."
            return
        }

        synchronizeWorkspace()
        if selectedSSHConnection?.id == updated.id {
            selectedSSHConnection = updated
        }
        self.editingSSHConnection = nil
        isShowingSSHConnectionEditor = false
        save()
    }

    func cancelSSHConnectionEditor() {
        editingSSHConnection = nil
        isShowingSSHConnectionEditor = false
    }

    func selectSSHConnection(_ connection: SSHConnection) {
        isShowingCredentials = false
        selectedWebLink = nil
        activeExternalWebLink = nil
        selectedTreeItemID = connection.id
        selectedTreeItemIDs = [connection.id]
        UserDefaults.standard.set(connection.id.uuidString, forKey: "GateTree.lastSelectedTreeItemID")
        let host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let inheritedCredential = effectiveCredential(for: connection)
        let entry = inheritedCredential.flatMap(keepassEntry(for:))
        let username = connection.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (entry?.username ?? inheritedCredential?.username ?? "")
            : connection.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            errorMessage = "This SSH connection has no host or IP address."
            return
        }
        if username.isEmpty {
            pendingSSHConnection = connection
            promptedSSHUsername = ""
            isShowingSSHUsernamePrompt = true
        } else {
            let sessionConnection = SSHConnection(
                id: connection.id,
                name: connection.name,
                host: connection.host,
                username: username,
                port: connection.port,
                credentialID: connection.credentialID,
                tags: connection.tags,
                localTunnel: connection.localTunnel
            )
            activateSSHConnection(sessionConnection, password: entry?.password)
        }
    }

    func connectWithPromptedSSHUsername() {
        let username = promptedSSHUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pendingSSHConnection else { return }
        let sessionConnection = SSHConnection(
            id: pendingSSHConnection.id,
            name: pendingSSHConnection.name,
            host: pendingSSHConnection.host,
            username: username,
            port: pendingSSHConnection.port,
            credentialID: pendingSSHConnection.credentialID,
            tags: pendingSSHConnection.tags,
            localTunnel: pendingSSHConnection.localTunnel
        )
        activateSSHConnection(sessionConnection, password: effectiveCredential(for: pendingSSHConnection).flatMap(keepassEntry(for:))?.password)
        self.pendingSSHConnection = nil
        isShowingSSHUsernamePrompt = false
    }

    func cancelSSHUsernamePrompt() {
        pendingSSHConnection = nil
        promptedSSHUsername = ""
        isShowingSSHUsernamePrompt = false
    }

    func closeSSHConnection() {
        guard let selectedSSHConnection else { return }
        closeSSHConnection(selectedSSHConnection.id)
    }

    func closeSSHConnection(_ id: UUID) {
        let wasActive = activeSessionProtocol == .ssh && activeSessionID == id
        let wasSelected = selectedSSHConnection?.id == id
        openSSHConnections.removeAll { $0.id == id }
        sshPasswordsByConnectionID[id] = nil
        if wasSelected {
            selectedSSHConnection = openSSHConnections.last
            selectedSSHPassword = selectedSSHConnection.flatMap { sshPasswordsByConnectionID[$0.id] }
        }
        if wasActive {
            activateNextOpenPane()
        }
    }

    func closeRDPConnection(_ id: UUID) {
        let wasActive = activeSessionProtocol == .rdp && activeSessionID == id
        let wasSelected = selectedRDPConnection?.id == id
        openRDPConnections.removeAll { $0.id == id }
        rdpPasswordsByConnectionID[id] = nil
        if wasSelected {
            selectedRDPConnection = openRDPConnections.last
        }
        if wasActive {
            activateNextOpenPane()
        }
    }

    /// Restores a visible pane after the active SSH or RDP tab closes.
    /// Web links live in Chrome, but retain an in-app status pane so the
    /// workspace must also reactivate one of those when it is the only type
    /// of open tab left.
    private func activateNextOpenPane() {
        if let ssh = openSSHConnections.last {
            selectedSSHConnection = ssh
            selectedSSHPassword = sshPasswordsByConnectionID[ssh.id]
            activeSessionID = ssh.id
            activeSessionProtocol = .ssh
            activeExternalWebLink = nil
        } else if let rdp = openRDPConnections.last {
            selectedRDPConnection = rdp
            activeSessionID = rdp.id
            activeSessionProtocol = .rdp
            activeExternalWebLink = nil
        } else if let webLink = openExternalWebLinks.last {
            activeExternalWebLink = webLink
            activeSessionID = nil
            activeSessionProtocol = nil
        } else {
            activeSessionID = nil
            activeSessionProtocol = nil
            activeExternalWebLink = nil
        }
    }

    func selectOpenRDPConnection(_ connection: SSHConnection) {
        guard openRDPConnections.contains(where: { $0.id == connection.id }) else { return }
        selectedRDPConnection = connection
        activeSessionID = connection.id
        activeSessionProtocol = .rdp
        selectedWebLink = nil
        activeExternalWebLink = nil
    }

    func rdpPassword(for connection: SSHConnection) -> String? {
        rdpPasswordsByConnectionID[connection.id]
    }

    func selectOpenSSHConnection(_ connection: SSHConnection) {
        guard openSSHConnections.contains(where: { $0.id == connection.id }) else { return }
        selectedSSHConnection = connection
        selectedSSHPassword = sshPasswordsByConnectionID[connection.id]
        activeSessionID = connection.id
        activeSessionProtocol = .ssh
        selectedWebLink = nil
        activeExternalWebLink = nil
    }

    func password(for connection: SSHConnection) -> String? {
        sshPasswordsByConnectionID[connection.id]
    }

    private func activateSSHConnection(_ connection: SSHConnection, password: String?) {
        if let index = openSSHConnections.firstIndex(where: { $0.id == connection.id }) {
            openSSHConnections[index] = connection
        } else {
            openSSHConnections.append(connection)
        }
        sshPasswordsByConnectionID[connection.id] = password
        selectedSSHConnection = connection
        selectedSSHPassword = password
        activeSessionID = connection.id
        activeSessionProtocol = .ssh
    }

    private func isValid(localTunnel: SSHLocalTunnel?) -> Bool {
        guard let localTunnel else { return true }
        guard (1...65_535).contains(localTunnel.localPort),
              (1...65_535).contains(localTunnel.remotePort),
              !localTunnel.remoteHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter a valid local tunnel port and destination."
            return false
        }
        return true
    }

    private func activateRDPConnection(_ connection: SSHConnection, password: String?) {
        if let index = openRDPConnections.firstIndex(where: { $0.id == connection.id }) {
            openRDPConnections[index] = connection
        } else {
            openRDPConnections.append(connection)
        }
        rdpPasswordsByConnectionID[connection.id] = password
        selectedRDPConnection = connection
        activeSessionID = connection.id
        activeSessionProtocol = .rdp
        selectedWebLink = nil
        activeExternalWebLink = nil
    }

    func selectWebLink(_ webLink: WebLink) {
        selectedTreeItemID = webLink.id
        selectedTreeItemIDs = [webLink.id]
        UserDefaults.standard.set(webLink.id.uuidString, forKey: "GateTree.lastSelectedTreeItemID")
        selectedSSHConnection = nil
        selectedSSHPassword = nil
        isShowingCredentials = false
        selectedWebLink = nil
        activeExternalWebLink = webLink
        if !openExternalWebLinks.contains(where: { $0.id == webLink.id }) {
            openExternalWebLinks.append(webLink)
        }

        // A double-click can deliver its second event only after Chrome has
        // started, so a time-based debounce is not reliable here. Keep this
        // bookmark locked until the initial open has settled instead.
        guard !webLinksBeingOpened.contains(webLink.id) else {
            return
        }
        webLinksBeingOpened.insert(webLink.id)
        activateChromeTab(for: webLink)
        releaseWebLinkOpenLock(for: webLink.id)
    }

    func openWebLinkInChrome(_ webLink: WebLink) {
        guard let url = URL(string: webLink.url) else {
            errorMessage = "This web bookmark has an invalid URL."
            return
        }

        // Let Launch Services perform the open exactly once. AppleScript can
        // report an error after creating a Chrome tab, causing a fallback open
        // to create a duplicate tab.
        openURLInChrome(url)
    }

    func activateChromeTab(for webLink: WebLink) {
        // Avoid AppleScript launching Chrome, which would create Chrome's
        // default tab and then a second tab for this bookmark.
        guard isChromeRunning else {
            openWebLinkInChrome(webLink)
            return
        }

        let tabMatch = chromeTabMatch(for: webLink.url)
        let escapedURL = tabMatch.url
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let knownTabID = chromeTabIDsByWebLinkID[webLink.id] ?? -1
        let matchesAnyPathAtTargetHost = tabMatch.matchesAnyPathAtTargetHost ? "true" : "false"
        let scriptSource = """
        tell application "Google Chrome"
            set targetURL to "\(escapedURL)"
            set targetTabID to \(knownTabID)
            set matchesAnyPathAtTargetHost to \(matchesAnyPathAtTargetHost)
            repeat with browserWindow in windows
                set tabIndex to 0
                repeat with browserTab in tabs of browserWindow
                    set tabIndex to tabIndex + 1
                    if id of browserTab is targetTabID or URL of browserTab is targetURL or (matchesAnyPathAtTargetHost and URL of browserTab starts with targetURL) then
                        set active tab index of browserWindow to tabIndex
                        set index of browserWindow to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
            return false
        end tell
        """

        var scriptError: NSDictionary?
        let result = NSAppleScript(source: scriptSource)?.executeAndReturnError(&scriptError)
        if scriptError == nil, result?.booleanValue == true {
            return
        }

        openWebLinkInChrome(webLink)
    }

    private var isChromeRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty
    }

    private func chromeTabMatch(for urlString: String) -> (url: String, matchesAnyPathAtTargetHost: Bool) {
        guard var components = URLComponents(string: urlString),
              components.path.isEmpty || components.path == "/" else {
            return (urlString, false)
        }

        components.path = "/"
        return (components.url?.absoluteString ?? urlString, true)
    }

    private func openURLInChrome(_ url: URL) {
        if let chromeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: chromeURL,
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil
            )
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func releaseWebLinkOpenLock(for webLinkID: UUID) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.webLinksBeingOpened.remove(webLinkID)
        }
    }

    func focusChrome() {
        if let activeExternalWebLink {
            activateChromeTab(for: activeExternalWebLink)
            return
        }

        if let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first {
            chrome.activate(options: [.activateIgnoringOtherApps])
        } else if let chromeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            NSWorkspace.shared.openApplication(at: chromeURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func closeExternalWebLink() {
        guard let activeExternalWebLink else { return }
        closeExternalWebLink(activeExternalWebLink.id)
    }

    func closeExternalWebLink(_ id: UUID) {
        openExternalWebLinks.removeAll { $0.id == id }
        guard activeExternalWebLink?.id == id else { return }
        activeExternalWebLink = openExternalWebLinks.last
    }

    func selectOpenExternalWebLink(_ webLink: WebLink) {
        guard openExternalWebLinks.contains(where: { $0.id == webLink.id }) else { return }
        activeExternalWebLink = webLink
        selectedSSHConnection = nil
        selectedSSHPassword = nil
        activateChromeTab(for: webLink)
    }

    func selectTreeItem(_ id: UUID) {
        if NSEvent.modifierFlags.contains(.command) {
            if selectedTreeItemIDs.contains(id) {
                selectedTreeItemIDs.remove(id)
            } else {
                selectedTreeItemIDs.insert(id)
            }
        } else {
            selectedTreeItemIDs = [id]
        }
        selectedTreeItemID = selectedTreeItemIDs.first
        UserDefaults.standard.set(selectedTreeItemID?.uuidString, forKey: "GateTree.lastSelectedTreeItemID")
    }

    func selectOnlyTreeItem(_ id: UUID) {
        selectedTreeItemIDs = [id]
        selectedTreeItemID = id
        UserDefaults.standard.set(id.uuidString, forKey: "GateTree.lastSelectedTreeItemID")
    }

    func isFolderExpanded(_ id: UUID) -> Bool {
        expandedFolderIDs.contains(id)
    }

    func toggleFolderExpanded(_ id: UUID) {
        if expandedFolderIDs.contains(id) {
            expandedFolderIDs.remove(id)
        } else {
            expandedFolderIDs.insert(id)
        }
        UserDefaults.standard.set(expandedFolderIDs.map(\.uuidString), forKey: "GateTree.expandedFolderIDs")
    }

    var hasTreeSelection: Bool { !selectedTreeItemIDs.isEmpty }
    var hasAssignableTreeSelection: Bool { hasTreeSelection }

    func showCredentialAssignment() {
        guard hasAssignableTreeSelection, !isProcessing else { return }
        selectedCredentialAssignmentID = nil
        isShowingCredentialAssignment = true
    }

    func applyCredentialAssignment() {
        guard !isProcessing else { return }
        let ids = selectedTreeItemIDs
        applyCredential(selectedCredentialAssignmentID, to: ids, in: &folders)
        for index in rootConnections.indices where ids.contains(rootConnections[index].id) {
            rootConnections[index].credentialID = selectedCredentialAssignmentID
        }
        synchronizeWorkspace()
        isShowingCredentialAssignment = false
        save()
    }

    func showSSHConnectionDeletionConfirmation(_ connection: SSHConnection) {
        guard !isProcessing else { return }
        deletingSSHConnectionID = connection.id
        isShowingSSHConnectionDeletionConfirmation = true
    }

    func deleteConfirmedSSHConnection() {
        guard let deletingSSHConnectionID, !isProcessing else { return }

        if let index = rootConnections.firstIndex(where: { $0.id == deletingSSHConnectionID }) {
            rootConnections.remove(at: index)
        } else if removeConnection(deletingSSHConnectionID, from: &folders) == nil {
            errorMessage = "The connection is no longer available."
            return
        }

        if selectedSSHConnection?.id == deletingSSHConnectionID {
            selectedSSHConnection = nil
        }

        synchronizeWorkspace()
        self.deletingSSHConnectionID = nil
        isShowingSSHConnectionDeletionConfirmation = false
        save()
    }

    func createFolder(named name: String, tags: [String]) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let folder = WorkspaceFolder(name: trimmedName, tags: normalizedTags(tags))
        if let folderParentID, !insert(folder, into: &folders, below: folderParentID) {
            errorMessage = "The parent folder is no longer available."
            return
        } else if let folderParentID {
            // Keep the destination visible after the context-menu action. A
            // context click can otherwise also reach the row's tap handler.
            expandedFolderIDs.insert(folderParentID)
            UserDefaults.standard.set(expandedFolderIDs.map(\.uuidString), forKey: "GateTree.expandedFolderIDs")
        } else if folderParentID == nil {
            folders.append(folder)
        }

        synchronizeWorkspace()
        self.folderParentID = nil
        isShowingFolderCreation = false
        save()
    }

    func cancelFolderCreation() {
        folderParentID = nil
        isShowingFolderCreation = false
    }

    func showFolderEditor(_ folder: WorkspaceFolder) {
        guard !isProcessing else { return }
        editingFolderID = folder.id
        editingFolderName = folder.name
        editingFolderCredentialID = folder.credentialID
        editingFolderTags = folder.tags.joined(separator: ", ")
        isShowingFolderEditor = true
    }

    func renameEditedFolder() {
        let trimmedName = editingFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let editingFolderID, !trimmedName.isEmpty, !isProcessing else { return }
        guard updateFolder(editingFolderID, name: trimmedName, credentialID: editingFolderCredentialID, tags: normalizedTags(editingFolderTags.split(separator: ",").map(String.init)), in: &folders) else { return }

        synchronizeWorkspace()
        self.editingFolderID = nil
        self.editingFolderCredentialID = nil
        self.editingFolderTags = ""
        isShowingFolderEditor = false
        save()
    }

    func cancelFolderEditor() {
        editingFolderID = nil
        editingFolderCredentialID = nil
        editingFolderTags = ""
        isShowingFolderEditor = false
    }

    func showFolderDeletionConfirmation(_ folder: WorkspaceFolder) {
        guard folder.children.isEmpty, folder.connections.isEmpty, folder.webLinks.isEmpty, folder.terminalCommands.isEmpty, !isProcessing else { return }
        deletingFolderID = folder.id
        isShowingFolderDeletionConfirmation = true
    }

    func deleteConfirmedFolder() {
        guard let deletingFolderID, !isProcessing else { return }
        guard let folder = findFolder(deletingFolderID, in: folders), folder.children.isEmpty, folder.connections.isEmpty, folder.webLinks.isEmpty, folder.terminalCommands.isEmpty else {
            errorMessage = "Only empty folders can be deleted."
            return
        }
        guard removeFolder(deletingFolderID, from: &folders) != nil else { return }

        synchronizeWorkspace()
        self.deletingFolderID = nil
        isShowingFolderDeletionConfirmation = false
        save()
    }

    func isTrashFolder(_ folder: WorkspaceFolder) -> Bool {
        folders.contains { $0.id == folder.id && $0.name == "Trash" }
    }

    func showEmptyTrashConfirmation(_ folder: WorkspaceFolder) {
        guard isTrashFolder(folder),
              (!folder.children.isEmpty || !folder.connections.isEmpty || !folder.webLinks.isEmpty || !folder.terminalCommands.isEmpty),
              !isProcessing else { return }
        isShowingEmptyTrashConfirmation = true
    }

    func emptyTrash() {
        guard let trashIndex = folders.firstIndex(where: { $0.name == "Trash" }), !isProcessing else { return }

        let removedWebLinkIDs = Set(
            folders[trashIndex].webLinks.map(\.id) + allWebLinks(in: folders[trashIndex].children).map(\.id)
        )
        quickAccessWebLinkIDs.removeAll { removedWebLinkIDs.contains($0) }
        folders[trashIndex].children.removeAll()
        folders[trashIndex].connections.removeAll()
        folders[trashIndex].webLinks.removeAll()
        folders[trashIndex].terminalCommands.removeAll()

        synchronizeWorkspace()
        isShowingEmptyTrashConfirmation = false
        save()
    }

    func moveFolder(id: UUID, into parentID: UUID?) {
        guard id != parentID,
              let movingFolder = findFolder(id, in: folders),
              !containsFolder(parentID, inside: movingFolder),
              !isProcessing else { return }

        var updatedFolders = folders
        guard let removedFolder = removeFolder(id, from: &updatedFolders) else { return }

        if let parentID {
            guard insert(removedFolder, into: &updatedFolders, below: parentID) else { return }
        } else {
            updatedFolders.append(removedFolder)
        }

        folders = updatedFolders
        synchronizeWorkspace()
        save()
    }

    func moveSSHConnection(id: UUID, into parentID: UUID?) {
        guard !isProcessing else { return }

        var updatedFolders = folders
        var updatedRootConnections = rootConnections
        let connection: SSHConnection?

        if let rootIndex = updatedRootConnections.firstIndex(where: { $0.id == id }) {
            connection = updatedRootConnections.remove(at: rootIndex)
        } else {
            connection = removeConnection(id, from: &updatedFolders)
        }

        guard let connection else { return }

        if let parentID {
            guard insert(connection, into: &updatedFolders, below: parentID) else { return }
        } else {
            updatedRootConnections.append(connection)
        }

        folders = updatedFolders
        rootConnections = updatedRootConnections
        synchronizeWorkspace()
        save()
    }

    func moveSSHConnectionToTrash(_ id: UUID) {
        moveSSHConnection(id: id, into: trashFolderID())
    }

    func moveWebLink(id: UUID, into parentID: UUID?) {
        guard !isProcessing else { return }

        var updatedFolders = folders
        var updatedRootWebLinks = rootWebLinks
        let webLink: WebLink?

        if let rootIndex = updatedRootWebLinks.firstIndex(where: { $0.id == id }) {
            webLink = updatedRootWebLinks.remove(at: rootIndex)
        } else {
            webLink = removeWebLink(id, from: &updatedFolders)
        }

        guard let webLink else { return }
        if let parentID {
            guard insert(webLink, into: &updatedFolders, below: parentID) else { return }
        } else {
            updatedRootWebLinks.append(webLink)
        }

        folders = updatedFolders
        rootWebLinks = updatedRootWebLinks
        synchronizeWorkspace()
        save()
    }

    func moveWebLinkToTrash(_ id: UUID) {
        quickAccessWebLinkIDs.removeAll { $0 == id }
        moveWebLink(id: id, into: trashFolderID())
    }

    var quickAccessWebLinks: [WebLink] {
        let webLinks = allWebLinks(in: folders) + rootWebLinks
        let linksByID = Dictionary(uniqueKeysWithValues: webLinks.map { ($0.id, $0) })
        return quickAccessWebLinkIDs.compactMap { linksByID[$0] }
    }

    func isQuickAccess(_ webLink: WebLink) -> Bool {
        quickAccessWebLinkIDs.contains(webLink.id)
    }

    func toggleQuickAccess(_ webLink: WebLink) {
        if let index = quickAccessWebLinkIDs.firstIndex(of: webLink.id) {
            quickAccessWebLinkIDs.remove(at: index)
        } else {
            quickAccessWebLinkIDs.append(webLink.id)
        }
        synchronizeWorkspace()
        save()
    }

    func reorderQuickAccess(movedID: UUID, before targetID: UUID?) {
        guard !isProcessing,
              quickAccessWebLinkIDs.contains(movedID),
              targetID != movedID else { return }

        var reorderedIDs = quickAccessWebLinkIDs
        reorderedIDs.removeAll { $0 == movedID }
        if let targetID, let targetIndex = reorderedIDs.firstIndex(of: targetID) {
            reorderedIDs.insert(movedID, at: targetIndex)
        } else {
            reorderedIDs.append(movedID)
        }
        guard reorderedIDs != quickAccessWebLinkIDs else { return }
        quickAccessWebLinkIDs = reorderedIDs
        synchronizeWorkspace()
        save()
    }

    func moveTerminalCommand(id: UUID, into parentID: UUID?) {
        guard !isProcessing else { return }

        var updatedFolders = folders
        var updatedRootTerminalCommands = rootTerminalCommands
        let terminalCommand: TerminalCommand?

        if let rootIndex = updatedRootTerminalCommands.firstIndex(where: { $0.id == id }) {
            terminalCommand = updatedRootTerminalCommands.remove(at: rootIndex)
        } else {
            terminalCommand = removeTerminalCommand(id, from: &updatedFolders)
        }

        guard let terminalCommand else { return }
        if let parentID {
            guard insert(terminalCommand, into: &updatedFolders, below: parentID) else { return }
        } else {
            updatedRootTerminalCommands.append(terminalCommand)
        }

        folders = updatedFolders
        rootTerminalCommands = updatedRootTerminalCommands
        synchronizeWorkspace()
        save()
    }

    func moveTerminalCommandToTrash(_ id: UUID) {
        moveTerminalCommand(id: id, into: trashFolderID())
    }

    private func trashFolderID() -> UUID {
        if let existing = folders.first(where: { $0.name == "Trash" }) {
            return existing.id
        }
        let trash = WorkspaceFolder(name: "Trash")
        folders.append(trash)
        return trash.id
    }

    private func synchronizeWorkspace() {
        workspace = Workspace(
            formatVersion: workspace.formatVersion,
            createdAt: workspace.createdAt,
            folders: folders,
            rootConnections: rootConnections,
            rootWebLinks: rootWebLinks,
            rootTerminalCommands: rootTerminalCommands,
            credentials: credentials,
            quickAccessWebLinkIDs: quickAccessWebLinkIDs
        )
    }

    private func insert(_ folder: WorkspaceFolder, into folders: inout [WorkspaceFolder], below parentID: UUID) -> Bool {
        for index in folders.indices {
            if folders[index].id == parentID {
                folders[index].children.append(folder)
                return true
            }
            if insert(folder, into: &folders[index].children, below: parentID) {
                return true
            }
        }
        return false
    }

    private func insert(_ connection: SSHConnection, into folders: inout [WorkspaceFolder], below parentID: UUID) -> Bool {
        for index in folders.indices {
            if folders[index].id == parentID {
                folders[index].connections.append(connection)
                return true
            }
            if insert(connection, into: &folders[index].children, below: parentID) {
                return true
            }
        }
        return false
    }

    private func insert(_ webLink: WebLink, into folders: inout [WorkspaceFolder], below parentID: UUID) -> Bool {
        for index in folders.indices {
            if folders[index].id == parentID {
                folders[index].webLinks.append(webLink)
                return true
            }
            if insert(webLink, into: &folders[index].children, below: parentID) {
                return true
            }
        }
        return false
    }

    private func insert(_ terminalCommand: TerminalCommand, into folders: inout [WorkspaceFolder], below parentID: UUID) -> Bool {
        for index in folders.indices {
            if folders[index].id == parentID {
                folders[index].terminalCommands.append(terminalCommand)
                return true
            }
            if insert(terminalCommand, into: &folders[index].children, below: parentID) { return true }
        }
        return false
    }

    private func findFolder(_ id: UUID, in folders: [WorkspaceFolder]) -> WorkspaceFolder? {
        for folder in folders {
            if folder.id == id { return folder }
            if let match = findFolder(id, in: folder.children) { return match }
        }
        return nil
    }

    private func containsFolder(_ id: UUID?, inside folder: WorkspaceFolder) -> Bool {
        guard let id else { return false }
        return folder.children.contains { child in
            child.id == id || containsFolder(id, inside: child)
        }
    }

    private func removeFolder(_ id: UUID, from folders: inout [WorkspaceFolder]) -> WorkspaceFolder? {
        for index in folders.indices {
            if folders[index].id == id {
                return folders.remove(at: index)
            }
            if let removed = removeFolder(id, from: &folders[index].children) {
                return removed
            }
        }
        return nil
    }

    private func updateFolder(_ id: UUID, name: String, credentialID: UUID?, tags: [String], in folders: inout [WorkspaceFolder]) -> Bool {
        for index in folders.indices {
            if folders[index].id == id {
                folders[index].name = name
                folders[index].credentialID = credentialID
                folders[index].tags = tags
                return true
            }
            if updateFolder(id, name: name, credentialID: credentialID, tags: tags, in: &folders[index].children) {
                return true
            }
        }
        return false
    }

    private func updateConnection(_ connection: SSHConnection, in folders: inout [WorkspaceFolder]) -> Bool {
        for index in folders.indices {
            if let connectionIndex = folders[index].connections.firstIndex(where: { $0.id == connection.id }) {
                folders[index].connections[connectionIndex] = connection
                return true
            }
            if updateConnection(connection, in: &folders[index].children) { return true }
        }
        return false
    }

    private func updateWebLink(_ webLink: WebLink, in folders: inout [WorkspaceFolder]) -> Bool {
        for index in folders.indices {
            if let webLinkIndex = folders[index].webLinks.firstIndex(where: { $0.id == webLink.id }) {
                folders[index].webLinks[webLinkIndex] = webLink
                return true
            }
            if updateWebLink(webLink, in: &folders[index].children) { return true }
        }
        return false
    }

    private func updateTerminalCommand(_ terminalCommand: TerminalCommand, in folders: inout [WorkspaceFolder]) -> Bool {
        for index in folders.indices {
            if let commandIndex = folders[index].terminalCommands.firstIndex(where: { $0.id == terminalCommand.id }) {
                folders[index].terminalCommands[commandIndex] = terminalCommand
                return true
            }
            if updateTerminalCommand(terminalCommand, in: &folders[index].children) { return true }
        }
        return false
    }

    private func applyCredential(_ credentialID: UUID?, to ids: Set<UUID>, in folders: inout [WorkspaceFolder]) {
        for index in folders.indices {
            if ids.contains(folders[index].id) {
                folders[index].credentialID = credentialID
            }
            for connectionIndex in folders[index].connections.indices where ids.contains(folders[index].connections[connectionIndex].id) {
                folders[index].connections[connectionIndex].credentialID = credentialID
            }
            applyCredential(credentialID, to: ids, in: &folders[index].children)
        }
    }

    private func effectiveCredential(for connection: SSHConnection) -> Credential? {
        let credentialID = connection.credentialID ?? inheritedCredentialID(
            forConnectionID: connection.id,
            in: folders,
            inherited: nil
        )
        guard let credentialID else { return nil }
        return credentials.first { $0.id == credentialID }
    }

    private func keepassEntry(for credential: Credential) -> KeePassXCEntry? {
        let databasePath = credential.keepassDatabasePath
        let entryPath = credential.keepassEntryPath
        guard !databasePath.isEmpty, !entryPath.isEmpty else {
            errorMessage = "Credential \(credential.name) has no KeePassXC database or entry path."
            return nil
        }
        let password: String
        if let cached = keepassMasterPasswords[databasePath] {
            password = cached
        } else {
            guard let entered = promptForKeePassMasterPassword(databasePath: databasePath) else { return nil }
            password = entered
            keepassMasterPasswords[databasePath] = password
        }
        let databaseURL = URL(fileURLWithPath: databasePath)
        let securityScopedURL = securityScopedDatabaseURL(for: databaseURL, bookmark: credential.keepassDatabaseBookmark)
        defer {
            securityScopedURL?.stopAccessingSecurityScopedResource()
        }
        if credential.keepassDatabaseBookmark != nil && securityScopedURL == nil {
            errorMessage = "GateTree no longer has permission to read \(databaseURL.lastPathComponent). Edit the credential and choose the KeePass database again."
            return nil
        }
        if credential.keepassDatabaseBookmark == nil && !FileManager.default.isReadableFile(atPath: databaseURL.path) {
            errorMessage = "GateTree needs permission to read \(databaseURL.lastPathComponent). Edit the credential and choose the KeePass database again."
            return nil
        }
        do {
            return try KeePassXCProvider.readEntry(
                databaseURL: securityScopedURL ?? databaseURL,
                entryPath: entryPath,
                masterPassword: password
            )
        } catch {
            keepassMasterPasswords[databasePath] = nil
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func securityScopedDatabaseURL(for url: URL, bookmark: Data?) -> URL? {
        guard let bookmark else { return nil }
        var isStale = false
        guard let bookmarkedURL = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), bookmarkedURL.standardizedFileURL == url.standardizedFileURL else {
            return nil
        }
        return bookmarkedURL.startAccessingSecurityScopedResource() ? bookmarkedURL : nil
    }

    private func promptForKeePassMasterPassword(databasePath: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Unlock KeePassXC"
        alert.informativeText = "Enter the master password for \((databasePath as NSString).lastPathComponent). It is kept only for this GateTree session."
        alert.addButton(withTitle: "Unlock")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "KeePassXC master password"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let password = field.stringValue
        return password.isEmpty ? nil : password
    }

    func isCredentialInUse(_ credentialID: UUID) -> Bool {
        rootConnections.contains { $0.credentialID == credentialID } || credentialIsAssigned(credentialID, in: folders)
    }

    func credentialSummary(for folder: WorkspaceFolder) -> String {
        if let credentialID = folder.credentialID, let credential = credentials.first(where: { $0.id == credentialID }) {
            return "Credential: \(credential.name)"
        }
        if let credential = inheritedCredential(forFolderID: folder.id, in: folders, inherited: nil) {
            return "Inherit: \(credential.name)"
        }
        return "Credential: Empty"
    }

    func credentialSummary(for connection: SSHConnection) -> String {
        if let credentialID = connection.credentialID, let credential = credentials.first(where: { $0.id == credentialID }) {
            return "Credential: \(credential.name)"
        }
        if let credential = effectiveCredential(for: connection) {
            return "Inherit: \(credential.name)"
        }
        return "Credential: Empty"
    }

    var selectedConnectionForInspector: SSHConnection? {
        guard let selectedTreeItemID else { return nil }
        if let connection = rootConnections.first(where: { $0.id == selectedTreeItemID }) {
            return connection
        }
        return findConnection(selectedTreeItemID, in: folders)
    }

    var selectedFolderForInspector: WorkspaceFolder? {
        guard let selectedTreeItemID else { return nil }
        return findFolder(selectedTreeItemID, in: folders)
    }

    var selectedWebLinkForInspector: WebLink? {
        guard let selectedTreeItemID else { return nil }
        if let webLink = rootWebLinks.first(where: { $0.id == selectedTreeItemID }) {
            return webLink
        }
        return findWebLink(selectedTreeItemID, in: folders)
    }

    var selectedTerminalCommandForInspector: TerminalCommand? {
        guard let selectedTreeItemID else { return nil }
        if let terminalCommand = rootTerminalCommands.first(where: { $0.id == selectedTreeItemID }) {
            return terminalCommand
        }
        return findTerminalCommand(selectedTreeItemID, in: folders)
    }

    var editingFolderCredentialSummary: String {
        guard let editingFolderID, let folder = findFolder(editingFolderID, in: folders) else {
            return "Credential: Empty"
        }
        return credentialSummary(for: folder)
    }

    func resolvedUsername(for connection: SSHConnection) -> String {
        let username = connection.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !username.isEmpty { return username }
        return effectiveCredential(for: connection)?.username ?? "—"
    }

    private func credentialIsAssigned(_ credentialID: UUID, in folders: [WorkspaceFolder]) -> Bool {
        folders.contains { folder in
            folder.credentialID == credentialID ||
            folder.connections.contains(where: { $0.credentialID == credentialID }) ||
            credentialIsAssigned(credentialID, in: folder.children)
        }
    }

    private func inheritedCredentialID(
        forConnectionID connectionID: UUID,
        in folders: [WorkspaceFolder],
        inherited: UUID?
    ) -> UUID? {
        for folder in folders {
            let credentialID = folder.credentialID ?? inherited
            if folder.connections.contains(where: { $0.id == connectionID }) {
                return credentialID
            }
            if let match = inheritedCredentialID(
                forConnectionID: connectionID,
                in: folder.children,
                inherited: credentialID
            ) {
                return match
            }
        }
        return nil
    }

    private func findConnection(_ id: UUID, in folders: [WorkspaceFolder]) -> SSHConnection? {
        for folder in folders {
            if let connection = folder.connections.first(where: { $0.id == id }) {
                return connection
            }
            if let connection = findConnection(id, in: folder.children) { return connection }
        }
        return nil
    }

    private func findWebLink(_ id: UUID, in folders: [WorkspaceFolder]) -> WebLink? {
        for folder in folders {
            if let webLink = folder.webLinks.first(where: { $0.id == id }) {
                return webLink
            }
            if let webLink = findWebLink(id, in: folder.children) { return webLink }
        }
        return nil
    }

    private func findTerminalCommand(_ id: UUID, in folders: [WorkspaceFolder]) -> TerminalCommand? {
        for folder in folders {
            if let terminalCommand = folder.terminalCommands.first(where: { $0.id == id }) {
                return terminalCommand
            }
            if let terminalCommand = findTerminalCommand(id, in: folder.children) { return terminalCommand }
        }
        return nil
    }

    private func inheritedCredential(forFolderID folderID: UUID, in folders: [WorkspaceFolder], inherited: UUID?) -> Credential? {
        for folder in folders {
            let credentialID = folder.credentialID ?? inherited
            if folder.id == folderID {
                guard let credentialID else { return nil }
                return credentials.first { $0.id == credentialID }
            }
            if let match = inheritedCredential(forFolderID: folderID, in: folder.children, inherited: credentialID) {
                return match
            }
        }
        return nil
    }

    private func removeConnection(_ id: UUID, from folders: inout [WorkspaceFolder]) -> SSHConnection? {
        for index in folders.indices {
            if let connectionIndex = folders[index].connections.firstIndex(where: { $0.id == id }) {
                return folders[index].connections.remove(at: connectionIndex)
            }
            if let connection = removeConnection(id, from: &folders[index].children) { return connection }
        }
        return nil
    }

    private func removeWebLink(_ id: UUID, from folders: inout [WorkspaceFolder]) -> WebLink? {
        for index in folders.indices {
            if let webLinkIndex = folders[index].webLinks.firstIndex(where: { $0.id == id }) {
                return folders[index].webLinks.remove(at: webLinkIndex)
            }
            if let webLink = removeWebLink(id, from: &folders[index].children) { return webLink }
        }
        return nil
    }

    private func allWebLinks(in folders: [WorkspaceFolder]) -> [WebLink] {
        folders.flatMap { folder in
            folder.webLinks + allWebLinks(in: folder.children)
        }
    }

    private func removeTerminalCommand(_ id: UUID, from folders: inout [WorkspaceFolder]) -> TerminalCommand? {
        for index in folders.indices {
            if let commandIndex = folders[index].terminalCommands.firstIndex(where: { $0.id == id }) {
                return folders[index].terminalCommands.remove(at: commandIndex)
            }
            if let command = removeTerminalCommand(id, from: &folders[index].children) { return command }
        }
        return nil
    }
}

enum WorkspaceStorageMode {
    case encrypted
    case plaintext
}

func normalizedTags(_ tags: [String]) -> [String] {
    var seen = Set<String>()
    return tags.compactMap { tag in
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let key = normalized.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return seen.insert(key).inserted ? normalized : nil
    }
}

struct WorkspaceFolder: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var children: [WorkspaceFolder]
    var connections: [SSHConnection]
    var webLinks: [WebLink]
    var terminalCommands: [TerminalCommand]
    var credentialID: UUID?
    var tags: [String]

    init(id: UUID = UUID(), name: String, children: [WorkspaceFolder] = [], connections: [SSHConnection] = [], webLinks: [WebLink] = [], terminalCommands: [TerminalCommand] = [], credentialID: UUID? = nil, tags: [String] = []) {
        self.id = id
        self.name = name
        self.children = children
        self.connections = connections
        self.webLinks = webLinks
        self.terminalCommands = terminalCommands
        self.credentialID = credentialID
        self.tags = tags
    }

    var outlineChildren: [WorkspaceFolder]? {
        children.isEmpty ? nil : children
    }

    enum CodingKeys: String, CodingKey { case id, name, children, connections, webLinks, terminalCommands, credentialID, tags }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        children = try values.decodeIfPresent([WorkspaceFolder].self, forKey: .children) ?? []
        connections = try values.decodeIfPresent([SSHConnection].self, forKey: .connections) ?? []
        webLinks = try values.decodeIfPresent([WebLink].self, forKey: .webLinks) ?? []
        terminalCommands = try values.decodeIfPresent([TerminalCommand].self, forKey: .terminalCommands) ?? []
        credentialID = try values.decodeIfPresent(UUID.self, forKey: .credentialID)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

enum WebLinkIcon: String, Codable, CaseIterable, Identifiable, Sendable {
    case icon1 = "icon_1"
    case icon2 = "icon_2"
    case icon3 = "icon_3"
    case icon4 = "icon_4"
    case icon5 = "icon_5"
    case icon6 = "icon_6"
    case icon7 = "icon_7"
    case icon8 = "icon_8"
    case icon9 = "icon_9"
    case icon10 = "icon_10"
    case icon11 = "icon_11"
    case icon12 = "icon_12"

    var id: String { rawValue }
}

struct WebLink: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var url: String
    var tags: [String]
    var icon: WebLinkIcon

    init(id: UUID = UUID(), name: String, url: String, tags: [String] = [], icon: WebLinkIcon = .icon12) {
        self.id = id
        self.name = name
        self.url = url
        self.tags = tags
        self.icon = icon
    }

    enum CodingKeys: String, CodingKey { case id, name, url, tags, icon }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        url = try values.decode(String.self, forKey: .url)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        icon = try values.decodeIfPresent(WebLinkIcon.self, forKey: .icon) ?? .icon12
    }
}

struct TerminalCommand: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var command: String
    var tags: [String]

    init(id: UUID = UUID(), name: String, command: String, tags: [String] = []) {
        self.id = id
        self.name = name
        self.command = command
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey { case id, name, command, tags }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        command = try values.decode(String.self, forKey: .command)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

enum ConnectionProtocol: String, Codable, Hashable, Sendable {
    case ssh
    case rdp
}

struct SSHConnection: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var host: String
    var username: String
    var port: Int
    var credentialID: UUID?
    var tags: [String]
    var connectionType: ConnectionProtocol
    var domain: String
    var localTunnel: SSHLocalTunnel?

    init(id: UUID = UUID(), name: String, host: String, username: String, port: Int, credentialID: UUID? = nil, tags: [String] = [], connectionType: ConnectionProtocol = .ssh, domain: String = "", localTunnel: SSHLocalTunnel? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.username = username
        self.port = port
        self.credentialID = credentialID
        self.tags = tags
        self.connectionType = connectionType
        self.domain = domain
        self.localTunnel = localTunnel
    }

    enum CodingKeys: String, CodingKey {
        case id, name, host, username, port, credentialID, tags, domain, localTunnel
        case connectionType = "protocol"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        host = try values.decode(String.self, forKey: .host)
        username = try values.decodeIfPresent(String.self, forKey: .username) ?? ""
        port = try values.decode(Int.self, forKey: .port)
        credentialID = try values.decodeIfPresent(UUID.self, forKey: .credentialID)
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        connectionType = try values.decodeIfPresent(ConnectionProtocol.self, forKey: .connectionType) ?? .ssh
        domain = try values.decodeIfPresent(String.self, forKey: .domain) ?? ""
        localTunnel = try values.decodeIfPresent(SSHLocalTunnel.self, forKey: .localTunnel)
    }
}

struct SSHLocalTunnel: Codable, Hashable, Sendable {
    var localPort: Int
    var remoteHost: String
    var remotePort: Int
}

struct Credential: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var username: String
    var keepassDatabasePath: String
    var keepassDatabaseBookmark: Data?
    var keepassEntryPath: String

    init(id: UUID = UUID(), name: String, username: String, keepassDatabasePath: String = "", keepassDatabaseBookmark: Data? = nil, keepassEntryPath: String = "") {
        self.id = id
        self.name = name
        self.username = username
        self.keepassDatabasePath = keepassDatabasePath
        self.keepassDatabaseBookmark = keepassDatabaseBookmark
        self.keepassEntryPath = keepassEntryPath
    }

    enum CodingKeys: String, CodingKey { case id, name, username, keepassDatabasePath, keepassEntryPath, keepassEntryUUID }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        username = try values.decodeIfPresent(String.self, forKey: .username) ?? ""
        keepassDatabasePath = try values.decodeIfPresent(String.self, forKey: .keepassDatabasePath) ?? ""
        keepassEntryPath = try values.decodeIfPresent(String.self, forKey: .keepassEntryPath)
            ?? values.decodeIfPresent(String.self, forKey: .keepassEntryUUID)
            ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(username, forKey: .username)
        try values.encode(keepassDatabasePath, forKey: .keepassDatabasePath)
        try values.encode(keepassEntryPath, forKey: .keepassEntryPath)
    }
}

private struct Workspace: Codable, Sendable {
    let formatVersion: Int
    let createdAt: Date
    let folders: [WorkspaceFolder]
    let rootConnections: [SSHConnection]
    let rootWebLinks: [WebLink]
    let rootTerminalCommands: [TerminalCommand]
    let credentials: [Credential]
    let quickAccessWebLinkIDs: [UUID]

    init(formatVersion: Int = 1, createdAt: Date = .now, folders: [WorkspaceFolder] = [], rootConnections: [SSHConnection] = [], rootWebLinks: [WebLink] = [], rootTerminalCommands: [TerminalCommand] = [], credentials: [Credential] = [], quickAccessWebLinkIDs: [UUID] = []) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.folders = folders
        self.rootConnections = rootConnections
        self.rootWebLinks = rootWebLinks
        self.rootTerminalCommands = rootTerminalCommands
        self.credentials = credentials
        self.quickAccessWebLinkIDs = quickAccessWebLinkIDs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        folders = try values.decodeIfPresent([WorkspaceFolder].self, forKey: .folders) ?? []
        rootConnections = try values.decodeIfPresent([SSHConnection].self, forKey: .rootConnections) ?? []
        rootWebLinks = try values.decodeIfPresent([WebLink].self, forKey: .rootWebLinks) ?? []
        rootTerminalCommands = try values.decodeIfPresent([TerminalCommand].self, forKey: .rootTerminalCommands) ?? []
        credentials = try values.decodeIfPresent([Credential].self, forKey: .credentials) ?? []
        quickAccessWebLinkIDs = try values.decodeIfPresent([UUID].self, forKey: .quickAccessWebLinkIDs) ?? []
    }
}

private struct EncryptedWorkspace: Codable {
    let formatVersion: Int
    let kdf: String
    let iterations: Int
    let salt: String
    let sealedPayload: String
}

private enum WorkspaceCrypto {
    static let configURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GateTree", isDirectory: true)
        .appendingPathComponent("Workspace.gatetree", isDirectory: false)

    static let kdfIterations = 310_000

    static func save(_ workspace: Workspace, password: String, to url: URL = configURL) throws {
        let payload = try JSONEncoder().encode(workspace)
        let envelope = try encrypt(payload, password: password)
        let configData = try JSONEncoder().encode(envelope)

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try configData.write(to: url, options: .atomic)
    }

    static func savePlaintext(_ workspace: Workspace, to url: URL = configURL) throws {
        let data = try JSONEncoder().encode(workspace)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func loadPlaintext() throws -> Workspace {
        try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: configURL))
    }

    static func isEncryptedFile() -> Bool {
        guard let data = try? Data(contentsOf: configURL) else { return false }
        return (try? JSONDecoder().decode(EncryptedWorkspace.self, from: data)) != nil
    }

    static func load(password: String) throws -> Workspace {
        let envelopeData = try Data(contentsOf: configURL)
        let envelope = try JSONDecoder().decode(EncryptedWorkspace.self, from: envelopeData)
        let payload = try decrypt(envelope, password: password)
        return try JSONDecoder().decode(Workspace.self, from: payload)
    }

    static func encrypt(_ payload: Data, password: String) throws -> EncryptedWorkspace {
        var salt = Data(count: 16)
        let randomStatus = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else { throw CryptoError.randomnessUnavailable }

        let key = try deriveKey(password: password, salt: salt)
        let sealedBox = try AES.GCM.seal(payload, using: key)
        guard let combined = sealedBox.combined else { throw CryptoError.encryptionFailed }

        return EncryptedWorkspace(
            formatVersion: 1,
            kdf: "PBKDF2-HMAC-SHA256",
            iterations: kdfIterations,
            salt: salt.base64EncodedString(),
            sealedPayload: combined.base64EncodedString()
        )
    }

    static func decrypt(_ envelope: EncryptedWorkspace, password: String) throws -> Data {
        guard envelope.formatVersion == 1,
              envelope.kdf == "PBKDF2-HMAC-SHA256",
              envelope.iterations >= 100_000,
              let salt = Data(base64Encoded: envelope.salt),
              let combined = Data(base64Encoded: envelope.sealedPayload) else {
            throw CryptoError.invalidFile
        }

        let key = try deriveKey(password: password, salt: salt, iterations: envelope.iterations)
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealedBox, using: key)
    }

    static func deriveKey(password: String, salt: Data, iterations: Int = kdfIterations) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var derivedKey = [UInt8](repeating: 0, count: 32)

        let status = passwordData.withUnsafeBytes { passwordBuffer in
            salt.withUnsafeBytes { saltBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.bindMemory(to: Int8.self).baseAddress,
                    passwordData.count,
                    saltBuffer.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &derivedKey,
                    derivedKey.count
                )
            }
        }

        guard status == kCCSuccess else { throw CryptoError.keyDerivationFailed }
        return SymmetricKey(data: derivedKey)
    }

    enum CryptoError: Error {
        case randomnessUnavailable
        case encryptionFailed
        case invalidFile
        case keyDerivationFailed
    }
}
