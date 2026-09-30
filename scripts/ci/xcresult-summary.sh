#!/usr/bin/env bash
# Usage: scripts/ci/xcresult-summary.sh <result.xcresult> <xcodebuild.log> [attachments-dir]
#
# Prints a Markdown summary of an xcodebuild test run (counts, failing tests,
# build errors, exported attachments) for $GITHUB_STEP_SUMMARY. Used by
# `make ios-summary`. Requires Xcode 16+ (xcresulttool test-results) and jq.
set -uo pipefail

result=$1
log=$2
attachments=${3:-}

echo "### iOS tests"
echo

if [[ -d "$result" ]] && summary=$(xcrun xcresulttool get test-results summary --path "$result" --compact); then
    jq -r '
        "**Result: \(.result)** (\(.passedTests) passed, \(.failedTests) failed, \(.skippedTests) skipped of \(.totalTestCount))",
        "",
        "Device: \(.devicesAndConfigurations[0].device // {} | "\(.deviceName // "?") (\(.osVersion // "?"))")",
        (if (.testFailures | length) > 0 then
            "", "| Test | Failure |", "| --- | --- |",
            (.testFailures[] | "| `\(.targetName)/\(.testName)` | \(.failureText | gsub("\\|"; "\\|") | gsub("\n"; " ")) |")
        else empty end)
    ' <<<"$summary" || echo "(Could not parse the xcresult summary.)"
else
    echo "**No test results** (the build probably failed before tests ran)."
fi

errors=$(grep -s ': error: ' "$log" | sort -u | head -n 30)
if [[ -n "$errors" ]]; then
    echo
    echo "<details open><summary>Errors from xcodebuild</summary>"
    echo
    echo '```'
    echo "$errors"
    echo '```'
    echo "</details>"
fi

if [[ -n "$attachments" && -d "$attachments" ]]; then
    echo
    echo "Attachments (see the workflow run's artifacts):"
    find "$attachments" -type f \( -name '*.png' -o -name '*.jpeg' -o -name '*.jpg' \) -exec basename {} \; | sort | sed 's/^/- /'
fi
