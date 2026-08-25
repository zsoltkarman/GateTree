# GateTree

Native macOS workspace for organizing SSH hosts, credentials and operational
web links in one connection tree.

GateTree is a local-first, clean-room SwiftUI application. It is intended for
people who need a compact remote-management workspace on macOS without
spreading hosts, passwords and monitoring URLs across separate tools.

> Status: **early development**. SSH, embedded RDP, credentials, folders and
> web bookmark workflows are usable; the file format and UI are still evolving.

## Features

- **Connection tree** with folders, drag and drop, rename, safe deletion and
  persistent selection / expansion state. Items can also be moved to Trash and
  permanently removed with **Empty Trash**.
- **Tags and multi-word search** across folders, SSH connections, web
  bookmarks and terminal commands, with a one-click clear control. Search
  results are grouped by their folder path, which keeps repeated names such as
  repeated service names readable across regions and environments.
- **Embedded SSH sessions** using the system OpenSSH client and a native
  terminal view, with several open connections represented as tabs.
- **Embedded RDP sessions** powered by FreeRDP. RDP opens in its own GateTree
  tab alongside SSH sessions — no Terminal or X11 client is launched. Mouse
  input and standard Unicode keyboard input are supported.
- **RDP credential prompts** when no KeePassXC credential is assigned. Password
  input is masked and can be pasted; it is kept only for the active session.
  Domain accounts may be entered as `DOMAIN\\username` or with separate
  Username and Domain fields.
- **Terminal commands** for repeatable local operational tasks.
- **Credential inheritance** from folders to child folders and SSH
  connections, with multi-select assignment.
- **KeePassXC credential integration** — the workspace stores only a credential
  name, `.kdbx` database path and entry path; usernames and passwords stay in
  KeePassXC and are read only when a session starts.
- **Web bookmarks and Quick Access** for operational tools. Bookmarks can open in Chrome;
GateTree can keep track of the corresponding Chrome tab and bring it to the
  foreground. Each bookmark stores its own selected icon.
- **Incident triage** that passes supplied alert context to a locally installed
  Codex CLI in read-only mode and displays the result in an app tab.
- **Workspace protection** with plaintext or encrypted workspace modes,
  master-password setup/change, decryption and file export.
- **Native macOS interface** with a resizable sidebar, connection details,
  keyboard-aware multiple selection and contextual actions.

## Screenshots

Screenshots will be added once the first public preview is prepared. GateTree
currently provides a two-pane workspace: a compact connection tree on the
left and active SSH/RDP sessions or bookmark status on the right.

## Local data and security

The active workspace is deliberately local and not part of this repository:

`~/Library/Application Support/GateTree/Workspace.gatetree`

Credentials are stored in KeePassXC. The workspace contains only their local
database and entry-path references, so neither a password nor a private
inventory should be committed. An entry path is its group path plus entry title
(for example `Accounts/Operations/User/entry-title`); GateTree also
accepts a full path copied from KeePassXC's Group Path column.
`.gitignore` excludes workspaces, generated builds and developer-only helper
scripts for this reason.

If you export a workspace, treat that file as sensitive data. Use workspace
encryption and a strong master password when it contains connection metadata
that should not be readable at rest.

## System requirements

- macOS 14 (Sonoma) or later.
- Xcode 16 or later.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- [FreeRDP 3](https://www.freerdp.com/) installed through Homebrew, including
  Homebrew OpenSSL 3: `brew install freerdp openssl@3`.
- Internet access for Swift Package Manager to download SwiftTerm on the
  first build.

## Build from source

```zsh
./build/generate-project.sh
xcodebuild -project GateTree.xcodeproj \
  -scheme GateTree \
  -configuration Debug \
  -derivedDataPath .build-xcode build
open .build-xcode/Build/Products/Debug/GateTree.app
```

The generated project and `.build-xcode` directory are local build output and
are intentionally ignored by Git.

`VERSION` is the single source of truth for the app's release version. The
project-generation helper reads it and supplies the matching marketing version
to XcodeGen.

## Create a distributable DMG

```zsh
./build/package.sh
```

Without a configured Developer ID certificate this produces an ad-hoc signed
developer DMG in `.dist/`. For a public build, set `DEVELOPER_ID` and store an
Apple notarization profile named `GateTree-notary` (or set
`NOTARY_PROFILE`). The script then signs, notarizes and staples the DMG.

## Automated GitHub releases

Pushing a tag matching `VERSION`, such as `v0.2.3`, starts the GitHub Actions
release workflow on a macOS 15 runner. It builds a DMG, attaches it to a
GitHub Release, and uploads a separate App Store-signed build to TestFlight.
Create a checked release tag with:

```zsh
./deploy/tag-release.sh
```

Without Apple signing secrets the DMG is ad-hoc signed; it is useful for
testing but will not be trusted by Gatekeeper.

For signed, notarized public releases, configure these GitHub Actions secrets:

- `APPLE_DEVELOPER_ID` — the complete Developer ID Application identity.
- `APPLE_CERTIFICATE_BASE64` — base64-encoded `.p12` certificate including
  the private key.
- `APPLE_CERTIFICATE_PASSWORD` — password used for that `.p12`.
- `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_PRIVATE_KEY` — an
  App Store Connect API key for notarization.

The workflow imports the certificate only into the temporary GitHub runner
keychain and creates a temporary `GateTree-notary` profile from the API key.

For TestFlight, create an `app-store` GitHub environment and add these
environment secrets:

- `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_PRIVATE_KEY` — App
  Store Connect API key details.

The TestFlight job uses Xcode cloud signing for the App Store archive, so the
Apple distribution certificates and provisioning profile remain managed by
Apple instead of being copied into CI.

The TestFlight build number is derived from the GitHub Actions run, so a
re-run receives a distinct build number. The App Store Connect record and App
ID must use `com.gatetree.app` under Apple team `PZ6YC7GM6J`.

## RDP notes

Create an RDP connection from the connection tree's contextual **New
Connection → Remote Desktop (RDP)** action. Double-click it, or select
**Open RDP**, to create its tab immediately. If no credential is assigned,
GateTree asks for the username and then the masked password inside that tab.

GateTree accepts certificates for the current RDP session so that headless
FreeRDP never attempts to prompt through standard input. Verify the target
host through your normal administrative process before connecting.

## Roadmap

- Signed public preview builds and screenshots.

## License

[Apache-2.0](LICENSE).

## Credits / dependencies

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — terminal emulator
  used for embedded SSH sessions.
- Apple SwiftUI, AppKit, Security and CryptoKit.
