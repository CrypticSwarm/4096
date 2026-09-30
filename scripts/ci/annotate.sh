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

log=$(mktemp)
trap 'rm -f "$log"' EXIT

"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

# Strip ANSI colors, then extract "severity<TAB>file<TAB>line<TAB>col<TAB>message":
#   /abs/or/rel/File.swift:12:5: error: message       (swiftc, swift-format)
#   ✘ Test foo() recorded an issue at File.swift:7:9: Expectation failed: ...
tab=$'\t'
esc=$'\033'
diagnostics=$(sed -e "s/${esc}\\[[0-9;]*m//g" "$log" | sed -nE \
    -e "s/^([^ :]+\\.swift):([0-9]+):([0-9]+): (error|warning): (.*)$/\\4${tab}\\1${tab}\\2${tab}\\3${tab}\\5/p" \
    -e "s/^.* recorded an issue.* at ([^ :]+\\.swift):([0-9]+):([0-9]+): (.*)$/error${tab}\\1${tab}\\2${tab}\\3${tab}\\4/p" |
    sort -u)

# Workflow-command escaping (data and property values).
escape_data() { local s=${1//%/%25}; s=${s//$'\r'/%0D}; printf '%s' "${s//$'\n'/%0A}"; }
escape_prop() { local s; s=$(escape_data "$1"); s=${s//:/%3A}; printf '%s' "${s//,/%2C}"; }

report=""
while IFS=$tab read -r severity file line col message; do
    [[ -n "$severity" ]] || continue
    # Swift Testing reports only the file name; find it in the repo.
    if [[ "$file" != */* ]]; then
        found=$(find . -name "$file" -not -path '*/.build/*' -print -quit)
        [[ -n "$found" ]] && file=$found
    fi
    file=${file#"$PWD"/}
    file=${file#./}
    echo "::${severity} file=$(escape_prop "$file"),line=${line},col=${col},title=$(escape_prop "$label")::$(escape_data "$message")"
    report+="- \`${file}:${line}:${col}\` ${severity}: ${message}"$'\n'
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
            sed -e "s/${esc}\\[[0-9;]*m//g" "$log" | tail -n 60
            echo '```'
            echo "</details>"
        fi
        echo
    } >>"$GITHUB_STEP_SUMMARY"
fi

exit "$status"
