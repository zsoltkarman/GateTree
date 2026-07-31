# GateTree

Native macOS workspace for organizing SSH hosts, credentials and operational
web links in one connection tree.

GateTree is a local-first, clean-room SwiftUI application. It is intended for
people who need a compact remote-management workspace on macOS without
spreading hosts, passwords and monitoring URLs across separate tools.

> Status: **early development**. The core SSH, credentials, folders and web
> bookmark workflows are usable; the file format and UI are still evolving.

## Features

- **Connection tree** with folders, drag and drop, rename, safe deletion and
  persistent selection / expansion state. Items can also be moved to Trash.
- **Tags and multi-word search** across folders, SSH connections, web
  bookmarks and terminal commands.
- **Embedded SSH sessions** using the system OpenSSH client and a native
  terminal view, with several open connections represented as tabs.
- **Terminal commands** for repeatable local operational tasks.
- **Credential inheritance** from folders to child folders and SSH
  connections, with multi-select assignment.
- **macOS Keychain integration** — only the credential name, username and an
  identifier are held in the workspace; passwords stay in Keychain.
- **Web bookmarks and Quick Access** for operational tools such as API,
  Grafana, Prometheus, Thanos and Shuttleproxy. Bookmarks can open in Chrome;
  GateTree can keep track of the corresponding Chrome tab and bring it to the
  foreground.
- **Incident triage** that passes supplied alert context to a locally installed
  Codex CLI in read-only mode and displays the result in an app tab.
- **Workspace protection** with plaintext or encrypted workspace modes,
  master-password setup/change, decryption and file export.
- **Native macOS interface** with a resizable sidebar, connection details,
  keyboard-aware multiple selection and contextual actions.

## Screenshots

Screenshots will be added once the first public preview is prepared. GateTree
currently provides a two-pane workspace: a compact connection tree on the
left and active SSH sessions or bookmark status on the right.

## Local data and security

The active workspace is deliberately local and not part of this repository:

`~/Library/Application Support/GateTree/Workspace.gatetree`

Credentials are kept in the macOS Keychain. The workspace only refers to them
by ID, so neither a password nor a private inventory should be committed.
`.gitignore` excludes workspaces, generated builds and developer-only helper
scripts for this reason.

If you export a workspace, treat that file as sensitive data. Use workspace
encryption and a strong master password when it contains connection metadata
that should not be readable at rest.

## System requirements

- macOS 14 (Sonoma) or later.
- Xcode 16 or later.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- Internet access for Swift Package Manager to download SwiftTerm on the
  first build.

## Build from source

```zsh
xcodegen generate
xcodebuild -project GateTree.xcodeproj \
  -scheme GateTree \
  -configuration Debug \
  -derivedDataPath .build-xcode build
open .build-xcode/Build/Products/Debug/GateTree.app
```

The generated project and `.build-xcode` directory are local build output and
are intentionally ignored by Git.

## Create a distributable DMG

```zsh
./build/package.sh v0.1.0
```

Without a configured Developer ID certificate this produces an ad-hoc signed
developer DMG in `.dist/`. For a public build, set `DEVELOPER_ID` and store an
Apple notarization profile named `GateTree-notary` (or set
`NOTARY_PROFILE`). The script then signs, notarizes and staples the DMG.

## Automated GitHub releases

Pushing a tag such as `v0.1.0` starts the GitHub Actions release workflow. It
builds a DMG and attaches it to a GitHub Release automatically. Without Apple
signing secrets the DMG is ad-hoc signed; it is useful for testing but will
not be trusted by Gatekeeper.

For signed, notarized public releases, configure these GitHub Actions secrets:

- `APPLE_DEVELOPER_ID` — the complete Developer ID Application identity.
- `APPLE_CERTIFICATE_BASE64` — base64-encoded `.p12` certificate including
  the private key.
- `APPLE_CERTIFICATE_PASSWORD` — password used for that `.p12`.
- `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_PRIVATE_KEY` — an
  App Store Connect API key for notarization.

The workflow imports the certificate only into the temporary GitHub runner
keychain and creates a temporary `GateTree-notary` profile from the API key.

## Roadmap

- RDP connections.
- Signed public preview builds and screenshots.
- Import assistants for common remote-manager exports, implemented from their
  documented formats rather than copied application code.

## License

[Apache-2.0](LICENSE).

## Credits / dependencies

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — terminal emulator
  used for embedded SSH sessions.
- Apple SwiftUI, AppKit, Security / Keychain Services and CryptoKit.
