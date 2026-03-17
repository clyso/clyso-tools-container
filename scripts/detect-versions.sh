#!/bin/bash
set -e

get_versions() {
    yq -o=json '.versions' "$1"
}

output() {
    local versions="$1"
    local count=$(echo "$versions" | jq 'length')
    
    [[ -n "$GITHUB_OUTPUT" ]] && {
        echo "versions=$(echo "$versions" | jq -c '.')" >> "$GITHUB_OUTPUT"
        echo "count=$count" >> "$GITHUB_OUTPUT"
    }
    
    echo "Building $count version(s): $versions" >&2
}

CURRENT=$(get_versions versions.yaml)

if [[ "${GITHUB_EVENT_NAME}" == "workflow_call" ]]; then
    echo "Triggered by external workflow - rebuilding all versions" >&2
    output "$CURRENT"
    exit 0
fi

if git diff HEAD~1 HEAD --name-only | grep -q "^Dockerfile$"; then
    echo "Dockerfile changed - rebuilding all" >&2
    output "$CURRENT"
    exit 0
fi

PREVIOUS=$(git show HEAD~1:versions.yaml 2>/dev/null | yq -o=json '.versions' || echo "[]")

NEW=$(jq -n --argjson c "$CURRENT" --argjson p "$PREVIOUS" '$c - $p')

if [[ "$(echo "$NEW" | jq 'length')" -eq 0 ]] && [[ "$PREVIOUS" == "[]" ]]; then
    echo "First time setup - building all" >&2
    output "$CURRENT"
else
    output "$NEW"
fi