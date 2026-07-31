// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private func treeItemProvider(_ payload: String) -> NSItemProvider {
    NSItemProvider(object: payload as NSString)
}

struct ContentView: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var searchText = ""
    @State private var sidebarVisible = true
    @State private var sidebarWidth: CGFloat?
    @State private var sidebarDragStartWidth: CGFloat?
    @State private var isSearchHelpPresented = false

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

                                    Button {
                                        isSearchHelpPresented.toggle()
                                    } label: {
                                        Image(systemName: "questionmark.circle")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Search help")
                                    .popover(isPresented: $isSearchHelpPresented, arrowEdge: .top) {
                                        SearchHelpView()
                                    }

                                    sidebarToggle
                                }
                                .padding(12)

                                Divider()

                                FolderList(searchText: searchText)
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
                            QuickAccessBar()

                            if !sidebarVisible {
                                sidebarToggle
                                    .padding(12)
                            }

                            if workspaceStore.isShowingCredentials {
                                CredentialsManagerView()
                            } else if workspaceStore.isShowingCodexResult || !workspaceStore.openSSHConnections.isEmpty || !workspaceStore.openExternalWebLinks.isEmpty {
                                VStack(spacing: 0) {
                                    SessionTabBar()
                                    if workspaceStore.isShowingCodexResult {
                                        CodexResultPane()
                                    } else if let webLink = workspaceStore.activeExternalWebLink {
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
        .sheet(isPresented: $workspaceStore.isShowingTerminalCommandInput) {
            IncidentPromptView()
                .environmentObject(workspaceStore)
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
        .sheet(isPresented: $workspaceStore.isShowingTerminalCommandEditor) {
            TerminalCommandEditorForm()
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
        .sheet(isPresented: $workspaceStore.isShowingHelp) {
            GateTreeAboutView()
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

private struct SearchHelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Search Help", systemImage: "magnifyingglass")
                .font(.headline)

            Text("Use one or more words. Every word must match a name, address, or tag; matching ignores capitalization.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Examples")
                    .font(.subheadline.weight(.semibold))
                Text("• sauron fra api — all FRA Sauron APIs")
                Text("• sauron iad iad1 thanos — the IAD1 Thanos link")
                Text("• ssh giu icprod fra kafka — FRA Kafka servers")
                Text("• ssh ohai cernfr cache — CERN FR cache servers")
            }
            .font(.callout)

            Text("Tags include site, region, instance, and service or server role.")
                .font(.footnote)
                .foregroundStyle(.secondary)

        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
    }
}

private struct GateTreeAboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("About GateTree", systemImage: "tree")
                .font(.title2.weight(.semibold))

            Text("GateTree is a local macOS workspace for organizing SSH servers, credentials, commands, and operational web links in one connection tree.")
                .fixedSize(horizontal: false, vertical: true)

            Text("Built with Swift and SwiftUI for macOS.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Features").font(.headline)
                Text("• Folder-based SSH and web bookmark management")
                Text("• Native SSH session tabs and macOS Keychain credentials")
                Text("• Tags and multi-word search for sites, services, regions, and instances")
                Text("• Chrome tab tracking for SSO-protected operational links")
            }
            .font(.callout)

            Text("Created by Zsolt Karman")
                .font(.headline)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 470, alignment: .leading)
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
                            workspaceStore.isShowingCodexResult = false
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
                            workspaceStore.isShowingCodexResult = false
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
                if workspaceStore.isCodexRunning || !workspaceStore.codexResult.isEmpty {
                    HStack(spacing: 5) {
                        Button { workspaceStore.isShowingCodexResult = true } label: {
                            Label("Incident triage", systemImage: "sparkles").lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        if !workspaceStore.isCodexRunning {
                            Button { workspaceStore.closeCodexResult() } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.25))
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
                Text("GateTree keeps this bookmark selected while Chrome handles the sign-in session.")
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
        VStack(spacing: 0) {
            Label("Details", systemImage: "info.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            Divider()

            Group {
            if let connection = workspaceStore.selectedConnectionForInspector {
                VStack(alignment: .leading, spacing: 3) {
                    Label(connection.name, systemImage: "server.rack")
                        .font(.system(size: 12, weight: .medium))
                    InspectorRow(label: "Host", value: "\(connection.host):\(connection.port)")
                    InspectorRow(label: "User", value: workspaceStore.resolvedUsername(for: connection))
                    InspectorRow(label: "Credential", value: workspaceStore.credentialSummary(for: connection))
                    InspectorTags(tags: connection.tags)
                }
                .padding(8)
            } else if let webLink = workspaceStore.selectedWebLinkForInspector {
                VStack(alignment: .leading, spacing: 3) {
                    Label(webLink.name, systemImage: "globe")
                        .font(.system(size: 12, weight: .medium))
                    InspectorRow(label: "Type", value: "Web bookmark")
                    InspectorRow(label: "URL", value: webLink.url)
                    InspectorTags(tags: webLink.tags)
                }
                .padding(8)
            } else if let terminalCommand = workspaceStore.selectedTerminalCommandForInspector {
                VStack(alignment: .leading, spacing: 3) {
                    Label(terminalCommand.name, systemImage: "terminal")
                        .font(.system(size: 12, weight: .medium))
                    InspectorRow(label: "Type", value: "Terminal connection")
                    InspectorRow(label: "Command", value: terminalCommand.command)
                    InspectorRow(label: "Action", value: "Double-click opens a new Terminal window")
                    InspectorTags(tags: terminalCommand.tags)
                }
                .padding(8)
            } else if let folder = workspaceStore.selectedFolderForInspector {
                VStack(alignment: .leading, spacing: 3) {
                    Label(folder.name, systemImage: "folder.fill")
                        .font(.system(size: 12, weight: .medium))
                    InspectorRow(label: "Type", value: "Folder")
                    InspectorTags(tags: folder.tags)
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
}

private struct InspectorTags: View {
    let tags: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Text("Tags")
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(tags.isEmpty ? "—" : tags.joined(separator: ", "))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 10))
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

private func matchesSearch(_ values: [String], query: String) -> Bool {
    let terms = query
        .split(whereSeparator: { $0.isWhitespace })
        .map(String.init)
    guard !terms.isEmpty else { return true }

    return terms.allSatisfy { term in
        values.contains { $0.localizedCaseInsensitiveContains(term) }
    }
}

private func sshMatchesSearch(_ connection: SSHConnection, query: String) -> Bool {
    matchesSearch([connection.name, connection.host, connection.username, String(connection.port)] + connection.tags, query: query)
}

private func webLinkMatchesSearch(_ webLink: WebLink, query: String) -> Bool {
    matchesSearch([webLink.name, webLink.url] + webLink.tags, query: query)
}

private func terminalCommandMatchesSearch(_ terminalCommand: TerminalCommand, query: String) -> Bool {
    matchesSearch([terminalCommand.name, terminalCommand.command] + terminalCommand.tags, query: query)
}

private func folderMatchesSearch(_ folder: WorkspaceFolder, query: String) -> Bool {
    matchesSearch([folder.name] + folder.tags, query: query) ||
    folder.connections.contains { sshMatchesSearch($0, query: query) } ||
    folder.webLinks.contains { webLinkMatchesSearch($0, query: query) } ||
    folder.terminalCommands.contains { terminalCommandMatchesSearch($0, query: query) } ||
    folder.children.contains { folderMatchesSearch($0, query: query) }
}

private enum TreeNavigationItemKind {
    case folder
    case ssh
    case web
    case terminal
}

private struct TreeNavigationItem {
    let id: UUID
    let kind: TreeNavigationItemKind
    let parentFolderID: UUID?
    let hasChildren: Bool
}

private func treeNavigationItems(
    folders: [WorkspaceFolder],
    rootConnections: [SSHConnection],
    rootWebLinks: [WebLink],
    rootTerminalCommands: [TerminalCommand],
    expandedFolderIDs: Set<UUID>,
    searchText: String
) -> [TreeNavigationItem] {
    let isFiltering = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

    func matchingConnections(_ folder: WorkspaceFolder) -> [SSHConnection] {
        folder.connections.filter { !isFiltering || sshMatchesSearch($0, query: searchText) }
    }

    func matchingWebLinks(_ folder: WorkspaceFolder) -> [WebLink] {
        folder.webLinks.filter { !isFiltering || webLinkMatchesSearch($0, query: searchText) }
    }

    func matchingTerminalCommands(_ folder: WorkspaceFolder) -> [TerminalCommand] {
        folder.terminalCommands.filter { !isFiltering || terminalCommandMatchesSearch($0, query: searchText) }
    }

    func matchingChildren(_ folder: WorkspaceFolder) -> [WorkspaceFolder] {
        folder.children.filter { !isFiltering || folderMatchesSearch($0, query: searchText) }
    }

    func appendFolders(_ source: [WorkspaceFolder], parentFolderID: UUID?, into items: inout [TreeNavigationItem]) {
        for folder in source where !isFiltering || folderMatchesSearch(folder, query: searchText) {
            let connections = matchingConnections(folder)
            let webLinks = matchingWebLinks(folder)
            let terminalCommands = matchingTerminalCommands(folder)
            let children = matchingChildren(folder)
            let hasChildren = !connections.isEmpty || !webLinks.isEmpty || !terminalCommands.isEmpty || !children.isEmpty
            items.append(TreeNavigationItem(id: folder.id, kind: .folder, parentFolderID: parentFolderID, hasChildren: hasChildren))

            if isFiltering || expandedFolderIDs.contains(folder.id) {
                items.append(contentsOf: connections.map { TreeNavigationItem(id: $0.id, kind: .ssh, parentFolderID: folder.id, hasChildren: false) })
                items.append(contentsOf: webLinks.map { TreeNavigationItem(id: $0.id, kind: .web, parentFolderID: folder.id, hasChildren: false) })
                items.append(contentsOf: terminalCommands.map { TreeNavigationItem(id: $0.id, kind: .terminal, parentFolderID: folder.id, hasChildren: false) })
                appendFolders(children, parentFolderID: folder.id, into: &items)
            }
        }
    }

    var items: [TreeNavigationItem] = []
    appendFolders(folders, parentFolderID: nil, into: &items)
    items.append(contentsOf: rootConnections.filter { !isFiltering || sshMatchesSearch($0, query: searchText) }.map { TreeNavigationItem(id: $0.id, kind: .ssh, parentFolderID: nil, hasChildren: false) })
    items.append(contentsOf: rootWebLinks.filter { !isFiltering || webLinkMatchesSearch($0, query: searchText) }.map { TreeNavigationItem(id: $0.id, kind: .web, parentFolderID: nil, hasChildren: false) })
    items.append(contentsOf: rootTerminalCommands.filter { !isFiltering || terminalCommandMatchesSearch($0, query: searchText) }.map { TreeNavigationItem(id: $0.id, kind: .terminal, parentFolderID: nil, hasChildren: false) })
    return items
}

private struct FolderList: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    let searchText: String

    private var isFiltering: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasResults: Bool {
        workspaceStore.folders.contains { folderMatchesSearch($0, query: searchText) } ||
        workspaceStore.rootConnections.contains { sshMatchesSearch($0, query: searchText) } ||
        workspaceStore.rootWebLinks.contains { webLinkMatchesSearch($0, query: searchText) } ||
        workspaceStore.rootTerminalCommands.contains { terminalCommandMatchesSearch($0, query: searchText) }
    }
    private var navigationItems: [TreeNavigationItem] {
        treeNavigationItems(
            folders: workspaceStore.folders,
            rootConnections: workspaceStore.rootConnections,
            rootWebLinks: workspaceStore.rootWebLinks,
            rootTerminalCommands: workspaceStore.rootTerminalCommands,
            expandedFolderIDs: workspaceStore.expandedFolderIDs,
            searchText: searchText
        )
    }

    var body: some View {
        List {
            if isFiltering && !hasResults {
                ContentUnavailableView(
                    "No matches",
                    systemImage: "magnifyingglass",
                    description: Text("Try a connection name, host, URL or terminal command."))
            } else if workspaceStore.folders.isEmpty && workspaceStore.rootConnections.isEmpty && workspaceStore.rootWebLinks.isEmpty && workspaceStore.rootTerminalCommands.isEmpty {
                ContentUnavailableView(
                    "No folders",
                    systemImage: "folder",
                    description: Text("Use Connections → New Folder to start."))
            } else {
                ForEach(workspaceStore.folders.filter { !isFiltering || folderMatchesSearch($0, query: searchText) }) { folder in
                    FolderTreeRow(folder: folder, depth: 0, searchText: searchText)
                }
            }

            ForEach(workspaceStore.rootConnections.filter { !isFiltering || sshMatchesSearch($0, query: searchText) }) { connection in
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
                    .onDrag { treeItemProvider("ssh:\(connection.id.uuidString)") }
            }

            ForEach(workspaceStore.rootWebLinks.filter { !isFiltering || webLinkMatchesSearch($0, query: searchText) }) { webLink in
                WebLinkLabel(name: webLink.name, url: webLink.url)
                    .help(webLink.url)
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 6))
                    .listRowBackground(treeSelectionBackground(for: webLink.id))
                    .onTapGesture { workspaceStore.selectTreeItem(webLink.id) }
                    .onTapGesture(count: 2) { workspaceStore.selectWebLink(webLink) }
                    .contextMenu { webLinkMenu(webLink) }
                    .onDrag { treeItemProvider("web:\(webLink.id.uuidString)") }
            }

            ForEach(workspaceStore.rootTerminalCommands.filter { !isFiltering || terminalCommandMatchesSearch($0, query: searchText) }) { terminalCommand in
                TerminalCommandLabel(name: terminalCommand.name)
                    .help(terminalCommand.command)
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 6))
                    .listRowBackground(treeSelectionBackground(for: terminalCommand.id))
                    .onTapGesture { workspaceStore.selectTreeItem(terminalCommand.id) }
                    .onTapGesture(count: 2) { workspaceStore.launchTerminalCommand(terminalCommand) }
                    .contextMenu {
                        Button("Edit…") { workspaceStore.showTerminalCommandEditor(terminalCommand) }
                        Divider()
                        Button("Move to Trash", role: .destructive) { workspaceStore.moveTerminalCommandToTrash(terminalCommand.id) }
                    }
                    .onDrag { treeItemProvider("terminal:\(terminalCommand.id.uuidString)") }
            }

            Color.clear
                .frame(height: 1)
                .onDrop(of: [.text], delegate: FolderDropDelegate(targetFolderID: nil, store: workspaceStore))
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 18)
        .font(.system(size: 12, weight: .regular))
        .focusable()
        .onMoveCommand(perform: handleMoveCommand)
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

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard !navigationItems.isEmpty else { return }

        let selectedIndex = workspaceStore.selectedTreeItemID.flatMap { selectedID in
            navigationItems.firstIndex { $0.id == selectedID }
        }

        switch direction {
        case .up:
            let index = max(0, (selectedIndex ?? 1) - 1)
            workspaceStore.selectOnlyTreeItem(navigationItems[index].id)
        case .down:
            let index = min(navigationItems.count - 1, (selectedIndex ?? -1) + 1)
            workspaceStore.selectOnlyTreeItem(navigationItems[index].id)
        case .right:
            guard !isFiltering, let selectedIndex else { return }
            let item = navigationItems[selectedIndex]
            guard item.kind == .folder, item.hasChildren else { return }
            if !workspaceStore.isFolderExpanded(item.id) {
                workspaceStore.toggleFolderExpanded(item.id)
            } else if let child = navigationItems.dropFirst(selectedIndex + 1).first(where: { $0.parentFolderID == item.id }) {
                workspaceStore.selectOnlyTreeItem(child.id)
            }
        case .left:
            guard !isFiltering, let selectedIndex else { return }
            let item = navigationItems[selectedIndex]
            if item.kind == .folder, workspaceStore.isFolderExpanded(item.id) {
                workspaceStore.toggleFolderExpanded(item.id)
            } else if let parentFolderID = item.parentFolderID {
                workspaceStore.selectOnlyTreeItem(parentFolderID)
            }
        default:
            break
        }
    }

    @ViewBuilder
    private func webLinkMenu(_ webLink: WebLink) -> some View {
        Button("Edit…") { workspaceStore.showWebLinkEditor(webLink) }
        Button(workspaceStore.isQuickAccess(webLink) ? "Remove from Quick Access" : "Add to Quick Access") {
            workspaceStore.toggleQuickAccess(webLink)
        }
        Divider()
        Button("Move to Trash", role: .destructive) { workspaceStore.moveWebLinkToTrash(webLink.id) }
    }
}

private struct QuickAccessBar: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
                .font(.system(size: 11))

            if workspaceStore.quickAccessWebLinks.isEmpty {
                Text("Quick Access - right-click a URL and choose Add to Quick Access")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(workspaceStore.quickAccessWebLinks) { webLink in
                            Button {
                                workspaceStore.selectWebLink(webLink)
                            } label: {
                                Label(webLink.name, systemImage: "globe")
                                    .lineLimit(1)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 5)
                            }
                            .buttonStyle(.bordered)
                            .help(webLink.url)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        Divider()
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
                .keyboardShortcut(.defaultAction)
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

private struct IncidentPromptView: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Investigate incident")
                .font(.title2.weight(.semibold))
            Text("Paste the alert, Slack message, labels, and runbook context. GateTree will pass it to Codex.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $workspaceStore.terminalCommandInput)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 280)

            HStack {
                Button("Cancel") { workspaceStore.cancelTerminalCommandInput() }
                Spacer()
                Button("Start investigation") { workspaceStore.runTerminalCommandWithInput() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 720, height: 470)
    }
}

private struct CodexResultPane: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Incident triage", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Text(workspaceStore.codexStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if workspaceStore.isCodexRunning {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { workspaceStore.cancelCodexRun() }
                } else {
                    Button(action: workspaceStore.closeCodexResult) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(14)
            Divider()

            ScrollView {
                Text(workspaceStore.codexResult.isEmpty ? "Waiting for Codex output…" : workspaceStore.codexResult)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(18)
            }
        }
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
    let searchText: String

    private var isFiltering: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var matchingConnections: [SSHConnection] { folder.connections.filter { !isFiltering || sshMatchesSearch($0, query: searchText) } }
    private var matchingWebLinks: [WebLink] { folder.webLinks.filter { !isFiltering || webLinkMatchesSearch($0, query: searchText) } }
    private var matchingTerminalCommands: [TerminalCommand] { folder.terminalCommands.filter { !isFiltering || terminalCommandMatchesSearch($0, query: searchText) } }
    private var matchingChildren: [WorkspaceFolder] { folder.children.filter { !isFiltering || folderMatchesSearch($0, query: searchText) } }
    private var hasContents: Bool { !matchingChildren.isEmpty || !matchingConnections.isEmpty || !matchingWebLinks.isEmpty || !matchingTerminalCommands.isEmpty }
    private var isExpanded: Bool { isFiltering ? hasContents : workspaceStore.isFolderExpanded(folder.id) }

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
                            .foregroundStyle(isFiltering ? .tertiary : .secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                    .disabled(isFiltering)
                    .help(isFiltering ? "Clear search to change the folder expansion state." : "Expand or collapse folder")
                } else {
                    Color.clear.frame(width: 12, height: 1)
                }

                if folder.name == "Trash" && depth == 0 {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                } else {
                    Image("GateTreeFolder")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                }
                Text(folder.name)
            }
            .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .leading)
            .contentShape(Rectangle())
            .font(.system(size: 12, weight: .regular))
            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 6))
            .listRowBackground(workspaceStore.selectedTreeItemIDs.contains(folder.id) ? Color.accentColor.opacity(0.72) : .clear)
            .onTapGesture {
                workspaceStore.selectTreeItem(folder.id)
                if !isFiltering {
                    workspaceStore.toggleFolderExpanded(folder.id)
                }
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
                treeItemProvider("folder:\(folder.id.uuidString)")
            }
            .onDrop(of: [.text], delegate: FolderDropDelegate(targetFolderID: folder.id, store: workspaceStore))

            if isExpanded {
                ForEach(matchingConnections) { connection in
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
                        .onDrag {
                            treeItemProvider("ssh:\(connection.id.uuidString)")
                        }
                }
                ForEach(matchingWebLinks) { webLink in
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
                        Button(workspaceStore.isQuickAccess(webLink) ? "Remove from Quick Access" : "Add to Quick Access") {
                            workspaceStore.toggleQuickAccess(webLink)
                        }
                        Divider()
                        Button("Move to Trash", role: .destructive) { workspaceStore.moveWebLinkToTrash(webLink.id) }
                    }
                    .onDrag { treeItemProvider("web:\(webLink.id.uuidString)") }
                }
                ForEach(matchingTerminalCommands) { terminalCommand in
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
                    .onTapGesture(count: 2) { workspaceStore.launchTerminalCommand(terminalCommand) }
                    .contextMenu {
                        Button("Edit…") { workspaceStore.showTerminalCommandEditor(terminalCommand) }
                        Divider()
                        Button("Move to Trash", role: .destructive) { workspaceStore.moveTerminalCommandToTrash(terminalCommand.id) }
                    }
                    .onDrag { treeItemProvider("terminal:\(terminalCommand.id.uuidString)") }
                }
                ForEach(matchingChildren) { child in
                    FolderTreeRow(folder: child, depth: depth + 1, searchText: searchText)
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
        Button("Move to Trash", role: .destructive) { workspaceStore.moveSSHConnectionToTrash(connection.id) }
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

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }

        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let payload = value as? String else { return }

            DispatchQueue.main.async {
                let components = payload.split(separator: ":", maxSplits: 1).map(String.init)
                guard components.count == 2, let id = UUID(uuidString: components[1]) else { return }

                switch components[0] {
                case "folder":
                    store.moveFolder(id: id, into: targetFolderID)
                case "ssh":
                    store.moveSSHConnection(id: id, into: targetFolderID)
                case "web":
                    store.moveWebLink(id: id, into: targetFolderID)
                case "terminal":
                    store.moveTerminalCommand(id: id, into: targetFolderID)
                default:
                    break
                }
            }
        }
        return true
    }
}

