#!/bin/bash
set -euo pipefail

pid=$1
destination=$2
staged=$3
work=$(dirname "$staged")
backup="$work/Previous.app"

[[ "$pid" =~ ^[0-9]+$ && -d "$destination" && -d "$staged" && ! -e "$backup" ]] || exit 1
lock="$destination.update-lock"
if ! mkdir "$lock"; then
    echo 'Another Convio installation is already in progress.' >&2
    exit 1
fi
trap 'rmdir "$lock" 2>/dev/null || true' EXIT
if (( pid > 1 )); then
    for ((attempt = 0; attempt < 60; attempt++)); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
        echo 'Convio did not quit; the existing installation was left untouched.' >&2
        exit 1
    fi
fi

mv "$destination" "$backup"
if ! mv "$staged" "$destination"; then
    mv "$backup" "$destination"
    echo 'Replacement failed; restored the previous app.' >&2
    exit 1
fi
if ! open -n "$destination"; then
    mv "$destination" "$staged"
    mv "$backup" "$destination"
    open -n "$destination" || true
    echo 'Relaunch failed; restored the previous app.' >&2
    exit 1
fi
echo "Updated Convio. Previous app retained at: $backup"
