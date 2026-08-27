// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private func treeItemProvider(_ payload: String) -> NSItemProvider {
    NSItemProvider(object: payload as NSString)
}

private extension View {
    /// Gives a double-click priority over a single-click selection. Keeping
    /// these gestures exclusive prevents List rows from consuming the second
    /// click as another selection instead of opening the selected item.
    func treeItemTap(
        onSingleClick: @escaping () -> Void,
        onDoubleClick: @escaping () -> Void
    ) -> some View {
        gesture(
            TapGesture(count: 2)
                .onEnded(onDoubleClick)
                .exclusively(before: TapGesture().onEnded(onSingleClick))
        )
    }
}

private struct KeePassDatabaseSelection {
    let path: String
    let bookmark: Data?
}

private func chooseKeePassDatabase(_ completion: @escaping (KeePassDatabaseSelection) -> Void) {
    let panel = NSOpenPanel()
    panel.title = "Select KeePass Database"
    panel.message = "Choose a KeePassXC .kdbx database."
    panel.allowedContentTypes = [UTType(filenameExtension: "kdbx")].compactMap { $0 }
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
        let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        completion(KeePassDatabaseSelection(path: url.path, bookmark: bookmark))
    }
}

struct ContentView: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var searchText = ""
    @State private var sidebarVisible = true
    @State private var sidebarWidth: CGFloat?
    @State private var sidebarDragStartWidth: CGFloat?
    @State private var isSearchHelpPresented = false
    @State private var didPrepareConnectionResources = false
    @State private var isPaneRailExpanded = false

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
                                        searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(searchText.isEmpty ? .tertiary : .secondary)
                                    .disabled(searchText.isEmpty)
                                    .help("Clear search")

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

                                SidebarConnections(
                                    searchText: searchText,
                                    treeHeight: sidebarTreeHeight
                                )

                                Divider()
                                SidebarNotes(searchText: searchText)

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
                            } else if workspaceStore.isShowingNotes {
                                NotesWorkspaceView(searchText: $searchText)
                            } else if workspaceStore.isShowingSSHUsernamePrompt || workspaceStore.isShowingRDPUsernamePrompt || workspaceStore.isShowingCodexResult || !workspaceStore.openSSHConnections.isEmpty || !workspaceStore.openRDPConnections.isEmpty || !workspaceStore.openExternalWebLinks.isEmpty {
                                ZStack(alignment: .trailing) {
                                    ZStack {
                                        if workspaceStore.isShowingCodexResult {
                                            CodexResultPane()
                                        }
                                        if let webLink = workspaceStore.activeExternalWebLink {
                                            ChromeLinkPane(webLink: webLink)
                                                .zIndex(2)
                                        }
                                        ForEach(workspaceStore.openSSHConnections) { connection in
                                                SSHSessionPane(
                                                    connection: connection,
                                                    password: workspaceStore.password(for: connection),
                                                    isActive: workspaceStore.activeSessionProtocol == .ssh && workspaceStore.activeSessionID == connection.id
                                                ) {
                                                    workspaceStore.closeSSHConnection(connection.id)
                                                }
                                                .opacity(workspaceStore.activeSessionProtocol == .ssh && workspaceStore.activeSessionID == connection.id ? 1 : 0)
                                                .allowsHitTesting(workspaceStore.activeSessionProtocol == .ssh && workspaceStore.activeSessionID == connection.id)
                                            }
                                        ForEach(workspaceStore.openRDPConnections) { connection in
                                                RDPConnectionPane(connection: connection, password: workspaceStore.rdpPassword(for: connection)) {
                                                    workspaceStore.closeRDPConnection(connection.id)
                                                }
                                                .opacity(workspaceStore.activeSessionProtocol == .rdp && workspaceStore.activeSessionID == connection.id ? 1 : 0)
                                                .allowsHitTesting(workspaceStore.activeSessionProtocol == .rdp && workspaceStore.activeSessionID == connection.id)
                                        }

                                        if workspaceStore.isShowingSSHUsernamePrompt {
                                            SSHUsernamePrompt()
                                                .zIndex(1)
                                        } else if workspaceStore.isShowingRDPUsernamePrompt || workspaceStore.isPromptingRDPPassword {
                                            RDPUsernamePrompt()
                                                .zIndex(1)
                                        }
                                    }
                                    PaneRail(isExpanded: $isPaneRailExpanded)
                                        .zIndex(10)
                                }
                                .onExitCommand {
                                    isPaneRailExpanded = false
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
        .sheet(isPresented: $workspaceStore.isShowingRDPConnectionCreation) {
            RDPConnectionForm()
                .environmentObject(workspaceStore)
        }
        .sheet(isPresented: $workspaceStore.isShowingRDPConnectionEditor) {
            RDPConnectionEditorForm()
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
            "Empty Trash?",
            isPresented: $workspaceStore.isShowingEmptyTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) {
                workspaceStore.emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All items in Trash will be permanently deleted. This cannot be undone.")
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
            Text("The KeePassXC credential reference will be removed from GateTree.")
        }
        .sheet(isPresented: $workspaceStore.isShowingHelp) {
            GateTreeAboutView()
        }
        .onAppear {
            prepareConnectionResourcesIfNeeded()
        }
        .onChange(of: workspaceStore.isUnlocked) { _ in
            prepareConnectionResourcesIfNeeded()
        }
    }

    private func prepareConnectionResourcesIfNeeded() {
        guard workspaceStore.isUnlocked, !didPrepareConnectionResources else { return }
        didPrepareConnectionResources = true
        DispatchQueue.main.async {
            workspaceStore.prepareConnectionResourcesAtLaunch()
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

            Text("Use one or more words. Every word must match a name, address, tag, or encrypted note title/content; matching ignores capitalization.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Examples")
                    .font(.subheadline.weight(.semibold))
                Text("• region api — all API links for a region")
                Text("• region monitoring — a monitoring link for a region")
                Text("• production kafka — Kafka servers in production")
                Text("• europe cache — Cache servers in Europe")
            }
            .font(.callout)

            Text("Tags include site, region, instance, and service or server role.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Label("Use the × button beside the search field to clear the current search.", systemImage: "xmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Label("Search results are grouped by their folder path, so repeated names remain easy to distinguish.", systemImage: "rectangle.3.group")
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
            Label("GateTree Help", systemImage: "tree")
                .font(.title2.weight(.semibold))

            Text("GateTree is a local macOS workspace for organizing SSH and RDP connections, credentials, commands, and operational web links in one connection tree.")
                .fixedSize(horizontal: false, vertical: true)

            Text("Built with Swift and SwiftUI for macOS.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(AppBuildInfo.aboutDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Working with GateTree").font(.headline)
                Text("• Double-click an SSH connection to open it in a session tab.")
                Text("• In an SSH session, drag with the left mouse button to select and copy text. Right-click the terminal for Copy and Paste; use Shift-right-click to send a mouse event to a remote terminal application.")
                Text("• Double-click an RDP connection to open a separate embedded RDP tab. It stays open alongside SSH session tabs; Terminal and X11 are not used.")
                Text("• For RDP, assign a KeePassXC credential or enter a username and masked password in the tab. Paste is supported. Use DOMAIN\\username, or fill Username and Domain separately.")
                Text("• Double-click a URL or select it from Quick Access to open or focus its Google Chrome tab.")
                Text("• Choose a bookmark icon when creating or editing a URL; the selected icon is saved with that bookmark.")
                Text("• Right-click a URL and choose Add to Quick Access to pin it to the top bar.")
                Text("• Drag Quick Access items left or right to set their saved order.")
                Text("• Use the search field to filter by name, address, or tag. Results are grouped by folder path, so repeated service names remain distinguishable; the × icon clears the search.")
                Text("• Right-click a folder and choose New Folder to create a child folder. The destination folder stays expanded so the new item remains visible.")
                Text("• Right-click an item and choose Move to Trash. Right-click Trash and choose Empty Trash… to permanently delete its contents.")
                Text("• Notes are available from the sidebar above Applications and are stored only inside an encrypted workspace. Select Notes in a plaintext workspace to start encryption setup.")
                Text("• Use + for a new note and the folder+ button for a one-level note folder. Right-click Root notes or a folder to create a note there; right-click a folder to rename or safely delete it. Deleting a folder moves its notes to Root notes.")
                Text("• Right-click a note to open or delete it. Drag a note onto Root notes or another note folder to move it. The note editor preserves literal text such as ------ for commands and separators.")
                Text("• Save writes the encrypted note and closes its editor; the note remains in the list.")
                Text("• KeePassXC credential references can be inherited by child SSH and RDP connections.")
                Text("• When creating a KeePassXC credential, choose the .kdbx file and enter the entry path: its group path plus entry title. A copied full Group Path (for example /Operations/...) or a root-relative path both work.")
            }
            .font(.callout)

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

/// A compact, overlaying switcher for the open panes.  It deliberately lives
/// in the ZStack above the terminal, so expanding it never changes the size
/// of a live SSH/RDP session.
private struct PaneRail: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @Binding var isExpanded: Bool
    @State private var searchText = ""

    private enum PaneCategory: String, CaseIterable, Identifiable {
        case ssh, rdp, thanos, grafana, confluence, jira, scm, dashboards, web

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ssh: "SSH"
            case .rdp: "RDP"
            case .thanos: "Thanos"
            case .grafana: "Grafana"
            case .confluence: "Confluence"
            case .jira: "Jira"
            case .scm: "SCM"
            case .dashboards: "Dashboards"
            case .web: "Web"
            }
        }

        var icon: String {
            switch self {
            case .ssh: "terminal"
            case .rdp: "display"
            case .thanos: "chart.line.uptrend.xyaxis"
            case .grafana: "gauge.with.dots.needle.50percent"
            case .confluence: "text.alignleft"
            case .jira: "diamond.fill"
            case .scm: "arrow.triangle.branch"
            case .dashboards: "rectangle.3.group.fill"
            case .web: "globe"
            }
        }

        var color: Color {
            switch self {
            case .ssh: .green
            case .rdp: .blue
            case .thanos: .purple
            case .grafana: .orange
            case .confluence: .cyan
            case .jira: .indigo
            case .scm: .teal
            case .dashboards: .mint
            case .web: .secondary
            }
        }
    }

    private var visibleCategories: [PaneCategory] {
        PaneCategory.allCases.filter { count(for: $0) > 0 }
    }

    private func count(for category: PaneCategory) -> Int {
        switch category {
        case .ssh: return sshConnections.count
        case .rdp: return rdpConnections.count
        default: return webLinks(for: category).count
        }
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func matchesSearch(_ values: [String]) -> Bool {
        normalizedSearch.isEmpty || values.joined(separator: " ").lowercased().contains(normalizedSearch)
    }

    private var sshConnections: [SSHConnection] {
        workspaceStore.openSSHConnections.filter {
            matchesSearch([$0.name, $0.host] + $0.tags)
        }
    }

    private var rdpConnections: [SSHConnection] {
        workspaceStore.openRDPConnections.filter {
            matchesSearch([$0.name, $0.host] + $0.tags)
        }
    }

    private var hasMatchingTools: Bool {
        (workspaceStore.isCodexRunning || !workspaceStore.codexResult.isEmpty)
            && matchesSearch(["Incident triage", "Tools"])
    }

    private func webLinks(for category: PaneCategory) -> [WebLink] {
        workspaceStore.openExternalWebLinks.filter { webLink in
            let searchable = ([webLink.name, webLink.url] + webLink.tags)
                .joined(separator: " ")
                .lowercased()
            guard normalizedSearch.isEmpty || searchable.contains(normalizedSearch) else { return false }
            return primaryWebCategory(for: webLink) == category
        }
    }

    /// A web page can legitimately mention multiple technologies (for example
    /// a Grafana dashboard backed by Thanos).  Give it one predictable home
    /// instead of rendering the same open pane in multiple sections.
    private func primaryWebCategory(for webLink: WebLink) -> PaneCategory {
        let searchable = ([webLink.name, webLink.url] + webLink.tags)
            .joined(separator: " ")
            .lowercased()
        if searchable.contains("github") || searchable.contains("gitlab") || searchable.contains("bitbucket") || searchable.contains("scm") { return .scm }
        if searchable.contains("confluence") { return .confluence }
        if searchable.contains("jira") { return .jira }
        if searchable.contains("grafana") { return .grafana }
        if searchable.contains("thanos") { return .thanos }
        if searchable.contains("dashboard") { return .dashboards }
        return .web
    }

    var body: some View {
        HStack(spacing: 0) {
            if isExpanded {
                paneList
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            rail
        }
        .frame(maxHeight: .infinity, alignment: .trailing)
        .animation(.easeInOut(duration: 0.16), value: isExpanded)
        .shadow(color: .black.opacity(isExpanded ? 0.18 : 0.08), radius: isExpanded ? 8 : 3, x: -2, y: 0)
    }

    private var rail: some View {
        VStack(spacing: 8) {
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide open panes" : "Show open panes")

            if !visibleCategories.isEmpty {
                Divider()

                ForEach(visibleCategories) { category in
                    Button {
                        isExpanded = true
                    } label: {
                        railIcon(category)
                    }
                    .buttonStyle(.plain)
                    .help("Open \(category.title) panes")
                }
            }

            Spacer()

            Button {
                isExpanded = false
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("Hide open panes")
        }
        .padding(.vertical, 8)
        .frame(minWidth: 42, maxWidth: 42, maxHeight: .infinity)
        .background(.bar)
        .overlay(alignment: .leading) { Divider() }
    }

    private func railIcon(_ category: PaneCategory) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: category.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(category.color)
                .frame(width: 30, height: 30)
            if count(for: category) > 0 {
                Text("\(count(for: category))")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(category.color, in: Capsule())
                    .offset(x: 3, y: -2)
            }
        }
    }

    private var paneList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Open panes")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isExpanded = false
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .help("Hide open panes")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search open panes", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear pane search")
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if visibleCategories.isEmpty && !hasMatchingTools {
                        ContentUnavailableView(
                            "No matching open panes",
                            systemImage: "magnifyingglass",
                            description: Text("Try a connection, service, URL, or tag."))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 28)
                    }

                    ForEach(visibleCategories) { category in
                        paneSection(category) {
                            if category == .ssh {
                                ForEach(sshConnections) { connection in
                                paneRow(
                                    title: connection.name,
                                    icon: category.icon,
                                    iconColor: category.color,
                                    isActive: workspaceStore.activeSessionProtocol == .ssh && workspaceStore.activeSessionID == connection.id,
                                    select: {
                                        workspaceStore.isShowingCodexResult = false
                                        workspaceStore.selectOpenSSHConnection(connection)
                                    },
                                    close: { workspaceStore.closeSSHConnection(connection.id) }
                                )
                                }
                            } else if category == .rdp {
                                ForEach(rdpConnections) { connection in
                                paneRow(
                                    title: connection.name,
                                    icon: category.icon,
                                    iconColor: category.color,
                                    isActive: workspaceStore.activeSessionProtocol == .rdp && workspaceStore.activeSessionID == connection.id,
                                    select: {
                                        workspaceStore.isShowingCodexResult = false
                                        workspaceStore.selectOpenRDPConnection(connection)
                                    },
                                    close: { workspaceStore.closeRDPConnection(connection.id) }
                                )
                                }
                            } else {
                                ForEach(webLinks(for: category)) { webLink in
                                paneRow(
                                    title: webLink.name,
                                    icon: category.icon,
                                    iconColor: category.color,
                                    isActive: workspaceStore.activeExternalWebLink?.id == webLink.id,
                                    select: {
                                        workspaceStore.isShowingCodexResult = false
                                        workspaceStore.selectOpenExternalWebLink(webLink)
                                    },
                                    close: { workspaceStore.closeExternalWebLink(webLink.id) }
                                )
                                }
                            }
                        }
                    }

                    if hasMatchingTools {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Tools  1", systemImage: "sparkles")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.purple)
                            paneRow(
                                title: "Incident triage",
                                icon: "sparkles",
                                iconColor: .purple,
                                isActive: workspaceStore.isShowingCodexResult,
                                select: { workspaceStore.isShowingCodexResult = true },
                                close: workspaceStore.isCodexRunning ? nil : { workspaceStore.closeCodexResult() }
                            )
                        }
                    }
                }
                .padding(10)
            }
        }
        .frame(minWidth: 280, maxWidth: 280, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .overlay(alignment: .leading) { Divider() }
    }

    private func paneSection<Content: View>(
        _ category: PaneCategory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("\(category.title)  \(count(for: category))", systemImage: category.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(category.color)
            content()
        }
    }

    private func paneRow(
        title: String,
        icon: String,
        iconColor: Color,
        isActive: Bool,
        select: @escaping () -> Void,
        close: (() -> Void)?
    ) -> some View {
        HStack(spacing: 7) {
            Button {
                select()
                isExpanded = false
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(iconColor)
                    Text(title)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if let close {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Close pane")
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(isActive ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
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
                        workspaceStore.activeSessionProtocol == .ssh && workspaceStore.activeSessionID == connection.id
                            ? Color.accentColor.opacity(0.25)
                            : Color.secondary.opacity(0.10)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                ForEach(workspaceStore.openRDPConnections) { connection in
                    HStack(spacing: 5) {
                        Button {
                            workspaceStore.isShowingCodexResult = false
                            workspaceStore.selectOpenRDPConnection(connection)
                        } label: {
                            Label(connection.name, systemImage: "rectangle.inset.filled")
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        Button { workspaceStore.closeRDPConnection(connection.id) } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(workspaceStore.activeSessionProtocol == .rdp && workspaceStore.activeSessionID == connection.id ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                ForEach(workspaceStore.openExternalWebLinks) { webLink in
                    HStack(spacing: 5) {
                        Button {
                            workspaceStore.isShowingCodexResult = false
                            workspaceStore.selectOpenExternalWebLink(webLink)
                        } label: {
                            WebLinkTitle(webLink: webLink)
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
                WebServiceIcon(icon: webLink.icon, size: 18)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SidebarConnections: View {
    let searchText: String
    let treeHeight: CGFloat
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                isExpanded.toggle()
            } label: {
                Label("Connections", systemImage: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.top, 6)

            if isExpanded {
                FolderList(searchText: searchText)
                    .frame(height: treeHeight - 30, alignment: .top)
            }
        }
    }
}

private struct SidebarNotes: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    let searchText: String

    private var matchingNotes: [WorkspaceNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return workspaceStore.notes }
        return workspaceStore.notes.filter {
            ($0.title + " " + $0.body).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Button {
            workspaceStore.showNotes()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: workspaceStore.storageMode == .encrypted ? "note.text" : "lock.fill")
                    .foregroundStyle(workspaceStore.storageMode == .encrypted ? .purple : .secondary)
                Text("Notes")
                if !workspaceStore.notes.isEmpty {
                    Text("\(searchText.isEmpty ? workspaceStore.notes.count : matchingNotes.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(workspaceStore.isShowingNotes ? Color.accentColor.opacity(0.22) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(workspaceStore.storageMode == .encrypted ? "Encrypted workspace notes" : "Notes require an encrypted workspace")
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
    }
}

private struct NotesWorkspaceView: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @Binding var searchText: String
    @State private var selectedID: UUID?
    @State private var selectedFolderID: UUID?
    @State private var title = ""
    @State private var bodyText = ""
    @State private var newFolderName = ""
    @State private var isAddingFolder = false
    @State private var isRenamingFolder = false
    @State private var renamingFolderID: UUID?
    @State private var renamingFolderName = ""

    private var selectedNote: WorkspaceNote? {
        workspaceStore.notes.first { $0.id == selectedID }
    }

    private var filteredNotes: [WorkspaceNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return workspaceStore.notes
            .filter { $0.folderID == selectedFolderID }
            .filter { query.isEmpty || ($0.title + " " + $0.body).localizedCaseInsensitiveContains(query) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Notes", systemImage: "lock.fill")
                        .font(.headline)
                        .foregroundStyle(.purple)
                    Spacer()
                    Button {
                        let note = WorkspaceNote(title: "Untitled note", body: "")
                        workspaceStore.createNote(title: note.title, body: note.body, folderID: selectedFolderID)
                        select(workspaceStore.notes.last)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New encrypted note")
                    Button {
                        isAddingFolder.toggle()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New note folder")
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                Text("Stored only in the encrypted workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)

                if isAddingFolder {
                    HStack(spacing: 6) {
                        TextField("Folder name", text: $newFolderName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addFolder() }
                        Button("Add") { addFolder() }
                            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 12)
                }

                VStack(alignment: .leading, spacing: 2) {
                    folderRow(title: "Root notes", icon: "tray.full", id: nil)
                    ForEach(workspaceStore.noteFolders) { folder in
                        folderRow(title: folder.name, icon: "folder", id: folder.id)
                    }
                }
                .padding(.horizontal, 6)

                Divider()

                // Do not use List(selection:) here: on macOS its focus and
                // drag recognizers can swallow the first click of a row.
                // These explicit buttons select on the very first click.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredNotes) { note in
                            Button {
                                select(note)
                            } label: {
                                Text(note.title.isEmpty ? "Untitled note" : note.title)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(selectedID == note.id ? Color.accentColor.opacity(0.72) : .clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .onDrag { noteItemProvider(note.id) }
                            .contextMenu {
                                Button("Open") {
                                    select(note)
                                }
                                Divider()
                                Button("Delete note", role: .destructive) {
                                    let nextNote = filteredNotes.first { $0.id != note.id }
                                    workspaceStore.deleteNote(note.id)
                                    if selectedID == note.id {
                                        select(nextNote)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }
                .background(Color.white)
                .onChange(of: selectedID) { _ in select(selectedNote) }
                .onChange(of: searchText) { _ in
                    if !filteredNotes.contains(where: { $0.id == selectedID }) {
                        select(filteredNotes.first)
                    }
                }
                .onChange(of: selectedFolderID) { _ in
                    select(filteredNotes.first)
                }
            }
            .frame(minWidth: 180, idealWidth: 210, maxWidth: 240, maxHeight: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if selectedNote != nil {
                    HStack {
                        TextField("Note title", text: $title)
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Button("Save") { saveDraft() }
                            .buttonStyle(.borderedProminent)
                        Button(role: .destructive) {
                            if let selectedID { workspaceStore.deleteNote(selectedID) }
                            select(workspaceStore.notes.last)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .help("Delete note")
                    }
                    PlainTextNoteEditor(text: $bodyText)
                        .padding(8)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    ContentUnavailableView(
                        "No note selected",
                        systemImage: "note.text",
                        description: Text("Create an encrypted note with the plus button."))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Rename note folder", isPresented: $isRenamingFolder) {
            TextField("Folder name", text: $renamingFolderName)
            Button("Cancel", role: .cancel) {
                renamingFolderID = nil
            }
            Button("Rename") {
                if let renamingFolderID {
                    workspaceStore.renameNoteFolder(renamingFolderID, to: renamingFolderName)
                }
                renamingFolderID = nil
            }
        } message: {
            Text("Folder names are unique within Notes.")
        }
        .onAppear { select(filteredNotes.first) }
    }

    private func select(_ note: WorkspaceNote?) {
        selectedID = note?.id
        title = note?.title ?? ""
        bodyText = note?.body ?? ""
    }

    private func saveDraft() {
        guard let selectedNote else { return }
        workspaceStore.updateNote(selectedNote, title: title, body: bodyText)
        // Saving is also the explicit "close note" action: the note remains
        // in the encrypted list, but its editor no longer occupies the pane.
        select(nil)
    }

    private func addFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        workspaceStore.createNoteFolder(name: name)
        if let folder = workspaceStore.noteFolders.last(where: { $0.name == name }) {
            selectedFolderID = folder.id
        }
        newFolderName = ""
        isAddingFolder = false
    }

    private func folderRow(title: String, icon: String, id: UUID?) -> some View {
        Button {
            selectedFolderID = id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                Spacer()
                Text("\(workspaceStore.notes.filter { $0.folderID == id }.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(selectedFolderID == id ? Color.accentColor.opacity(0.18) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onDrop(
            of: [.text],
            delegate: NoteFolderDropDelegate(folderID: id, workspaceStore: workspaceStore)
        )
        .contextMenu {
            Button("New note") {
                let note = WorkspaceNote(title: "Untitled note", body: "")
                workspaceStore.createNote(title: note.title, body: note.body, folderID: id)
                selectedFolderID = id
                select(workspaceStore.notes.last)
            }
            if let id {
                Divider()
                Button("Rename…") {
                    renamingFolderID = id
                    renamingFolderName = title
                    isRenamingFolder = true
                }
                Button("Delete folder", role: .destructive) {
                    workspaceStore.deleteNoteFolder(id)
                    if selectedFolderID == id { selectedFolderID = nil }
                }
            }
        }
    }

    private func noteItemProvider(_ id: UUID) -> NSItemProvider {
        NSItemProvider(object: "GateTreeNote:\(id.uuidString)" as NSString)
    }
}

/// AppKit's normal rich-text substitutions turn sequences such as `------`
/// into typography. Notes frequently contain shell commands and separators, so
/// keep their editor deliberately literal.
private struct PlainTextNoteEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.string = text
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else { return }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private struct NoteFolderDropDelegate: DropDelegate {
    let folderID: UUID?
    let workspaceStore: SecureWorkspaceStore

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let text = value as? String,
                  text.hasPrefix("GateTreeNote:"),
                  let noteID = UUID(uuidString: String(text.dropFirst("GateTreeNote:".count))) else { return }
            Task { @MainActor in
                workspaceStore.moveNote(noteID, to: folderID)
            }
        }
        return true
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
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    WebLinkTitle(webLink: webLink)
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
        let normalizedTerm = normalizedURLForSearch(term)
        return values.contains { value in
            value.localizedCaseInsensitiveContains(term) ||
            normalizedURLForSearch(value).localizedCaseInsensitiveContains(normalizedTerm)
        }
    }
}

private func normalizedURLForSearch(_ value: String) -> String {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowercasedValue = trimmedValue.lowercased()
    guard lowercasedValue.hasPrefix("http://") || lowercasedValue.hasPrefix("https://") else {
        return trimmedValue
    }

    return trimmedValue.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
}

private func sshMatchesSearch(_ connection: SSHConnection, query: String) -> Bool {
    matchesSearch([connection.name, connection.host, connection.username, connection.domain, connection.connectionType.rawValue, String(connection.port)] + connection.tags, query: query)
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
            if isFiltering {
                GroupedSearchResults(query: searchText)
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
                ConnectionLabel(connection: connection)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .help("\(connection.connectionType == .rdp ? "RDP" : "SSH"): \(connection.host):\(connection.port)")
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 6))
                    .listRowBackground(treeSelectionBackground(for: connection.id))
                    .treeItemTap(
                        onSingleClick: { workspaceStore.selectTreeItem(connection.id) },
                        onDoubleClick: {
                            if connection.connectionType == .rdp {
                                workspaceStore.launchRDPConnection(connection)
                            } else {
                                workspaceStore.selectSSHConnection(connection)
                            }
                        }
                    )
                    .contextMenu {
                        if connection.connectionType == .ssh {
                            Button("Edit…") { workspaceStore.showSSHConnectionEditor(connection) }
                        } else {
                            Button("Edit…") { workspaceStore.showRDPConnectionEditor(connection) }
                            Button("Open RDP") { workspaceStore.launchRDPConnection(connection) }
                        }
                        Divider()
                        Button("Delete…", role: .destructive) {
                            workspaceStore.showSSHConnectionDeletionConfirmation(connection)
                        }
                    }
                    .onDrag { treeItemProvider("ssh:\(connection.id.uuidString)") }
                    .onDrop(of: [.text], delegate: SSHConnectionDropDelegate(targetConnectionID: connection.id, store: workspaceStore))
            }

            ForEach(workspaceStore.rootWebLinks.filter { !isFiltering || webLinkMatchesSearch($0, query: searchText) }) { webLink in
                WebLinkTitle(webLink: webLink)
                    .help(webLink.url)
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 6))
                    .listRowBackground(treeSelectionBackground(for: webLink.id))
                    .treeItemTap(
                        onSingleClick: { workspaceStore.selectTreeItem(webLink.id) },
                        onDoubleClick: { workspaceStore.selectWebLink(webLink) }
                    )
                    .contextMenu { webLinkMenu(webLink) }
                    .onDrag { treeItemProvider("web:\(webLink.id.uuidString)") }
            }

            ForEach(workspaceStore.rootTerminalCommands.filter { !isFiltering || terminalCommandMatchesSearch($0, query: searchText) }) { terminalCommand in
                TerminalCommandLabel(name: terminalCommand.name)
                    .help(terminalCommand.command)
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 6))
                    .listRowBackground(treeSelectionBackground(for: terminalCommand.id))
                    .treeItemTap(
                        onSingleClick: { workspaceStore.selectTreeItem(terminalCommand.id) },
                        onDoubleClick: { workspaceStore.launchTerminalCommand(terminalCommand) }
                    )
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
                Button("Remote Desktop (RDP)") { workspaceStore.showRDPConnectionCreation() }
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

private struct SearchResultGroup: Identifiable {
    let id: String
    let title: String
    let path: String
    let connections: [SSHConnection]
    let webLinks: [WebLink]
    let terminalCommands: [TerminalCommand]
}

private func groupedSearchResults(
    folders: [WorkspaceFolder],
    rootConnections: [SSHConnection],
    rootWebLinks: [WebLink],
    rootTerminalCommands: [TerminalCommand],
    query: String
) -> [SearchResultGroup] {
    var groups: [SearchResultGroup] = []

    let rootConnections = rootConnections.filter { sshMatchesSearch($0, query: query) }
    let rootWebLinks = rootWebLinks.filter { webLinkMatchesSearch($0, query: query) }
    let rootTerminalCommands = rootTerminalCommands.filter { terminalCommandMatchesSearch($0, query: query) }
    if !rootConnections.isEmpty || !rootWebLinks.isEmpty || !rootTerminalCommands.isEmpty {
        groups.append(SearchResultGroup(id: "root", title: "Root", path: "Workspace", connections: rootConnections, webLinks: rootWebLinks, terminalCommands: rootTerminalCommands))
    }

    func appendGroups(_ folders: [WorkspaceFolder], path: [String]) {
        for folder in folders {
            let folderPath = path + [folder.name]
            let connections = folder.connections.filter { sshMatchesSearch($0, query: query) }
            let webLinks = folder.webLinks.filter { webLinkMatchesSearch($0, query: query) }
            let terminalCommands = folder.terminalCommands.filter { terminalCommandMatchesSearch($0, query: query) }
            if !connections.isEmpty || !webLinks.isEmpty || !terminalCommands.isEmpty {
                groups.append(SearchResultGroup(id: folder.id.uuidString, title: folder.name, path: folderPath.joined(separator: " / "), connections: connections, webLinks: webLinks, terminalCommands: terminalCommands))
            }
            appendGroups(folder.children, path: folderPath)
        }
    }
    appendGroups(folders, path: [])
    return groups
}

private struct GroupedSearchResults: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    let query: String

    private var groups: [SearchResultGroup] {
        groupedSearchResults(
            folders: workspaceStore.folders,
            rootConnections: workspaceStore.rootConnections,
            rootWebLinks: workspaceStore.rootWebLinks,
            rootTerminalCommands: workspaceStore.rootTerminalCommands,
            query: query
        )
    }

    var body: some View {
        if groups.isEmpty {
            ContentUnavailableView("No matches", systemImage: "magnifyingglass", description: Text("Try a connection name, host, URL or terminal command."))
        } else {
            ForEach(groups) { group in
                HStack(spacing: 6) {
                    Text(group.title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.10), in: Capsule())
                    Text(group.path)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .listRowInsets(EdgeInsets(top: 7, leading: 8, bottom: 3, trailing: 6))

                ForEach(group.connections) { connection in
                    HStack(spacing: 6) {
                        ConnectionLabel(connection: connection)
                        Spacer(minLength: 0)
                        Text(connection.host)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(height: 20)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .contentShape(Rectangle())
                    .listRowInsets(EdgeInsets(top: 1, leading: 14, bottom: 1, trailing: 6))
                    .listRowBackground(workspaceStore.selectedTreeItemIDs.contains(connection.id) ? Color.accentColor.opacity(0.72) : .clear)
                    .treeItemTap(
                        onSingleClick: { workspaceStore.selectTreeItem(connection.id) },
                        onDoubleClick: {
                            if connection.connectionType == .rdp {
                                workspaceStore.launchRDPConnection(connection)
                            } else {
                                workspaceStore.selectSSHConnection(connection)
                            }
                        }
                    )
                    .contextMenu {
                        if connection.connectionType == .rdp {
                            Button("Edit…") { workspaceStore.showRDPConnectionEditor(connection) }
                            Button("Open RDP") { workspaceStore.launchRDPConnection(connection) }
                        } else {
                            Button("Edit…") { workspaceStore.showSSHConnectionEditor(connection) }
                        }
                        Divider()
                        Button("Move to Trash", role: .destructive) {
                            workspaceStore.moveSSHConnectionToTrash(connection.id)
                        }
                    }
                }

                ForEach(group.webLinks) { webLink in
                    WebLinkTitle(webLink: webLink)
                        .frame(height: 20)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .contentShape(Rectangle())
                        .listRowInsets(EdgeInsets(top: 1, leading: 14, bottom: 1, trailing: 6))
                        .listRowBackground(workspaceStore.selectedTreeItemIDs.contains(webLink.id) ? Color.accentColor.opacity(0.72) : .clear)
                        .treeItemTap(
                            onSingleClick: { workspaceStore.selectTreeItem(webLink.id) },
                            onDoubleClick: { workspaceStore.selectWebLink(webLink) }
                        )
                }

                ForEach(group.terminalCommands) { command in
                    TerminalCommandLabel(name: command.name)
                        .frame(height: 20)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .contentShape(Rectangle())
                        .listRowInsets(EdgeInsets(top: 1, leading: 14, bottom: 1, trailing: 6))
                        .listRowBackground(workspaceStore.selectedTreeItemIDs.contains(command.id) ? Color.accentColor.opacity(0.72) : .clear)
                        .treeItemTap(
                            onSingleClick: { workspaceStore.selectTreeItem(command.id) },
                            onDoubleClick: { workspaceStore.launchTerminalCommand(command) }
                        )
                }
            }
        }
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
                                WebLinkTitle(webLink: webLink)
                                    .lineLimit(1)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 5)
                            }
                            .buttonStyle(.bordered)
                            .help(webLink.url)
                            .onDrag { treeItemProvider("quickaccess:\(webLink.id.uuidString)") }
                            .onDrop(of: [.text], delegate: QuickAccessDropDelegate(targetID: webLink.id, store: workspaceStore))
                        }
                        Color.clear
                            .frame(width: 14, height: 28)
                            .onDrop(of: [.text], delegate: QuickAccessDropDelegate(targetID: nil, store: workspaceStore))
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
                    Text("Credentials are resolved from KeePassXC; GateTree stores only the database path and entry path.")
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
                            Text("KeePassXC · \(credential.keepassEntryPath)")
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
    @State private var databasePath = ""
    @State private var databaseBookmark: Data?
    @State private var entryPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Credential")
                .font(.title2.weight(.semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("KeePass database (.kdbx)", text: $databasePath)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") {
                    chooseKeePassDatabase { selection in
                        databasePath = selection.path
                        databaseBookmark = selection.bookmark
                    }
                }
            }
            TextField("KeePass entry path (for example: Accounts/Operations/User/entry-title)", text: $entryPath)
                .textFieldStyle(.roundedBorder)
            Text("Use the group path plus the entry title — not the KeePass Username. GateTree accepts either the full path shown by KeePassXC or the root-relative path.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { workspaceStore.cancelCredentialCreation() }
                Spacer()
                Button("Add Credential") {
                    workspaceStore.createCredential(
                        name: name,
                        username: "",
                        databasePath: databasePath,
                        databaseBookmark: databaseBookmark,
                        entryPath: entryPath
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || databasePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    Text(credential.name).tag(Optional(credential.id))
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
    @State private var databasePath = ""
    @State private var databaseBookmark: Data?
    @State private var entryPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Credential")
                .font(.title2.weight(.semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("KeePass database (.kdbx)", text: $databasePath)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") {
                    chooseKeePassDatabase { selection in
                        databasePath = selection.path
                        databaseBookmark = selection.bookmark
                    }
                }
            }
            TextField("KeePass entry path (for example: Accounts/Operations/User/entry-title)", text: $entryPath)
                .textFieldStyle(.roundedBorder)
            Text("Use the group path plus the entry title — not the KeePass Username. The password stays in KeePassXC and is never saved by GateTree.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { workspaceStore.cancelCredentialEditor() }
                Spacer()
                Button("Save") {
                    workspaceStore.updateCredential(
                        name: name,
                        username: "",
                        databasePath: databasePath,
                        databaseBookmark: databaseBookmark,
                        entryPath: entryPath
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || databasePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
        .onAppear {
            name = workspaceStore.editingCredential?.name ?? ""
            databasePath = workspaceStore.editingCredential?.keepassDatabasePath ?? ""
            databaseBookmark = workspaceStore.editingCredential?.keepassDatabaseBookmark
            entryPath = workspaceStore.editingCredential?.keepassEntryPath ?? ""
        }
    }
}

private struct SSHConnectionLabel: View {
    let name: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "terminal")
                .frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
            Text(name)
        }
        .frame(height: 18)
    }
}

private struct ConnectionLabel: View {
    let connection: SSHConnection

    var body: some View {
        if connection.connectionType == .rdp {
            Label(connection.name, systemImage: "display")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
                .frame(height: 18)
        } else {
            SSHConnectionLabel(name: connection.name)
        }
    }
}

private extension WebLinkIcon {
    var iconName: String {
        switch self {
        case .icon1: return "diamond.fill"
        case .icon2: return "text.alignleft"
        case .icon3: return "rectangle.3.group.fill"
        case .icon4: return "chevron.left.forwardslash.chevron.right"
        case .icon5: return "bell.badge.fill"
        case .icon6: return "gauge.with.dots.needle.50percent"
        case .icon7: return "flame.fill"
        case .icon8: return "checkmark.seal"
        case .icon9: return "chart.xyaxis.line"
        case .icon10: return "arrow.triangle.branch"
        case .icon11: return "questionmark.circle.fill"
        case .icon12: return "globe"
        }
    }

    var color: Color {
        switch self {
        case .icon1: return Color(red: 0.0, green: 0.32, blue: 0.78)
        case .icon2: return Color(red: 0.09, green: 0.46, blue: 0.89)
        case .icon3: return .cyan
        case .icon4: return .indigo
        case .icon5: return .red
        case .icon6: return .orange
        case .icon7: return Color(red: 0.82, green: 0.18, blue: 0.08)
        case .icon8, .icon9: return .purple
        case .icon10: return .teal
        case .icon11: return .gray
        case .icon12: return .primary
        }
    }
}

private struct WebServiceIcon: View {
    let icon: WebLinkIcon
    var size: CGFloat = 13

    var body: some View {
        Image(systemName: icon.iconName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(icon.color)
    }
}

private struct WebLinkIconPicker: View {
    @Binding var icon: WebLinkIcon
    @State private var isPresented = false

    var body: some View {
        HStack {
            Text("Icon")
            Spacer()
            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 4) {
                    WebServiceIcon(icon: icon, size: 16)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 42, height: 22)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34)), count: 4), spacing: 6) {
                    ForEach(WebLinkIcon.allCases) { candidate in
                        Button {
                            icon = candidate
                            isPresented = false
                        } label: {
                            WebServiceIcon(icon: candidate, size: 17)
                                .frame(width: 30, height: 30)
                                .background(icon == candidate ? Color.accentColor.opacity(0.22) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(candidate.rawValue)
                    }
                }
                .padding(10)
            }
        }
    }
}

private struct WebLinkTitle: View {
    let webLink: WebLink

    var body: some View {
        HStack(spacing: 5) {
            WebServiceIcon(icon: webLink.icon)
            Text(webLink.name)
                .foregroundStyle(.primary)
        }
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
                WebServiceIcon(icon: webLink.icon)
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
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 1)
                }
        }
    }
}

private struct EmbeddedWebView: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        // Keep a loaded page visually distinct from GateTree in both light and
        // dark mode. Without an under-page colour WebKit can briefly (or for
        // transparent pages permanently) render as a black, blended surface.
        webView.underPageBackgroundColor = .textBackgroundColor
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
    @State private var isExpandedWhileFiltering = true

    private var isFiltering: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var matchingConnections: [SSHConnection] { folder.connections.filter { !isFiltering || sshMatchesSearch($0, query: searchText) } }
    private var matchingWebLinks: [WebLink] { folder.webLinks.filter { !isFiltering || webLinkMatchesSearch($0, query: searchText) } }
    private var matchingTerminalCommands: [TerminalCommand] { folder.terminalCommands.filter { !isFiltering || terminalCommandMatchesSearch($0, query: searchText) } }
    private var matchingChildren: [WorkspaceFolder] { folder.children.filter { !isFiltering || folderMatchesSearch($0, query: searchText) } }
    private var hasContents: Bool { !matchingChildren.isEmpty || !matchingConnections.isEmpty || !matchingWebLinks.isEmpty || !matchingTerminalCommands.isEmpty }
    private var isExpanded: Bool { isFiltering ? hasContents && isExpandedWhileFiltering : workspaceStore.isFolderExpanded(folder.id) }

    var body: some View {
        Group {
            HStack(spacing: 6) {
                TreeIndentation(depth: depth)
                if hasContents {
                    Button {
                        if isFiltering {
                            isExpandedWhileFiltering.toggle()
                        } else {
                            workspaceStore.toggleFolderExpanded(folder.id)
                        }
                    } label: {
                        Image(systemName: isExpanded ? "minus.square" : "plus.square")
                            .font(.system(size: 11))
                            .foregroundStyle(isFiltering ? .tertiary : .secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                    .help("Expand or collapse folder")
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
                if workspaceStore.isTrashFolder(folder) {
                    Button("Empty Trash…", role: .destructive) {
                        workspaceStore.showEmptyTrashConfirmation(folder)
                    }
                    .disabled(folder.children.isEmpty && folder.connections.isEmpty && folder.webLinks.isEmpty && folder.terminalCommands.isEmpty)
                } else {
                    Button("Edit…") {
                        workspaceStore.showFolderEditor(folder)
                    }
                    Divider()
                    Menu("New Connection") {
                        Button("Server (SSH)") { workspaceStore.showSSHConnectionCreation(in: folder) }
                        Button("Remote Desktop (RDP)") { workspaceStore.showRDPConnectionCreation(in: folder) }
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
            }
            .onDrag {
                treeItemProvider("folder:\(folder.id.uuidString)")
            }
            .onDrop(of: [.text], delegate: FolderDropDelegate(targetFolderID: folder.id, store: workspaceStore))
            .onChange(of: isFiltering) { _, isFiltering in
                if isFiltering {
                    isExpandedWhileFiltering = true
                }
            }

            if isExpanded {
                ForEach(matchingConnections) { connection in
                    HStack(spacing: 6) {
                        TreeIndentation(depth: depth + 1)
                        ConnectionLabel(connection: connection)
                    }
                        .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18, alignment: .leading)
                        .contentShape(Rectangle())
                        .help("\(connection.connectionType == .rdp ? "RDP" : "SSH"): \(connection.host):\(connection.port)")
                        .font(.system(size: 12, weight: .regular))
                        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 6))
                        .listRowBackground(workspaceStore.selectedTreeItemIDs.contains(connection.id) ? Color.accentColor.opacity(0.72) : .clear)
                        .treeItemTap(
                            onSingleClick: { workspaceStore.selectTreeItem(connection.id) },
                            onDoubleClick: {
                                if connection.connectionType == .rdp {
                                    workspaceStore.launchRDPConnection(connection)
                                } else {
                                    workspaceStore.selectSSHConnection(connection)
                                }
                            }
                        )
                        .contextMenu { connectionMenu(connection) }
                        .onDrag {
                            treeItemProvider("ssh:\(connection.id.uuidString)")
                        }
                        .onDrop(of: [.text], delegate: SSHConnectionDropDelegate(targetConnectionID: connection.id, store: workspaceStore))
                }
                ForEach(matchingWebLinks) { webLink in
                    HStack(spacing: 6) {
                        TreeIndentation(depth: depth + 1)
                        WebLinkTitle(webLink: webLink)
                    }
                    .frame(height: 18)
                    .help(webLink.url)
                    .font(.system(size: 12, weight: .regular))
                    .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 6))
                    .listRowBackground(workspaceStore.selectedTreeItemIDs.contains(webLink.id) ? Color.accentColor.opacity(0.72) : .clear)
                    .treeItemTap(
                        onSingleClick: { workspaceStore.selectTreeItem(webLink.id) },
                        onDoubleClick: { workspaceStore.selectWebLink(webLink) }
                    )
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
                    .treeItemTap(
                        onSingleClick: { workspaceStore.selectTreeItem(terminalCommand.id) },
                        onDoubleClick: { workspaceStore.launchTerminalCommand(terminalCommand) }
                    )
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
        if connection.connectionType == .rdp {
            Button("Edit…") { workspaceStore.showRDPConnectionEditor(connection) }
            Button("Open RDP") { workspaceStore.launchRDPConnection(connection) }
        } else {
            Button("Edit…") { workspaceStore.showSSHConnectionEditor(connection) }
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

private struct SSHConnectionDropDelegate: DropDelegate {
    let targetConnectionID: UUID
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
            guard let payload = value as? String,
                  payload.hasPrefix("ssh:"),
                  let id = UUID(uuidString: String(payload.dropFirst(4))) else { return }
            DispatchQueue.main.async {
                store.moveSSHConnection(id: id, before: targetConnectionID)
            }
        }
        return true
    }
}

private struct QuickAccessDropDelegate: DropDelegate {
    let targetID: UUID?
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
            guard let payload = value as? String,
                  let idString = payload.split(separator: ":", maxSplits: 1).last,
                  payload.hasPrefix("quickaccess:"),
                  let movedID = UUID(uuidString: String(idString)) else { return }
            DispatchQueue.main.async {
                store.reorderQuickAccess(movedID: movedID, before: targetID)
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
            .help("Use commas to separate tags, for example: prod, region, monitoring")
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
                    Text(credential.name).tag(Optional(credential.id))
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
    @State private var isLocalTunnelEnabled = false
    @State private var localTunnelPort = "13306"
    @State private var localTunnelHost = "127.0.0.1"
    @State private var localTunnelRemotePort = "3306"

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
                    Text(credential.name).tag(Optional(credential.id))
                }
            }
            TagTextField(tags: $tags)
            LocalTunnelFields(
                isEnabled: $isLocalTunnelEnabled,
                localPort: $localTunnelPort,
                remoteHost: $localTunnelHost,
                remotePort: $localTunnelRemotePort
            )
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
                    workspaceStore.createSSHConnection(name: name, host: host, username: username, port: portNumber, tags: tags.split(separator: ",").map(String.init), localTunnel: localTunnel)
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var localTunnel: SSHLocalTunnel? {
        guard isLocalTunnelEnabled else { return nil }
        return SSHLocalTunnel(localPort: Int(localTunnelPort) ?? 0, remoteHost: localTunnelHost.trimmingCharacters(in: .whitespacesAndNewlines), remotePort: Int(localTunnelRemotePort) ?? 0)
    }
}

private struct RDPConnectionForm: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var name = ""
    @State private var host = ""
    @State private var username = ""
    @State private var domain = ""
    @State private var port = "3389"
    @State private var credentialID: UUID?
    @State private var tags = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New RDP Connection").font(.title2.weight(.semibold))
            TextField("Name (optional)", text: $name).textFieldStyle(.roundedBorder)
            TextField("Host or IP address", text: $host).textFieldStyle(.roundedBorder)
            TextField("Username", text: $username).textFieldStyle(.roundedBorder)
            TextField("Domain (optional)", text: $domain).textFieldStyle(.roundedBorder)
            TextField("Port", text: $port).textFieldStyle(.roundedBorder)
            Picker("Credential", selection: $credentialID) {
                Text("Inherit from folder").tag(UUID?.none)
                ForEach(workspaceStore.credentials) { credential in
                    Text(credential.name).tag(Optional(credential.id))
                }
            }
            TagTextField(tags: $tags)
            Text("RDP opens in a GateTree tab. Assigned passwords are read from KeePassXC.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { workspaceStore.cancelRDPConnectionCreation() }
                Spacer()
                Button("Add RDP Connection") {
                    guard let portNumber = Int(port) else {
                        workspaceStore.errorMessage = "Enter a valid RDP port."
                        return
                    }
                    workspaceStore.createRDPConnection(name: name, host: host, username: username, domain: domain, port: portNumber, credentialID: credentialID, tags: tags.split(separator: ",").map(String.init))
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 390)
    }
}

private struct RDPConnectionEditorForm: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var name = ""
    @State private var host = ""
    @State private var username = ""
    @State private var domain = ""
    @State private var port = "3389"
    @State private var credentialID: UUID?
    @State private var tags = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit RDP Connection").font(.title2.weight(.semibold))
            TextField("Name (optional)", text: $name).textFieldStyle(.roundedBorder)
            TextField("Host or IP address", text: $host).textFieldStyle(.roundedBorder)
            TextField("Username", text: $username).textFieldStyle(.roundedBorder)
            TextField("Domain (optional)", text: $domain).textFieldStyle(.roundedBorder)
            TextField("Port", text: $port).textFieldStyle(.roundedBorder)
            Picker("Credential", selection: $credentialID) {
                Text("Inherit from folder").tag(UUID?.none)
                ForEach(workspaceStore.credentials) { credential in
                    Text(credential.name).tag(Optional(credential.id))
                }
            }
            TagTextField(tags: $tags)
            HStack {
                Button("Cancel") { workspaceStore.cancelRDPConnectionEditor() }
                Spacer()
                Button("Save") {
                    guard let portNumber = Int(port) else {
                        workspaceStore.errorMessage = "Enter a valid RDP port."
                        return
                    }
                    workspaceStore.updateRDPConnection(name: name, host: host, username: username, domain: domain, port: portNumber, credentialID: credentialID, tags: tags.split(separator: ",").map(String.init))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 390)
        .onAppear {
            guard let connection = workspaceStore.editingRDPConnection else { return }
            name = connection.name
            host = connection.host
            username = connection.username
            domain = workspaceStore.rdpDomainForEditor(connection)
            port = String(connection.port)
            credentialID = connection.credentialID
            tags = connection.tags.joined(separator: ", ")
        }
    }
}

private struct RDPUsernamePrompt: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @FocusState private var isUsernameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(workspaceStore.isPromptingRDPPassword ? "Enter your password:" : "Enter your username:")
                .foregroundStyle(.white)
                .font(.system(.body, design: .monospaced))
            Group {
                if workspaceStore.isPromptingRDPPassword {
                    SecureField("Password", text: $workspaceStore.promptedRDPPassword)
                        .textFieldStyle(.roundedBorder)
                        .foregroundStyle(.primary)
                        .onSubmit { workspaceStore.connectWithPromptedRDPPassword() }
                } else {
                    TextField("", text: $workspaceStore.promptedRDPUsername)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .onSubmit { workspaceStore.connectWithPromptedRDPUsername() }
                }
            }
            .focused($isUsernameFocused)
            .font(.system(.body, design: .monospaced))
            .padding(.top, 4)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            Text("Press Return to connect · Esc to cancel")
                .foregroundStyle(.white.opacity(0.55))
                .font(.system(.caption, design: .monospaced))
                .padding(.top, 12)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black)
        .onAppear { DispatchQueue.main.async { isUsernameFocused = true } }
        .onChange(of: workspaceStore.isPromptingRDPPassword) { _, _ in
            isUsernameFocused = false
            DispatchQueue.main.async { isUsernameFocused = true }
        }
        .onExitCommand { workspaceStore.cancelRDPUsernamePrompt() }
    }
}

private struct WebLinkForm: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @State private var name = ""
    @State private var url = ""
    @State private var tags = ""
    @State private var icon: WebLinkIcon = .icon12

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Web Link").font(.title2.weight(.semibold))
            TextField("Name (optional)", text: $name).textFieldStyle(.roundedBorder)
            TextField("URL", text: $url).textFieldStyle(.roundedBorder)
            WebLinkIconPicker(icon: $icon)
            TagTextField(tags: $tags)
            HStack {
                Button("Cancel") { workspaceStore.cancelWebLinkCreation() }
                Spacer()
                Button("Add Web Link") { workspaceStore.createWebLink(name: name, urlString: url, tags: tags.split(separator: ",").map(String.init), icon: icon) }
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
    @State private var icon: WebLinkIcon = .icon12

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Web Link").font(.title2.weight(.semibold))
            TextField("Name (optional)", text: $name).textFieldStyle(.roundedBorder)
            TextField("URL", text: $url).textFieldStyle(.roundedBorder)
            WebLinkIconPicker(icon: $icon)
            TagTextField(tags: $tags)
            HStack {
                Button("Cancel") { workspaceStore.cancelWebLinkEditor() }
                Spacer()
                Button("Save") { workspaceStore.updateWebLink(name: name, urlString: url, tags: tags.split(separator: ",").map(String.init), icon: icon) }
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
            icon = workspaceStore.editingWebLink?.icon ?? .icon12
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
    @State private var isLocalTunnelEnabled = false
    @State private var localTunnelPort = "13306"
    @State private var localTunnelHost = "127.0.0.1"
    @State private var localTunnelRemotePort = "3306"

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
                    Text(credential.name).tag(Optional(credential.id))
                }
            }
            TagTextField(tags: $tags)
            LocalTunnelFields(
                isEnabled: $isLocalTunnelEnabled,
                localPort: $localTunnelPort,
                remoteHost: $localTunnelHost,
                remotePort: $localTunnelRemotePort
            )

            HStack {
                Button("Cancel") { workspaceStore.cancelSSHConnectionEditor() }
                Spacer()
                Button("Save") {
                    guard let portNumber = Int(port) else {
                        workspaceStore.errorMessage = "Enter a valid SSH port."
                        return
                    }
                    workspaceStore.updateSSHConnection(name: name, host: host, username: username, port: portNumber, credentialID: credentialID, tags: tags.split(separator: ",").map(String.init), localTunnel: localTunnel)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            if let connection = workspaceStore.editingSSHConnection {
                name = connection.name
                host = connection.host
                username = connection.username
                port = String(connection.port)
                credentialID = connection.credentialID
                tags = connection.tags.joined(separator: ", ")
                if let tunnel = connection.localTunnel {
                    isLocalTunnelEnabled = true
                    localTunnelPort = String(tunnel.localPort)
                    localTunnelHost = tunnel.remoteHost
                    localTunnelRemotePort = String(tunnel.remotePort)
                }
            }
        }
    }

    private var localTunnel: SSHLocalTunnel? {
        guard isLocalTunnelEnabled else { return nil }
        return SSHLocalTunnel(localPort: Int(localTunnelPort) ?? 0, remoteHost: localTunnelHost.trimmingCharacters(in: .whitespacesAndNewlines), remotePort: Int(localTunnelRemotePort) ?? 0)
    }
}

private struct LocalTunnelFields: View {
    @Binding var isEnabled: Bool
    @Binding var localPort: String
    @Binding var remoteHost: String
    @Binding var remotePort: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Create local SSH tunnel", isOn: $isEnabled)
            if isEnabled {
                HStack {
                    Text("localhost:")
                    TextField("Local port", text: $localPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 82)
                    Text("→")
                    TextField("Remote host", text: $remoteHost)
                        .textFieldStyle(.roundedBorder)
                    TextField("Port", text: $remotePort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 66)
                }
                Text("The tunnel starts with this SSH session and closes with it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SSHUsernamePrompt: View {
    @EnvironmentObject private var workspaceStore: SecureWorkspaceStore
    @FocusState private var isUsernameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Enter your username (or press Return to use your SSH config):")
                .foregroundStyle(.white)
                .font(.system(.body, design: .monospaced))

            TextField("", text: $workspaceStore.promptedSSHUsername)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .font(.system(.body, design: .monospaced))
                .onSubmit { workspaceStore.connectWithPromptedSSHUsername() }
            .focused($isUsernameFocused)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)

            Text("Press Return to connect · Esc to cancel")
                .foregroundStyle(.white.opacity(0.55))
                .font(.system(.caption, design: .monospaced))
                .padding(.top, 12)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black)
        .onAppear {
            DispatchQueue.main.async {
                isUsernameFocused = true
            }
        }
        .onExitCommand { workspaceStore.cancelSSHUsernamePrompt() }
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

    private var validationMessage: String? {
        if !password.isEmpty && password.count < 8 {
            return "Use at least 8 characters for the master password."
        }
        if !confirmation.isEmpty && password != confirmation {
            return "The master passwords do not match."
        }
        return nil
    }

    private var canEncrypt: Bool {
        password.count >= 8 && password == confirmation
    }

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

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("At least 8 characters. Both fields must match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                .disabled(workspaceStore.isProcessing || !canEncrypt)
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
                .onSubmit { submit() }

            if workspaceStore.needsMasterPasswordSetup {
                SecureField("Confirm master password", text: $confirmation)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit() }
            }

            HStack {
                Spacer()
                Button(workspaceStore.needsMasterPasswordSetup ? "Create encrypted workspace" : "Unlock") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
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

    private func submit() {
        guard !workspaceStore.isProcessing, !password.isEmpty else { return }
        if workspaceStore.needsMasterPasswordSetup {
            guard !confirmation.isEmpty, password == confirmation else {
                workspaceStore.errorMessage = "The master passwords do not match."
                return
            }
            workspaceStore.createWorkspace(masterPassword: password)
        } else {
            workspaceStore.unlock(masterPassword: password)
        }
    }
}
