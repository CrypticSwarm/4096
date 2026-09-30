#!/usr/bin/env bash
# Usage: scripts/ci/annotate.sh <label> <command> [args...]
#
# Runs a command. Under GitHub Actions it also turns Swift compiler,
# swift-format and Swift Testing diagnostics in the command's output into
# check-run annotations and writes a short report to the job summary, so
# failures are visible without access to the raw logs. Elsewhere it just
# runs the command. Exits with the command's status.
set -uo pipefail

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <label> <command> [args...]" >&2
    exit 2
fi
label=$1
shift

if [[ "${GITHUB_ACTIONS:-}" != true ]]; then
    exec "$@"
fi

raw=$(mktemp)
log=$(mktemp)
trap 'rm -f "$raw" "$log"' EXIT

"$@" 2>&1 | tee "$raw"
status=${PIPESTATUS[0]}

# Strip ANSI colors and terminal hyperlinks (swiftc wraps diagnostic group names).
esc=$'\033'
sed -e "s/${esc}\\[[0-9;]*m//g" -e "s/${esc}\\]8;;[^${esc}]*${esc}\\\\//g" "$raw" >"$log"

# Extract "severity|file|line|col|message" separated by the ASCII unit
# separator (not a whitespace IFS, so an empty col survives `read`):
#   /abs/or/rel/File.swift:12:5: error: message       (swiftc, swift-format)
#   /abs/File.swift:12: error: Suite.test : XCTAssert… (XCTest on Linux)
#   ✘ Test foo() recorded an issue at File.swift:7:9: Expectation failed: ...
sep=$'\037'
diagnostics=$(sed -nE \
    -e "s/^([^ :]+\\.swift):([0-9]+):(([0-9]+):)? (error|warning): (.*)$/\\5${sep}\\1${sep}\\2${sep}\\4${sep}\\6/p" \
    -e "s/^.* recorded an issue.* at ([^ :]+\\.swift):([0-9]+):([0-9]+): (.*)$/error${sep}\\1${sep}\\2${sep}\\3${sep}\\4/p" \
    "$log" | sort -u)

# Workflow-command escaping (data and property values).
escape_data() { local s=${1//%/%25}; s=${s//$'\r'/%0D}; printf '%s' "${s//$'\n'/%0A}"; }
escape_prop() { local s; s=$(escape_data "$1"); s=${s//:/%3A}; printf '%s' "${s//,/%2C}"; }

report=""
while IFS=$sep read -r severity file line col message; do
    [[ -n "$severity" ]] || continue
    # Swift Testing reports only the file name; find it in the repo.
    if [[ "$file" != */* ]]; then
        found=$(find . -name "$file" -not -path '*/.build/*' -print -quit)
        [[ -n "$found" ]] && file=$found
    fi
    file=${file#"$PWD"/}
    file=${file#./}
    location="${file}:${line}${col:+:$col}"
    echo "::${severity} file=$(escape_prop "$file"),line=${line}${col:+,col=$col},title=$(escape_prop "$label")::$(escape_data "$message")"
    report+="- \`${location}\` ${severity}: ${message}"$'\n'
done <<<"$diagnostics"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        if [[ $status -eq 0 ]]; then
            echo "### ${label}: passed"
        else
            echo "### ${label}: FAILED (exit ${status})"
        fi
        if [[ -n "$report" ]]; then
            echo
            printf '%s' "$report" | head -n 50
        fi
        if [[ $status -ne 0 ]]; then
            echo
            echo "<details><summary>Last 60 lines of output</summary>"
            echo
            echo '```'
            tail -n 60 "$log"
            echo '```'
            echo "</details>"
        fi
        echo
    } >>"$GITHUB_STEP_SUMMARY"
fi

exit "$status"
