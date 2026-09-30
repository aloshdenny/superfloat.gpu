#!/bin/bash
# Rebuild the files stored as <name>.part-NNN (GitHub rejects files over
# 100 MB) and check every rebuilt file against SHA256SUMS.
#   ./join.sh
set -euo pipefail
cd "$(dirname "$0")"
find . -name '*.part-000' | sort | while read -r first; do
    f=${first%.part-000}
    cat "$f".part-[0-9][0-9][0-9] > "$f"
done
if command -v sha256sum >/dev/null; then
    sha256sum -c --quiet SHA256SUMS
else
    shasum -a 256 -c --quiet SHA256SUMS
fi
echo "rebuilt and verified $(wc -l < SHA256SUMS | tr -d ' ') files"
