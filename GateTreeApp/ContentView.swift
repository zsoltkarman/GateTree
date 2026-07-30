// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var searchText = ""
    @State private var sidebarVisible = true
    @State private var sidebarWidth: CGFloat?
    @State private var sidebarDragStartWidth: CGFloat?

    var body: some View {
        Group {
            if workspaceStore.isUnlocked {
                GeometryReader { geometry in
                    let resolvedSidebarWidth = sidebarWidth ?? max(180, geometry.size.width * 0.2)
                    let maximumSidebarWidth = min(560, geometry.size.width * 0.6)
                    let sidebarTreeHeight = max(120, geometry.size.height - 320)
                    HStack(spacing: 0) {
                        if sidebarVisible {
                            VStack(spacing: 0) {
                                HStack(spacing: 8) {
                                    TextField("Search connections", text: $searchText)
                                        .textFieldStyle(.roundedBorder)

                                    sidebarToggle
                                }
                                .padding(12)

                                Divider()

                                FolderList()
                                    .frame(height: sidebarTreeHeight, alignment: .top)

                                Divider()
                                SidebarApplications()

                                Color.white.opacity(0.82)
                                    .frame(height: 12)
                                Divider()
                                HostInspector()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .frame(width: min(maximumSidebarWidth, max(180, resolvedSidebarWidth)))
                            .background(.quaternary.opacity(0.35))

                            sidebarResizeHandle(
                                currentWidth: resolvedSidebarWidth,
                                maximumWidth: maximumSidebarWidth
                            )
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            if !sidebarVisible {
                                sidebarToggle
                                    .padding(12)
                            }

                            if workspaceStore.isShowingCredentials {
                                CredentialsManagerView()
                            } else if !workspaceStore.openSSHConnections.isEmpty || !workspaceStore.openExternalWebLinks.isEmpty {
                                VStack(spacing: 0) {
                                    SessionTabBar()
                                    if let webLink = workspaceStore.activeExternalWebLink {
                                        ChromeLinkPane(webLink: webLink)
                                    } else {
                                        ZStack {
                                            ForEach(workspaceStore.openSSHConnections) { connection in
                                                SSHSessionPane(connection: connection, password: workspaceStore.password(for: connection)) {
                                                    workspaceStore.closeSSHConnection(connection.id)
                                                }
                                                .opacity(workspaceStore.selectedSSHConnection?.id == connection.id ? 1 : 0)
                                                .allowsHitTesting(workspaceStore.selectedSSHConnection?.id == connection.id)
                                            }
                                        }
                                    }
                                }
                            } else {
                                ContentUnavailableView(
                                    "No connection selected",
                                    systemImage: "rectangle.connected.to.line.below",
                                    description: Text("Click an SSH connection to open it here."))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                MasterPasswordView()
            }
        }
        .alert(
            "GateTree",
            isPresented: Binding(
                get: { workspaceStore.errorMessage != nil },
                set: { if !$0 { workspaceStore.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { workspaceStore.errorMessage = nil }
        } message: {
            Text(workspaceStore.errorMessage ?? "")
        }
        .sheet(isPresented: $workspaceStore.isShowingFolderCreation) {
            FolderNameView()
                .environmentObject(workspaceStore)
        }
        .sheet(isPresented: $workspaceStore.isShowingPasswordChange) {
            PasswordChangeView()
                .environmentObject(workspaceStore)
        }
        .sheet(isPresented: $workspaceStore.isShowingEncryptionSetup) {
            EncryptionSetupView()
                .environmentObject(workspaceStore)
        }
        .confirmationDialog(
            "Decrypt workspace?",
            isPresented: $workspaceStore.isShowingDecryptionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Decrypt Workspace", role: .destructive) {
                workspaceStore.decryptWorkspace()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The config file will be saved as readable JSON and will no longer ask for a master password at startup.")
        }
        .sheet(isPresented: $workspaceStore.isShowingFolderEditor) {
            FolderEditorView()
                .environmentObject(workspaceStore)
        }
        .sheet(isPresented: $workspaceStore.isShowingSSHConnectionCreation) {
            SSHConnectionForm()
                .environmentObject(workspaceStore)
        }
        .sheet(isPresented: $workspaceStore.isShowingWebLinkCreation) {
            WebLinkForm()
                .environmentObject(workspaceStore)
        }
        .sheet(isPresented: $workspaceStore.isShowingTerminalCommandCreation) {
            TerminalCommandForm()
                .environmentObject(workspaceStore)
        }
        .sheet(isPresented: $workspaceStore.isShowingWebLinkEditor) {
            WebLinkEditorForm()
                .environmentObject(workspaceStore)
        }
        .sheet(isPresented: $workspaceStore.isShowingSSHConnectionEditor) {
            SSHConnectionEditorForm()
                .environmentObject(workspaceStore)
        }
        .sheet(isPresented: $workspaceStore.isShowingSSHUsernamePrompt) {
            SSHUsernamePrompt()
                .environmentObject(workspaceStore)
        }
        .sheet(isPresented: $workspaceStore.isShowingCredentialCreation) {
            CredentialForm()
                .environmentObject(workspaceStore)
        }
        .sheet(isPresented: $workspaceStore.isShowingCredentialEditor) {
            CredentialEditorForm()
                .environmentObject(workspaceStore)
        }
        .sheet(isPresented: $workspaceStore.isShowingCredentialAssignment) {
            CredentialAssignmentForm()
                .environmentObject(workspaceStore)
        }
        .confirmationDialog(
            "Delete empty folder?",
            isPresented: $workspaceStore.isShowingFolderDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                workspaceStore.deleteConfirmedFolder()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .confirmationDialog(
            "Delete connection?",
            isPresented: $workspaceStore.isShowingSSHConnectionDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Connection", role: .destructive) {
                workspaceStore.deleteConfirmedSSHConnection()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .confirmationDialog(
            "Delete credential?",
            isPresented: $workspaceStore.isShowingCredentialDeletionConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Credential", role: .destructive) {
                workspaceStore.deleteConfirmedCredential()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved password will also be removed from macOS Keychain.")
        }
    }

    private var sidebarToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                sidebarVisible.toggle()
            }
        } label: {
            Image(systemName: "sidebar.left")
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .help(sidebarVisible ? "Hide connections" : "Show connections")
    }

    private func sidebarResizeHandle(currentWidth: CGFloat, maximumWidth: CGFloat) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 7)
            .contentShape(Rectangle())
            .overlay(alignment: .center) {
                Divider()
            }
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if sidebarDragStartWidth == nil {
                            sidebarDragStartWidth = currentWidth
                        }
                        let startWidth = sidebarDragStartWidth ?? currentWidth
                        sidebarWidth = min(maximumWidth, max(180, startWidth + value.translation.width))
                    }
                    .onEnded { _ in
                        sidebarDragStartWidth = nil
                    }
            )
    }
}

private struct SessionTabBar: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(workspaceStore.openSSHConnections) { connection in
                    HStack(spacing: 5) {
                        Button {
                            workspaceStore.selectOpenSSHConnection(connection)
                        } label: {
                            Label(connection.name, systemImage: "terminal")
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        Button {
                            workspaceStore.closeSSHConnection(connection.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        workspaceStore.selectedSSHConnection?.id == connection.id
                            ? Color.accentColor.opacity(0.25)
                            : Color.secondary.opacity(0.10)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                ForEach(workspaceStore.openExternalWebLinks) { webLink in
                    HStack(spacing: 5) {
                        Button {
                            workspaceStore.selectOpenExternalWebLink(webLink)
                        } label: {
                            Label(webLink.name, systemImage: "globe")
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        Button {
                            workspaceStore.closeExternalWebLink(webLink.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        workspaceStore.activeExternalWebLink?.id == webLink.id
                            ? Color.accentColor.opacity(0.25)
                            : Color.secondary.opacity(0.10)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.bar)
        Divider()
    }
}

private struct ChromeLinkPane: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    let webLink: WebLink

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(webLink.name).font(.headline)
                    Text(webLink.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Button {
                    workspaceStore.closeExternalWebLink()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .help("Close web tab")
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                Label("Opened in Google Chrome", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("GateTree keeps this bookmark selected while Chrome handles the Oracle SSO and FIDO session.")
                    .foregroundStyle(.secondary)

                Button {
                    workspaceStore.focusChrome()
                } label: {
                    Label("Focus Chrome", systemImage: "macwindow")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct SidebarApplications: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                isExpanded.toggle()
            } label: {
                Label("Applications", systemImage: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Button {
                    workspaceStore.showCredentials()
                } label: {
                    Label("Credentials", systemImage: "key.fill")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(workspaceStore.isShowingCredentials ? Color.accentColor.opacity(0.72) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)

                if workspaceStore.hasAssignableTreeSelection {
                    Button {
                        workspaceStore.showCredentialAssignment()
                    } label: {
                        Label("Assign credential", systemImage: "key.horizontal")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
    }
}

private struct HostInspector: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore

    var body: some View {
        Group {
            if let connection = workspaceStore.selectedConnectionForInspector {
                VStack(alignment: .leading, spacing: 3) {
                    Label(connection.name, systemImage: "server.rack")
                        .font(.system(size: 12, weight: .medium))
                    InspectorRow(label: "Host", value: "\(connection.host):\(connection.port)")
                    InspectorRow(label: "User", value: workspaceStore.resolvedUsername(for: connection))
                    InspectorRow(label: "Credential", value: workspaceStore.credentialSummary(for: connection))
                }
                .padding(8)
            } else if let webLink = workspaceStore.selectedWebLinkForInspector {
                VStack(alignment: .leading, spacing: 3) {
                    Label(webLink.name, systemImage: "globe")
                        .font(.system(size: 12, weight: .medium))
                    InspectorRow(label: "Type", value: "Web bookmark")
                    InspectorRow(label: "URL", value: webLink.url)
                }
                .padding(8)
            } else if let terminalCommand = workspaceStore.selectedTerminalCommandForInspector {
                VStack(alignment: .leading, spacing: 3) {
                    Label(terminalCommand.name, systemImage: "terminal")
                        .font(.system(size: 12, weight: .medium))
                    InspectorRow(label: "Type", value: "Terminal connection")
                    InspectorRow(label: "Command", value: terminalCommand.command)
                    InspectorRow(label: "Action", value: "Double-click opens a new Terminal window")
                }
                .padding(8)
            } else {
                Text("Select a connection to see its details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: 106, alignment: .topLeading)
    }
}

private struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.system(size: 10))
    }
}

private struct FolderList: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore

    var body: some View {
        List {
            if workspaceStore.folders.isEmpty {
                ContentUnavailableView(
                    "No folders",
                    systemImage: "folder",
                    description: Text("Use Connections → New Folder to start."))
            } else {
                ForEach(workspaceStore.folders) { folder in
                    FolderTreeRow(folder: folder, depth: 0)
                }
            }

            ForEach(workspaceStore.rootConnections) { connection in
                SSHConnectionLabel(name: connection.name)
                    .help("SSH: \(connection.host):\(connection.port)")
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 6))
                    .listRowBackground(treeSelectionBackground(for: connection.id))
                    .simultaneousGesture(TapGesture().onEnded {
                        workspaceStore.selectTreeItem(connection.id)
                    })
                    .onTapGesture(count: 2) {
                        workspaceStore.selectSSHConnection(connection)
                    }
                    .contextMenu {
                        Button("Edit…") {
                            workspaceStore.showSSHConnectionEditor(connection)
                        }
                        Divider()
                        Button("Delete…", role: .destructive) {
                            workspaceStore.showSSHConnectionDeletionConfirmation(connection)
                        }
                    }
            }

            ForEach(workspaceStore.rootWebLinks) { webLink in
                WebLinkLabel(name: webLink.name, url: webLink.url)
                    .help(webLink.url)
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 6))
                    .listRowBackground(treeSelectionBackground(for: webLink.id))
                    .onTapGesture { workspaceStore.selectTreeItem(webLink.id) }
                    .onTapGesture(count: 2) { workspaceStore.selectWebLink(webLink) }
                    .contextMenu { webLinkMenu(webLink) }
            }

            ForEach(workspaceStore.rootTerminalCommands) { terminalCommand in
                TerminalCommandLabel(name: terminalCommand.name)
                    .help(terminalCommand.command)
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 6))
                    .listRowBackground(treeSelectionBackground(for: terminalCommand.id))
                    .onTapGesture { workspaceStore.selectTreeItem(terminalCommand.id) }
                    .onTapGesture(count: 2) { TerminalCommandLauncher.openInTerminal(terminalCommand.command) }
            }

            Color.clear
                .frame(height: 1)
                .onDrop(of: [.text], delegate: FolderDropDelegate(targetFolderID: nil, store: workspaceStore))
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 18)
        .font(.system(size: 12, weight: .regular))
        .contextMenu {
            Menu("New Connection") {
                Button("Server (SSH)") { workspaceStore.showSSHConnectionCreation() }
                Button("URL") { workspaceStore.showWebLinkCreation() }
                Button("Terminal") { workspaceStore.showTerminalCommandCreation() }
            }
            Button("New Folder") {
                workspaceStore.showFolderCreation()
            }
        }
    }

    private func treeSelectionBackground(for id: UUID) -> Color {
        workspaceStore.selectedTreeItemIDs.contains(id) ? Color.accentColor.opacity(0.72) : .clear
    }

    @ViewBuilder
    private func webLinkMenu(_ webLink: WebLink) -> some View {
        Button("Edit…") { workspaceStore.showWebLinkEditor(webLink) }
    }
}

private struct CredentialsManagerView: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Credentials")
                        .font(.title2.weight(.semibold))
                    Text("Passwords are stored in macOS Keychain, not in the workspace file.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    workspaceStore.showCredentialCreation()
                } label: {
                    Label("Add Credential", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)

            Divider()

            if workspaceStore.credentials.isEmpty {
                ContentUnavailableView(
                    "No credentials",
                    systemImage: "key",
                    description: Text("Add a credential to reuse its username and password later."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(workspaceStore.credentials) { credential in
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(credential.name)
                            Text(credential.username)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if workspaceStore.isCredentialInUse(credential.id) {
                                Text("Assigned — cannot be deleted")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contextMenu {
                        Button("Edit…") {
                            workspaceStore.showCredentialEditor(credential)
                        }
                        Divider()
                        Button("Delete…", role: .destructive) {
                            workspaceStore.showCredentialDeletionConfirmation(credential)
                        }
                        .disabled(workspaceStore.isCredentialInUse(credential.id))
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CredentialForm: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var name = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Credential")
                .font(.title2.weight(.semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
            SecureField("Password (stored in Keychain)", text: $password)
                .textFieldStyle(.roundedBorder)
            Text("Leave the password blank for a username-only credential.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { workspaceStore.cancelCredentialCreation() }
                Spacer()
                Button("Add Credential") {
                    workspaceStore.createCredential(name: name, username: username, password: password)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

private struct CredentialAssignmentForm: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Assign Credential")
                .font(.title2.weight(.semibold))
            Text("Assigning a credential to a folder overrides its inherited credential. Assigning it to a connection overrides the folder credential.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Credential", selection: $workspaceStore.selectedCredentialAssignmentID) {
                Text("Inherit / remove override").tag(UUID?.none)
                ForEach(workspaceStore.credentials) { credential in
                    Text("\(credential.name) (\(credential.username))").tag(Optional(credential.id))
                }
            }
            HStack {
                Button("Cancel") { workspaceStore.isShowingCredentialAssignment = false }
                Spacer()
                Button("Apply") { workspaceStore.applyCredentialAssignment() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

private struct CredentialEditorForm: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var name = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Credential")
                .font(.title2.weight(.semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
            SecureField("New password (optional)", text: $password)
                .textFieldStyle(.roundedBorder)
            Text("Leave the password empty to keep the existing Keychain password.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { workspaceStore.cancelCredentialEditor() }
                Spacer()
                Button("Save") {
                    workspaceStore.updateCredential(name: name, username: username, newPassword: password)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            name = workspaceStore.editingCredential?.name ?? ""
            username = workspaceStore.editingCredential?.username ?? ""
        }
    }
}

private struct SSHConnectionLabel: View {
    let name: String

    var body: some View {
        HStack(spacing: 5) {
            Image("OracleLinuxServer")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(name)
        }
        .frame(height: 18)
    }
}

private struct WebLinkLabel: View {
    let name: String
    let url: String

    private var iconName: String {
        if url.contains("thanos-rule.") { return "checkmark.seal" }
        if url.contains("thanos.") { return "chart.xyaxis.line" }
        if url.contains("shuttleproxy.") { return "arrow.triangle.swap" }
        if url.contains("api.") { return "network" }
        return "arrow.up.right.square"
    }

    var body: some View {
        Label(name, systemImage: iconName)
            .frame(height: 18)
    }
}

private struct TerminalCommandLabel: View {
    let name: String

    var body: some View {
        Label(name, systemImage: "terminal")
            .foregroundStyle(.purple)
    }
}

private struct EmbeddedWebPane: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    let webLink: WebLink

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(webLink.name).font(.headline)
                    Text(webLink.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button {
                    workspaceStore.openWebLinkInChrome(webLink)
                } label: {
                    Label("Open in Chrome", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            EmbeddedWebView(url: URL(string: webLink.url))
        }
    }
}

private struct EmbeddedWebView: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        if let url { webView.load(URLRequest(url: url)) }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let url, webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}

private struct FolderTreeRow: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    let folder: WorkspaceFolder
    let depth: Int

    private var hasContents: Bool { !folder.children.isEmpty || !folder.connections.isEmpty || !folder.webLinks.isEmpty || !folder.terminalCommands.isEmpty }
    private var isExpanded: Bool { workspaceStore.isFolderExpanded(folder.id) }

    var body: some View {
        Group {
            HStack(spacing: 6) {
                TreeIndentation(depth: depth)
                if hasContents {
                    Button {
                        workspaceStore.toggleFolderExpanded(folder.id)
                    } label: {
                        Image(systemName: isExpanded ? "minus.square" : "plus.square")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 12, height: 1)
                }

                Image("GateTreeFolder")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                Text(folder.name)
            }
            .frame(height: 18)
            .font(.system(size: 12, weight: .regular))
            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 6))
            .listRowBackground(workspaceStore.selectedTreeItemIDs.contains(folder.id) ? Color.accentColor.opacity(0.72) : .clear)
            .onTapGesture {
                workspaceStore.selectTreeItem(folder.id)
                workspaceStore.toggleFolderExpanded(folder.id)
            }
            .contextMenu {
                Button("Edit…") {
                    workspaceStore.showFolderEditor(folder)
                }
                Divider()
                Menu("New Connection") {
                    Button("Server (SSH)") { workspaceStore.showSSHConnectionCreation(in: folder) }
                    Button("URL") { workspaceStore.showWebLinkCreation(in: folder) }
                    Button("Terminal") { workspaceStore.showTerminalCommandCreation(in: folder) }
                }
                Button("New Folder") {
                    workspaceStore.showFolderCreation(parentID: folder.id)
                }
                Divider()
                Button("Delete…", role: .destructive) {
                    workspaceStore.showFolderDeletionConfirmation(folder)
                }
                .disabled(!folder.children.isEmpty || !folder.connections.isEmpty || !folder.webLinks.isEmpty || !folder.terminalCommands.isEmpty)
            }
            .onDrag {
                NSItemProvider(object: folder.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: FolderDropDelegate(targetFolderID: folder.id, store: workspaceStore))

            if isExpanded {
                ForEach(folder.connections) { connection in
                    HStack(spacing: 6) {
                        TreeIndentation(depth: depth + 1)
                        SSHConnectionLabel(name: connection.name)
                    }
                        .frame(height: 18)
                        .help("SSH: \(connection.host):\(connection.port)")
                        .font(.system(size: 12, weight: .regular))
                        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 6))
                        .listRowBackground(workspaceStore.selectedTreeItemIDs.contains(connection.id) ? Color.accentColor.opacity(0.72) : .clear)
                        .simultaneousGesture(TapGesture().onEnded {
                            workspaceStore.selectTreeItem(connection.id)
                        })
                        .onTapGesture(count: 2) {
                            workspaceStore.selectSSHConnection(connection)
                        }
                        .contextMenu { connectionMenu(connection) }
                }
                ForEach(folder.webLinks) { webLink in
                    HStack(spacing: 6) {
                        TreeIndentation(depth: depth + 1)
                        WebLinkLabel(name: webLink.name, url: webLink.url)
                    }
                    .frame(height: 18)
                    .help(webLink.url)
                    .font(.system(size: 12, weight: .regular))
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 6))
                    .listRowBackground(workspaceStore.selectedTreeItemIDs.contains(webLink.id) ? Color.accentColor.opacity(0.72) : .clear)
                    .onTapGesture { workspaceStore.selectTreeItem(webLink.id) }
                    .onTapGesture(count: 2) { workspaceStore.selectWebLink(webLink) }
                    .contextMenu {
                        Button("Edit…") { workspaceStore.showWebLinkEditor(webLink) }
                    }
                }
                ForEach(folder.terminalCommands) { terminalCommand in
                    HStack(spacing: 6) {
                        TreeIndentation(depth: depth + 1)
                        TerminalCommandLabel(name: terminalCommand.name)
                    }
                    .frame(height: 18)
                    .help(terminalCommand.command)
                    .font(.system(size: 12, weight: .regular))
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 6))
                    .listRowBackground(workspaceStore.selectedTreeItemIDs.contains(terminalCommand.id) ? Color.accentColor.opacity(0.72) : .clear)
                    .onTapGesture { workspaceStore.selectTreeItem(terminalCommand.id) }
                    .onTapGesture(count: 2) { TerminalCommandLauncher.openInTerminal(terminalCommand.command) }
                }
                ForEach(folder.children) { child in
                    FolderTreeRow(folder: child, depth: depth + 1)
                }
            }
        }
    }

    @ViewBuilder
    private func connectionMenu(_ connection: SSHConnection) -> some View {
        Button("Edit…") {
            workspaceStore.showSSHConnectionEditor(connection)
        }
        Divider()
        Button("Delete…", role: .destructive) {
            workspaceStore.showSSHConnectionDeletionConfirmation(connection)
        }
    }
}

private struct TreeIndentation: View {
    let depth: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<depth, id: \.self) { index in
                ZStack {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.34))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)

                    if index == depth - 1 {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.34))
                            .frame(width: 8, height: 1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(width: 16, height: 18)
            }
        }
    }
}

private struct FolderDropDelegate: DropDelegate {
    let targetFolderID: UUID?
    let store: SecureWorkspaceStore

    func validateDrop(info: DropInfo) -> Bool {
        !store.isProcessing && info.hasItemsConforming(to: [.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }

        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let identifier = value as? String,
                  let folderID = UUID(uuidString: identifier) else { return }

            DispatchQueue.main.async {
                store.moveFolder(id: folderID, into: targetFolderID)
            }
        }
        return true
    }
}

private struct FolderNameView: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Folder")
                .font(.title2.weight(.semibold))

            TextField("Folder name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createFolder)

            HStack {
                Button("Cancel") {
                    workspaceStore.cancelFolderCreation()
                }
                Spacer()
                Button("Add Folder", action: createFolder)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    private func createFolder() {
        workspaceStore.createFolder(named: name)
    }
}

private struct FolderEditorView: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Folder")
                .font(.title2.weight(.semibold))

            TextField("Folder name", text: $workspaceStore.editingFolderName)
                .textFieldStyle(.roundedBorder)
            Picker("Credential", selection: $workspaceStore.editingFolderCredentialID) {
                Text("Inherit from parent").tag(UUID?.none)
                ForEach(workspaceStore.credentials) { credential in
                    Text("\(credential.name) (\(credential.username))").tag(Optional(credential.id))
                }
            }
            Text(workspaceStore.editingFolderCredentialSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") { workspaceStore.cancelFolderEditor() }
                Spacer()
                Button("Save") { workspaceStore.renameEditedFolder() }
                    .buttonStyle(.borderedProminent)
                    .disabled(workspaceStore.editingFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

private struct SSHConnectionForm: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var name = ""
    @State private var host = ""
    @State private var username = ""
    @State private var port = "22"
    @State private var credentialID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New SSH Connection")
                .font(.title2.weight(.semibold))
            TextField("Name (optional)", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Host or IP address", text: $host)
                .textFieldStyle(.roundedBorder)
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
            TextField("Port", text: $port)
                .textFieldStyle(.roundedBorder)
            Picker("Credential", selection: $credentialID) {
                Text("Inherit from folder").tag(UUID?.none)
                ForEach(workspaceStore.credentials) { credential in
                    Text("\(credential.name) (\(credential.username))").tag(Optional(credential.id))
                }
            }
            if let connection = workspaceStore.editingSSHConnection {
                Text(workspaceStore.credentialSummary(for: connection))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel") { workspaceStore.cancelSSHConnectionCreation() }
                Spacer()
                Button("Add SSH Connection") {
                    guard let portNumber = Int(port) else {
                        workspaceStore.errorMessage = "Enter a valid SSH port."
                        return
                    }
                    workspaceStore.setNewConnectionCredential(credentialID)
                    workspaceStore.createSSHConnection(name: name, host: host, username: username, port: portNumber)
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

private struct WebLinkForm: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var name = ""
    @State private var url = "https://"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Web Link").font(.title2.weight(.semibold))
            TextField("Name (optional)", text: $name).textFieldStyle(.roundedBorder)
            TextField("URL", text: $url).textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { workspaceStore.cancelWebLinkCreation() }
                Spacer()
                Button("Add Web Link") { workspaceStore.createWebLink(name: name, urlString: url) }
                    .buttonStyle(.borderedProminent)
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct TerminalCommandForm: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var name = ""
    @State private var command = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Terminal Connection").font(.title2.weight(.semibold))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            TextField("Command", text: $command).textFieldStyle(.roundedBorder)
            Text("The command runs in a new Terminal window when you double-click this item.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { workspaceStore.cancelTerminalCommandCreation() }
                Spacer()
                Button("Add Terminal Connection") {
                    workspaceStore.createTerminalCommand(name: name, command: command)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct WebLinkEditorForm: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Web Link").font(.title2.weight(.semibold))
            TextField("Name (optional)", text: $name).textFieldStyle(.roundedBorder)
            TextField("URL", text: $url).textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { workspaceStore.cancelWebLinkEditor() }
                Spacer()
                Button("Save") { workspaceStore.updateWebLink(name: name, urlString: url) }
                    .buttonStyle(.borderedProminent)
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            name = workspaceStore.editingWebLink?.name ?? ""
            url = workspaceStore.editingWebLink?.url ?? ""
        }
    }
}

private struct SSHConnectionEditorForm: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var name = ""
    @State private var host = ""
    @State private var username = ""
    @State private var port = "22"
    @State private var credentialID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit SSH Connection")
                .font(.title2.weight(.semibold))
            TextField("Name (optional)", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Host or IP address", text: $host)
                .textFieldStyle(.roundedBorder)
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
            TextField("Port", text: $port)
                .textFieldStyle(.roundedBorder)
            Picker("Credential", selection: $credentialID) {
                Text("Inherit from folder").tag(UUID?.none)
                ForEach(workspaceStore.credentials) { credential in
                    Text("\(credential.name) (\(credential.username))").tag(Optional(credential.id))
                }
            }

            HStack {
                Button("Cancel") { workspaceStore.cancelSSHConnectionEditor() }
                Spacer()
                Button("Save") {
                    guard let portNumber = Int(port) else {
                        workspaceStore.errorMessage = "Enter a valid SSH port."
                        return
                    }
                    workspaceStore.updateSSHConnection(name: name, host: host, username: username, port: portNumber, credentialID: credentialID)
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            if let connection = workspaceStore.editingSSHConnection {
                name = connection.name
                host = connection.host
                username = connection.username
                port = String(connection.port)
                credentialID = connection.credentialID
            }
        }
    }
}

private struct SSHUsernamePrompt: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SSH Username")
                .font(.title2.weight(.semibold))
            Text("Enter the username for this connection. It will be used only for this session.")
                .foregroundStyle(.secondary)
            TextField("Username", text: $workspaceStore.promptedSSHUsername)
                .textFieldStyle(.roundedBorder)
                .onSubmit { workspaceStore.connectWithPromptedSSHUsername() }
            HStack {
                Button("Cancel") { workspaceStore.cancelSSHUsernamePrompt() }
                Spacer()
                Button("Connect") { workspaceStore.connectWithPromptedSSHUsername() }
                    .buttonStyle(.borderedProminent)
                    .disabled(workspaceStore.promptedSSHUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

private struct PasswordChangeView: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Change Master Password")
                .font(.title2.weight(.semibold))
            SecureField("Current password", text: $currentPassword)
                .textFieldStyle(.roundedBorder)
            SecureField("New password", text: $newPassword)
                .textFieldStyle(.roundedBorder)
            SecureField("Confirm new password", text: $confirmation)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { workspaceStore.isShowingPasswordChange = false }
                Spacer()
                Button("Change Password") {
                    guard newPassword == confirmation else {
                        workspaceStore.errorMessage = "The new master passwords do not match."
                        return
                    }
                    workspaceStore.changeMasterPassword(currentPassword: currentPassword, newPassword: newPassword)
                }
                .buttonStyle(.borderedProminent)
                .disabled(workspaceStore.isProcessing || currentPassword.isEmpty || newPassword.isEmpty || confirmation.isEmpty)
            }

            if workspaceStore.isProcessing { ProgressView("Changing master password…") }
        }
        .padding(24)
        .frame(width: 360)
    }
}

private struct EncryptionSetupView: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Encrypt Workspace")
                .font(.title2.weight(.semibold))
            Text("Create a master password to encrypt the current workspace.")
                .foregroundStyle(.secondary)
            SecureField("Master password", text: $password)
                .textFieldStyle(.roundedBorder)
            SecureField("Confirm master password", text: $confirmation)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { workspaceStore.isShowingEncryptionSetup = false }
                Spacer()
                Button("Encrypt") {
                    guard password == confirmation else {
                        workspaceStore.errorMessage = "The master passwords do not match."
                        return
                    }
                    workspaceStore.encryptWorkspace(masterPassword: password)
                }
                .buttonStyle(.borderedProminent)
                .disabled(workspaceStore.isProcessing || password.isEmpty || confirmation.isEmpty)
            }

            if workspaceStore.isProcessing { ProgressView("Encrypting workspace…") }
        }
        .padding(24)
        .frame(width: 360)
    }
}

private struct MasterPasswordView: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "lock.shield")
                .font(.system(size: 34))
                .foregroundStyle(.tint)

            Text(workspaceStore.needsMasterPasswordSetup ? "Create master password" : "Unlock GateTree")
                .font(.title2.weight(.semibold))

            Text(workspaceStore.needsMasterPasswordSetup
                 ? "Your workspace will always be saved encrypted. The master password is never written to disk."
                 : "Enter the master password to unlock the encrypted workspace.")
                .foregroundStyle(.secondary)

            SecureField("Master password", text: $password)
                .textFieldStyle(.roundedBorder)

            if workspaceStore.needsMasterPasswordSetup {
                SecureField("Confirm master password", text: $confirmation)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button(workspaceStore.needsMasterPasswordSetup ? "Create encrypted workspace" : "Unlock") {
                    if workspaceStore.needsMasterPasswordSetup {
                        guard password == confirmation else {
                            workspaceStore.errorMessage = "The master passwords do not match."
                            return
                        }
                        workspaceStore.createWorkspace(masterPassword: password)
                    } else {
                        workspaceStore.unlock(masterPassword: password)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(workspaceStore.isProcessing || password.isEmpty || (workspaceStore.needsMasterPasswordSetup && confirmation.isEmpty))
            }

            if workspaceStore.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(workspaceStore.needsMasterPasswordSetup ? "Creating encrypted workspace…" : "Unlocking workspace…")
                        .foregroundStyle(.secondary)
                }
            }

            Text(workspaceStore.configPath)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .padding(28)
        .frame(width: 440)
    }
}
