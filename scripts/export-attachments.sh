#!/usr/bin/env bash
# Usage: scripts/export-attachments.sh <result.xcresult> <output-dir>
#
# Exports test attachments (e.g. UI test screenshots) from a result bundle and
# renames them from UUIDs to Xcode's suggested human-readable names.
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
            if [[ -n "$suggested" && -f "$out/$exported" && ! -e "$out/$suggested" ]]; then
                mv "$out/$exported" "$out/$suggested"
            fi
        done
fi

find "$out" -type f ! -name manifest.json | sort
