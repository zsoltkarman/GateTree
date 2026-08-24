#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(tr -d '[:space:]' < "$root_dir/VERSION")"
tag="v$version"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Érvénytelen verzió a VERSION fájlban: $version" >&2
    exit 1
fi

cd "$root_dir"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "A release előtt commitold a követett fájlok módosításait." >&2
    exit 1
fi

git fetch origin main --tags

if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
    echo "A helyi commit nem egyezik az origin/main állapotával." >&2
    exit 1
fi

if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "A tag már létezik: $tag" >&2
    exit 1
fi

git tag -a "$tag" -m "GateTree $tag"
git push origin "$tag"

echo "macOS kiadás elindítva: $tag"
