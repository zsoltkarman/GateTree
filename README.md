# GateTree

> One place for servers, desktops, and web.

GateTree is a local-first macOS workspace for organizing access to SSH hosts,
RDP desktops, and web tools in one tree.

## Status

Early foundation. The current app contains only the two-panel workspace shell.
Connection launchers, resource management, encrypted credential storage,
bookmark import, and sync are intentionally future work.

## Principles

- Local-first by default.
- SSH, RDP, and URLs are equal resource types.
- Credentials stay separate from the catalog and will use the macOS Keychain.
- No mRemoteNG or mRemoteNXT source code, icons, or configuration code is used.

## Build

```zsh
xcodegen generate
xcodebuild -project GateTree.xcodeproj -scheme GateTree -configuration Debug build
```

## License

Apache-2.0. See [LICENSE](LICENSE).
