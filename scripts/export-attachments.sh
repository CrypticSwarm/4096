#!/usr/bin/env bash
# Usage: scripts/export-attachments.sh <result.xcresult> <output-dir>
#
# Exports test attachments (e.g. UI test screenshots) from a result bundle and
# renames them from UUIDs to their attachment names: Xcode's suggested name
# ("<name>_<n>_<UUID>.png") without the "_<n>_<UUID>" part, so names are
# stable across runs. A name used twice keeps Xcode's suggested name.
# Characters that artifact uploads reject (such as quotes in the names of
# XCTest's automatic failure attachments) become "_".
# Requires Xcode 16+ and jq (bundled with macOS 15+).
set -euo pipefail

result=$1
out=$2

rm -rf "$out"
if [[ ! -d "$result" ]]; then
    echo "No result bundle at $result; nothing to export." >&2
    exit 0
fi
mkdir -p "$out"
xcrun xcresulttool export attachments --path "$result" --output-path "$out"

manifest="$out/manifest.json"
if [[ -f "$manifest" ]]; then
    jq -r '.[].attachments[] | [.exportedFileName, .suggestedHumanReadableName] | @tsv' "$manifest" |
        while IFS=$'\t' read -r exported suggested; do
            [[ -n "$suggested" && -f "$out/$exported" ]] || continue
            suggested=$(printf '%s' "$suggested" | tr '"<>:|*?/\\\r\n' '_')
            name=$suggested
            if [[ $suggested =~ ^(.+)_[0-9]+_[0-9A-Fa-f-]{36}(\.[A-Za-z0-9]+)$ ]]; then
                name="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
            fi
            for candidate in "$name" "$suggested"; do
                if [[ ! -e "$out/$candidate" ]]; then
                    mv "$out/$exported" "$out/$candidate"
                    break
                fi
            done
        done
fi

find "$out" -type f ! -name manifest.json | sort
