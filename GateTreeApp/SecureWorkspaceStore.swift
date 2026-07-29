// SPDX-License-Identifier: Apache-2.0

import CommonCrypto
import CryptoKit
import Foundation
import Security
import AppKit

@MainActor
final class SecureWorkspaceStore: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var needsMasterPasswordSetup: Bool
    @Published private(set) var isProcessing = false
    @Published var errorMessage: String?
    @Published private(set) var folders: [WorkspaceFolder] = []
    @Published private(set) var rootConnections: [SSHConnection] = []
    @Published private(set) var rootWebLinks: [WebLink] = []
    @Published private(set) var credentials: [Credential] = []
    @Published private(set) var selectedSSHConnection: SSHConnection?
    @Published private(set) var openSSHConnections: [SSHConnection] = []
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
    @Published var editingFolderName = ""
    @Published var editingFolderCredentialID: UUID?
    @Published var isShowingSSHConnectionCreation = false
    @Published var isShowingWebLinkCreation = false
    @Published var isShowingWebLinkEditor = false
    @Published var isShowingSSHConnectionEditor = false
    @Published var isShowingSSHConnectionDeletionConfirmation = false
    @Published var isShowingSSHUsernamePrompt = false
    @Published var promptedSSHUsername = ""
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
    private var webLinkParentFolderID: UUID?
    @Published private(set) var editingWebLink: WebLink?
    @Published private(set) var editingSSHConnection: SSHConnection?
    private var deletingSSHConnectionID: UUID?
    private var pendingSSHConnection: SSHConnection?
    private var deletingCredentialID: UUID?
    @Published private(set) var editingCredential: Credential?
    private var lastOpenedWebLinkID: UUID?
    private var lastOpenedWebLinkDate: Date = .distantPast
    private var sshPasswordsByConnectionID: [UUID: String] = [:]

    init(fileManager: FileManager = .default) {
        expandedFolderIDs = Set(
            UserDefaults.standard.stringArray(forKey: "GateTree.expandedFolderIDs")?.compactMap { UUID(uuidString: $0) } ?? []
        )
        let restoredSelectedTreeItemID = UserDefaults.standard.string(forKey: "GateTree.lastSelectedTreeItemID").flatMap { UUID(uuidString: $0) }
        selectedTreeItemID = restoredSelectedTreeItemID
        if let restoredSelectedTreeItemID {
            selectedTreeItemIDs = [restoredSelectedTreeItemID]
        }
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
                credentials = loadedWorkspace.credentials
                storageMode = .plaintext
                needsMasterPasswordSetup = false
                isUnlocked = true
            } catch {
                needsMasterPasswordSetup = false
                errorMessage = "The workspace file is not readable."
            }
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
                    self.credentials = []
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
                    self.credentials = loadedWorkspace.credentials
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

    func createCredential(name: String, username: String, password: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedUsername.isEmpty, !isProcessing else { return }

        let credential = Credential(name: trimmedName, username: trimmedUsername)
        do {
            try CredentialKeychain.save(password, for: credential.id)
            credentials.append(credential)
            synchronizeWorkspace()
            isShowingCredentialCreation = false
            save()
        } catch {
            errorMessage = "Could not save the password in macOS Keychain."
        }
    }

    func cancelCredentialCreation() { isShowingCredentialCreation = false }

    func showCredentialEditor(_ credential: Credential) {
        guard !isProcessing else { return }
        editingCredential = credential
        isShowingCredentialEditor = true
    }

    func updateCredential(name: String, username: String, newPassword: String) {
        guard let editingCredential, !isProcessing else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedUsername.isEmpty else { return }

        do {
            if !newPassword.isEmpty {
                try CredentialKeychain.save(newPassword, for: editingCredential.id)
            }
            guard let index = credentials.firstIndex(where: { $0.id == editingCredential.id }) else { return }
            credentials[index] = Credential(id: editingCredential.id, name: trimmedName, username: trimmedUsername)
            synchronizeWorkspace()
            self.editingCredential = nil
            isShowingCredentialEditor = false
            save()
        } catch {
            errorMessage = "Could not update the password in macOS Keychain."
        }
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
        CredentialKeychain.delete(for: deletingCredentialID)
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

    func showWebLinkCreation(in folder: WorkspaceFolder? = nil) {
        guard !isProcessing else { return }
        webLinkParentFolderID = folder?.id
        isShowingWebLinkCreation = true
    }

    func createWebLink(name: String, urlString: String) {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              !isProcessing else {
            errorMessage = "Enter a valid http or https URL."
            return
        }

        let webLink = WebLink(name: trimmedName.isEmpty ? (url.host ?? trimmedURL) : trimmedName, url: trimmedURL)
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

    func updateWebLink(name: String, urlString: String) {
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
            url: trimmedURL
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

    func createSSHConnection(name: String, host: String, username: String, port: Int) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty,
              (1...65_535).contains(port),
              !isProcessing else { return }

        let connection = SSHConnection(
            name: trimmedName.isEmpty ? trimmedHost : trimmedName,
            host: trimmedHost,
            username: trimmedUsername,
            port: port,
            credentialID: pendingConnectionCredentialID
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

    func showSSHConnectionEditor(_ connection: SSHConnection) {
        guard !isProcessing else { return }
        editingSSHConnection = connection
        isShowingSSHConnectionEditor = true
    }

    func updateSSHConnection(name: String, host: String, username: String, port: Int, credentialID: UUID?) {
        guard let editingSSHConnection,
              !isProcessing,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...65_535).contains(port) else { return }

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = SSHConnection(
            id: editingSSHConnection.id,
            name: trimmedName.isEmpty ? trimmedHost : trimmedName,
            host: trimmedHost,
            username: trimmedUsername,
            port: port,
            credentialID: credentialID
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
        let username = connection.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (inheritedCredential?.username ?? "")
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
                credentialID: connection.credentialID
            )
            activateSSHConnection(
                sessionConnection,
                password: inheritedCredential.flatMap { try? CredentialKeychain.password(for: $0.id) }
            )
        }
    }

    func connectWithPromptedSSHUsername() {
        let username = promptedSSHUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pendingSSHConnection, !username.isEmpty else { return }
        let sessionConnection = SSHConnection(
            id: pendingSSHConnection.id,
            name: pendingSSHConnection.name,
            host: pendingSSHConnection.host,
            username: username,
            port: pendingSSHConnection.port
        )
        activateSSHConnection(
            sessionConnection,
            password: effectiveCredential(for: pendingSSHConnection).flatMap { try? CredentialKeychain.password(for: $0.id) }
        )
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
        openSSHConnections.removeAll { $0.id == id }
        sshPasswordsByConnectionID[id] = nil
        guard selectedSSHConnection?.id == id else { return }
        selectedSSHConnection = openSSHConnections.last
        selectedSSHPassword = selectedSSHConnection.flatMap { sshPasswordsByConnectionID[$0.id] }
    }

    func selectOpenSSHConnection(_ connection: SSHConnection) {
        guard openSSHConnections.contains(where: { $0.id == connection.id }) else { return }
        selectedSSHConnection = connection
        selectedSSHPassword = sshPasswordsByConnectionID[connection.id]
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

        if lastOpenedWebLinkID == webLink.id,
           Date().timeIntervalSince(lastOpenedWebLinkDate) < 0.7 {
            return
        }
        lastOpenedWebLinkID = webLink.id
        lastOpenedWebLinkDate = .now
        openWebLinkInChrome(webLink)
    }

    func openWebLinkInChrome(_ webLink: WebLink) {
        guard let url = URL(string: webLink.url) else {
            errorMessage = "This web bookmark has an invalid URL."
            return
        }
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

    func focusChrome() {
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

    func showCredentialAssignment() {
        guard hasTreeSelection, !isProcessing else { return }
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
        } else if !removeConnection(deletingSSHConnectionID, from: &folders) {
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

    func createFolder(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let folder = WorkspaceFolder(name: trimmedName)
        if let folderParentID, !insert(folder, into: &folders, below: folderParentID) {
            errorMessage = "The parent folder is no longer available."
            return
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
        isShowingFolderEditor = true
    }

    func renameEditedFolder() {
        let trimmedName = editingFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let editingFolderID, !trimmedName.isEmpty, !isProcessing else { return }
        guard updateFolder(editingFolderID, name: trimmedName, credentialID: editingFolderCredentialID, in: &folders) else { return }

        synchronizeWorkspace()
        self.editingFolderID = nil
        self.editingFolderCredentialID = nil
        isShowingFolderEditor = false
        save()
    }

    func cancelFolderEditor() {
        editingFolderID = nil
        editingFolderCredentialID = nil
        isShowingFolderEditor = false
    }

    func showFolderDeletionConfirmation(_ folder: WorkspaceFolder) {
        guard folder.children.isEmpty, folder.connections.isEmpty, folder.webLinks.isEmpty, !isProcessing else { return }
        deletingFolderID = folder.id
        isShowingFolderDeletionConfirmation = true
    }

    func deleteConfirmedFolder() {
        guard let deletingFolderID, !isProcessing else { return }
        guard let folder = findFolder(deletingFolderID, in: folders), folder.children.isEmpty, folder.connections.isEmpty, folder.webLinks.isEmpty else {
            errorMessage = "Only empty folders can be deleted."
            return
        }
        guard removeFolder(deletingFolderID, from: &folders) != nil else { return }

        synchronizeWorkspace()
        self.deletingFolderID = nil
        isShowingFolderDeletionConfirmation = false
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

    private func synchronizeWorkspace() {
        workspace = Workspace(
            formatVersion: workspace.formatVersion,
            createdAt: workspace.createdAt,
            folders: folders,
            rootConnections: rootConnections,
            rootWebLinks: rootWebLinks,
            credentials: credentials
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

    private func updateFolder(_ id: UUID, name: String, credentialID: UUID?, in folders: inout [WorkspaceFolder]) -> Bool {
        for index in folders.indices {
            if folders[index].id == id {
                folders[index].name = name
                folders[index].credentialID = credentialID
                return true
            }
            if updateFolder(id, name: name, credentialID: credentialID, in: &folders[index].children) {
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

    var selectedWebLinkForInspector: WebLink? {
        guard let selectedTreeItemID else { return nil }
        if let webLink = rootWebLinks.first(where: { $0.id == selectedTreeItemID }) {
            return webLink
        }
        return findWebLink(selectedTreeItemID, in: folders)
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

    private func removeConnection(_ id: UUID, from folders: inout [WorkspaceFolder]) -> Bool {
        for index in folders.indices {
            if let connectionIndex = folders[index].connections.firstIndex(where: { $0.id == id }) {
                folders[index].connections.remove(at: connectionIndex)
                return true
            }
            if removeConnection(id, from: &folders[index].children) { return true }
        }
        return false
    }
}

enum WorkspaceStorageMode {
    case encrypted
    case plaintext
}

struct WorkspaceFolder: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var children: [WorkspaceFolder]
    var connections: [SSHConnection]
    var webLinks: [WebLink]
    var credentialID: UUID?

    init(id: UUID = UUID(), name: String, children: [WorkspaceFolder] = [], connections: [SSHConnection] = [], webLinks: [WebLink] = [], credentialID: UUID? = nil) {
        self.id = id
        self.name = name
        self.children = children
        self.connections = connections
        self.webLinks = webLinks
        self.credentialID = credentialID
    }

    var outlineChildren: [WorkspaceFolder]? {
        children.isEmpty ? nil : children
    }

    enum CodingKeys: String, CodingKey { case id, name, children, connections, webLinks, credentialID }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        children = try values.decodeIfPresent([WorkspaceFolder].self, forKey: .children) ?? []
        connections = try values.decodeIfPresent([SSHConnection].self, forKey: .connections) ?? []
        webLinks = try values.decodeIfPresent([WebLink].self, forKey: .webLinks) ?? []
        credentialID = try values.decodeIfPresent(UUID.self, forKey: .credentialID)
    }
}

struct WebLink: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var url: String

    init(id: UUID = UUID(), name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
    }
}

struct SSHConnection: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var host: String
    var username: String
    var port: Int
    var credentialID: UUID?

    init(id: UUID = UUID(), name: String, host: String, username: String, port: Int, credentialID: UUID? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.username = username
        self.port = port
        self.credentialID = credentialID
    }

    enum CodingKeys: String, CodingKey { case id, name, host, username, port, credentialID }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        host = try values.decode(String.self, forKey: .host)
        username = try values.decodeIfPresent(String.self, forKey: .username) ?? ""
        port = try values.decode(Int.self, forKey: .port)
        credentialID = try values.decodeIfPresent(UUID.self, forKey: .credentialID)
    }
}

struct Credential: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var username: String

    init(id: UUID = UUID(), name: String, username: String) {
        self.id = id
        self.name = name
        self.username = username
    }
}

private struct Workspace: Codable, Sendable {
    let formatVersion: Int
    let createdAt: Date
    let folders: [WorkspaceFolder]
    let rootConnections: [SSHConnection]
    let rootWebLinks: [WebLink]
    let credentials: [Credential]

    init(formatVersion: Int = 1, createdAt: Date = .now, folders: [WorkspaceFolder] = [], rootConnections: [SSHConnection] = [], rootWebLinks: [WebLink] = [], credentials: [Credential] = []) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.folders = folders
        self.rootConnections = rootConnections
        self.rootWebLinks = rootWebLinks
        self.credentials = credentials
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        folders = try values.decodeIfPresent([WorkspaceFolder].self, forKey: .folders) ?? []
        rootConnections = try values.decodeIfPresent([SSHConnection].self, forKey: .rootConnections) ?? []
        rootWebLinks = try values.decodeIfPresent([WebLink].self, forKey: .rootWebLinks) ?? []
        credentials = try values.decodeIfPresent([Credential].self, forKey: .credentials) ?? []
    }
}

private enum CredentialKeychain {
    private static let service = "com.zsoltkarman.GateTree.credentials"

    static func save(_ password: String, for id: UUID) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
        guard !password.isEmpty else { return }

        var item = query
        item[kSecValueData] = Data(password.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    static func delete(for id: UUID) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func password(for id: UUID) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id.uuidString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(status)
        }
        return password
    }

    enum KeychainError: Error { case unexpectedStatus(OSStatus) }
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
