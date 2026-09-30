#!/usr/bin/env bash
# Usage: scripts/ci/publish-screenshots.sh <dir>
#
# Commits the PNGs in <dir> to the ci-screenshots branch (an orphan branch
# holding nothing else) at <branch>/<short-sha>/<file>.png, so they can be
# viewed without a login at
#   https://raw.githubusercontent.com/<repo>/ci-screenshots/<branch>/<short-sha>/<file>.png
# where <file> is the attachment's name (see scripts/export-attachments.sh).
#
# Runs under GitHub Actions with GH_TOKEN set to a token with contents: write.
# It uses the Git Data API, so nothing is cloned and the branch's growing
# history is never downloaded. Concurrent runs race on the branch ref: a
# rejected (non-fast-forward) update is retried on top of the new tip. Pushes
# made with GITHUB_TOKEN don't trigger workflows. Best effort: on failure it
# prints a warning annotation and exits 0.
set -uo pipefail

dir=$1
repo=${GITHUB_REPOSITORY:?}
sha=${GITHUB_SHA:?}
branch=${GITHUB_REF_NAME:?}
target=ci-screenshots
prefix="${branch}/${sha:0:7}"

warn() {
    local message=${*//%/%25}
    message=${message//$'\r'/ }
    echo "::warning title=Publish screenshots::${message//$'\n'/ }"
    exit 0
}

shopt -s nullglob
files=("$dir"/*.png)
if [[ ${#files[@]} -eq 0 ]]; then
    echo "No screenshots in $dir; nothing to publish."
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Upload each file once as a blob; the tree entries refer to them by SHA.
for file in "${files[@]}"; do
    base64 <"$file" | tr -d '\n' | jq -Rs '{content: ., encoding: "base64"}' >"$work/blob.json"
    blob=""
    for attempt in 1 2 3; do
        blob=$(gh api "repos/$repo/git/blobs" --input "$work/blob.json" --jq .sha 2>"$work/error") && break
        blob=""
        [[ $attempt -lt 3 ]] && sleep $((attempt * 2))
    done
    [[ -n "$blob" ]] || warn "Could not upload $file: $(tail -c 300 "$work/error")"
    jq -n --arg path "$prefix/$(basename "$file")" --arg sha "$blob" \
        '{path: $path, mode: "100644", type: "blob", sha: $sha}' >>"$work/entries.jsonl"
done
jq -s . "$work/entries.jsonl" >"$work/entries.json" || warn "Could not build the tree entries"

# Commits the uploaded blobs on top of the branch's current tip (or as its
# first commit) and moves the branch there without forcing.
publish_once() {
    local tip base_tree="" tree commit
    # matching-refs returns an empty list rather than a 404 for a missing
    # branch, so a failed request isn't mistaken for "no branch yet".
    tip=$(gh api "repos/$repo/git/matching-refs/heads/$target" \
        --jq ".[] | select(.ref == \"refs/heads/$target\") | .object.sha") || return 1
    if [[ -n "$tip" ]]; then
        base_tree=$(gh api "repos/$repo/git/commits/$tip" --jq .tree.sha) || return 1
    fi
    tree=$(jq --arg base "$base_tree" '{tree: .} + (if $base == "" then {} else {base_tree: $base} end)' \
        "$work/entries.json" | gh api "repos/$repo/git/trees" --input - --jq .sha) || return 1
    commit=$(jq -n --arg message "Screenshots of $branch at $sha" --arg tree "$tree" --arg parent "$tip" \
        '{message: $message, tree: $tree, parents: (if $parent == "" then [] else [$parent] end)}' |
        gh api "repos/$repo/git/commits" --input - --jq .sha) || return 1
    if [[ -n "$tip" ]]; then
        gh api -X PATCH "repos/$repo/git/refs/heads/$target" -f sha="$commit" -F force=false >/dev/null
    else
        gh api "repos/$repo/git/refs" -f ref="refs/heads/$target" -f sha="$commit" >/dev/null
    fi
}

for attempt in 1 2 3 4 5; do
    if publish_once 2>"$work/error"; then
        url="https://github.com/$repo/tree/$target/$prefix"
        echo "::notice title=Screenshots::${#files[@]} published to $url"
        if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
            echo "Screenshots: $url" >>"$GITHUB_STEP_SUMMARY"
        fi
        exit 0
    fi
    echo "Attempt $attempt to update $target failed: $(cat "$work/error")" >&2
    [[ $attempt -lt 5 ]] && sleep $((attempt * 2))
done
warn "Could not update the $target branch after 5 attempts: $(tail -c 500 "$work/error")"