private struct TagTextField: View {
    @Binding var tags: String

    var body: some View {
        TextField("Tags (comma separated)", text: $tags)
            .textFieldStyle(.roundedBorder)
            .help("Use commas to separate tags, for example: prod, iad, sauron")
    }
}

private struct FolderNameView: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var name = ""
    @State private var tags = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Folder")
                .font(.title2.weight(.semibold))

            TextField("Folder name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createFolder)
            TagTextField(tags: $tags)

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
        workspaceStore.createFolder(named: name, tags: tags.split(separator: ",").map(String.init))
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
            TagTextField(tags: $workspaceStore.editingFolderTags)
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
                    .keyboardShortcut(.defaultAction)
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
    @State private var tags = ""

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
            TagTextField(tags: $tags)
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
                    workspaceStore.createSSHConnection(name: name, host: host, username: username, port: portNumber, tags: tags.split(separator: ",").map(String.init))
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
    @State private var url = ""
    @State private var tags = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Web Link").font(.title2.weight(.semibold))
            TextField("Name (optional)", text: $name).textFieldStyle(.roundedBorder)
            TextField("URL", text: $url).textFieldStyle(.roundedBorder)
            TagTextField(tags: $tags)
            HStack {
                Button("Cancel") { workspaceStore.cancelWebLinkCreation() }
                Spacer()
                Button("Add Web Link") { workspaceStore.createWebLink(name: name, urlString: url, tags: tags.split(separator: ",").map(String.init)) }
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
    @State private var tags = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Terminal Connection").font(.title2.weight(.semibold))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            TextField("Command", text: $command).textFieldStyle(.roundedBorder)
            TagTextField(tags: $tags)
            Text("The command runs in a new Terminal window when you double-click this item.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { workspaceStore.cancelTerminalCommandCreation() }
                Spacer()
                Button("Add Terminal Connection") {
                    workspaceStore.createTerminalCommand(name: name, command: command, tags: tags.split(separator: ",").map(String.init))
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct TerminalCommandEditorForm: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var name = ""
    @State private var command = ""
    @State private var tags = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Terminal Connection").font(.title2.weight(.semibold))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            TextField("Command", text: $command).textFieldStyle(.roundedBorder)
            TagTextField(tags: $tags)
            HStack {
                Button("Cancel") { workspaceStore.cancelTerminalCommandEditor() }
                Spacer()
                Button("Save") { workspaceStore.updateTerminalCommand(name: name, command: command, tags: tags.split(separator: ",").map(String.init)) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            guard let terminalCommand = workspaceStore.editingTerminalCommand else { return }
            name = terminalCommand.name
            command = terminalCommand.command
            tags = terminalCommand.tags.joined(separator: ", ")
        }
    }
}

private struct WebLinkEditorForm: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var name = ""
    @State private var url = ""
    @State private var tags = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Web Link").font(.title2.weight(.semibold))
            TextField("Name (optional)", text: $name).textFieldStyle(.roundedBorder)
            TextField("URL", text: $url).textFieldStyle(.roundedBorder)
            TagTextField(tags: $tags)
            HStack {
                Button("Cancel") { workspaceStore.cancelWebLinkEditor() }
                Spacer()
                Button("Save") { workspaceStore.updateWebLink(name: name, urlString: url, tags: tags.split(separator: ",").map(String.init)) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            name = workspaceStore.editingWebLink?.name ?? ""
            url = workspaceStore.editingWebLink?.url ?? ""
            tags = workspaceStore.editingWebLink?.tags.joined(separator: ", ") ?? ""
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
    @State private var tags = ""

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
            TagTextField(tags: $tags)

            HStack {
                Button("Cancel") { workspaceStore.cancelSSHConnectionEditor() }
                Spacer()
                Button("Save") {
                    guard let portNumber = Int(port) else {
                        workspaceStore.errorMessage = "Enter a valid SSH port."
                        return
                    }
                    workspaceStore.updateSSHConnection(name: name, host: host, username: username, port: portNumber, credentialID: credentialID, tags: tags.split(separator: ",").map(String.init))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
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
                tags = connection.tags.joined(separator: ", ")
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
