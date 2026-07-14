#!/usr/bin/env bash
#
# claude-swap installer (Linux / macOS)
#
# Smart install:
#   * copies the `claude-swap` binary to a bin dir on your PATH
#   * ensures that bin dir is on PATH (patches your shell rc if needed)
#   * creates ~/.claude/profiles/
#   * imports your current ~/.claude/settings.json as the `claude` profile
#     (only if you have no profiles yet)
#   * drops profile templates so you can create more
#
# Usage:
#   ./install.sh                 # normal install
#   curl -fsSL <raw-url>/install.sh | bash
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CLAUDE_DIR="${CLAUDE_SWAP_HOME:-$HOME/.claude}"
PROFILES_DIR="$CLAUDE_DIR/profiles"

# colors
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; D=$'\033[2m'; R=$'\033[0m'; else B=""; G=""; Y=""; D=""; R=""; fi
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$G" "$R" "$*"; }
warn() { printf '%s!%s %s\n' "$Y" "$R" "$*"; }

# --- 1. pick a bin dir on PATH -------------------------------------------
pick_bindir() {
  local candidates=("$HOME/.local/bin" "$HOME/bin")
  # prefer one already on PATH
  for d in "${candidates[@]}"; do
    case ":$PATH:" in *":$d:"*) printf '%s' "$d"; return;; esac
  done
  printf '%s' "${candidates[0]}"
}
BIN_DIR="${CLAUDE_SWAP_BIN:-$(pick_bindir)}"
mkdir -p "$BIN_DIR"

# --- 2. install the binary -----------------------------------------------
install -m 0755 "$REPO_DIR/bin/claude-swap" "$BIN_DIR/claude-swap"
ok "installed ${B}claude-swap${R} -> $BIN_DIR/claude-swap"

# --- 3. ensure BIN_DIR on PATH -------------------------------------------
on_path=false
case ":$PATH:" in *":$BIN_DIR:"*) on_path=true;; esac
if ! $on_path; then
  rc=""
  case "${SHELL##*/}" in
    zsh)  rc="$HOME/.zshrc" ;;
    bash) rc="$HOME/.bashrc" ;;
    *)    rc="$HOME/.profile" ;;
  esac
  line="export PATH=\"$BIN_DIR:\$PATH\""
  if [ -n "$rc" ] && ! grep -qsF "$line" "$rc" 2>/dev/null; then
    printf '\n# added by claude-swap installer\n%s\n' "$line" >> "$rc"
    warn "added $BIN_DIR to PATH in ${B}$rc${R} — run: ${B}source $rc${R} (or open a new shell)"
  fi
fi

# --- 4. profiles dir + smart import --------------------------------------
mkdir -p "$PROFILES_DIR"
have_profiles=false
for f in "$PROFILES_DIR"/*.json; do [ -e "$f" ] && { have_profiles=true; break; }; done

if ! $have_profiles && [ -f "$CLAUDE_DIR/settings.json" ]; then
  cp -p "$CLAUDE_DIR/settings.json" "$PROFILES_DIR/claude.json"
  printf 'claude' > "$PROFILES_DIR/.active"
  ok "imported current settings.json as the ${B}claude${R} profile"
fi

# drop templates for anything not already present (never overwrite)
for tpl in "$REPO_DIR"/profiles/*.json.example; do
  [ -e "$tpl" ] || continue
  base=$(basename "$tpl" .example)         # e.g. zai.json
  dest="$PROFILES_DIR/$base"
  if [ ! -e "$dest" ]; then
    cp "$tpl" "$dest.example"
    say "${D}  template available: $dest.example (fill in and rename to $base)${R}"
  fi
done

# --- 5. done -------------------------------------------------------------
say ""
ok "done."
say "Try:  ${B}claude-swap${R}            ${D}# status${R}"
say "      ${B}claude-swap zai${R}        ${D}# switch to Z.AI${R}"
say "      ${B}claude-swap claude${R}     ${D}# switch back to native Claude${R}"
if ! $on_path; then
  say ""
  warn "open a new terminal (or 'source' your shell rc) before the command is found."
fi
