#!/usr/bin/env bash
#
# Sign release artifacts with minisign so `claude-swap update` can verify them.
# See SIGNING.md for the full workflow. Requires the `minisign` tool.
#
#   scripts/sign-release.sh <path-to-your-minisign-private-key>
#
set -euo pipefail

KEY="${1:-}"
[ -n "$KEY" ] || { echo "usage: $0 <minisign-private-key-path>"; exit 1; }
[ -f "$KEY" ] || { echo "private key not found: $KEY"; exit 1; }
command -v minisign >/dev/null 2>&1 || { echo "minisign is not installed"; exit 1; }

cd "$(dirname "$0")/.."
for f in bin/claude-swap bin/claude-swap.ps1; do
  [ -f "$f" ] || { echo "missing $f"; exit 1; }
  rm -f "$f.minisig"
  # -S sign, -m message, -s secret key, -c trusted comment, -t untrusted comment (timestamp)
  minisign -Sm "$f" -s "$KEY" -c "claude-swap release"
  echo "signed $f -> $f.minisig"
done

echo
echo "Done. Commit the *.minisig files and tag the release."
