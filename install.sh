#!/usr/bin/env bash
#
# claude-swap installer (Linux / macOS)
#
# Smart install:
#   * copies the `claude-swap` binary to a bin dir on your PATH
#   * ensures that bin dir is on PATH (patches your shell rc if needed)
#   * creates ~/.claude/profiles/
#   * imports your current ~/.claude/settings.json as the `claude` profile
#   * interactively sets up the `zai` profile: asks for your Z.AI API key,
#     confirms, then saves it (inheriting your permissions so bypassPermissions
#     carries over), and prints the exact path for future edits
#
# Non-interactive: set ZAI_API_KEY=... in the environment to skip the prompt.
#
# Usage:
#   ./install.sh
#   curl -fsSL <raw-url>/install.sh | bash
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CLAUDE_DIR="${CLAUDE_SWAP_HOME:-$HOME/.claude}"
PROFILES_DIR="$CLAUDE_DIR/profiles"

# colors
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; C=$'\033[36m'; D=$'\033[2m'; R=$'\033[0m'; else B=""; G=""; Y=""; C=""; D=""; R=""; fi
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$G" "$R" "$*"; }
warn() { printf '%s!%s %s\n' "$Y" "$R" "$*"; }
fail() { printf '%s✗%s %s\n' "$Y" "$R" "$*" >&2; exit 1; }

# --- 0. bootstrap: support `curl ... | bash` (no local checkout) ----------
# When piped, there is no repo next to us; fetch the needed files over
# enforced-https into a temp dir and install from there.
fetch() { # url dest
  if command -v curl >/dev/null 2>&1; then
    # default source: enforce https + TLS >= 1.2; explicit override may relax
    local -a f=(-fsSL --proto '=https' --tlsv1.2)
    [ -n "${CLAUDE_SWAP_REPO_RAW:-}" ] && f=(-fsSL)
    curl "${f[@]}" "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$2" "$1"
  else
    fail "need curl or wget"
  fi
}
if [ ! -f "$REPO_DIR/bin/claude-swap" ]; then
  RAW="${CLAUDE_SWAP_REPO_RAW:-https://raw.githubusercontent.com/chunnytechmate/claude-swap/main}"
  case "$RAW" in https://*) ;; *) [ -n "${CLAUDE_SWAP_REPO_RAW:-}" ] || fail "refusing non-https source: $RAW";; esac
  say "${D}no local checkout found — downloading from $RAW${R}"
  TMP_REPO=$(mktemp -d)
  trap 'rm -rf "$TMP_REPO"' EXIT
  mkdir -p "$TMP_REPO/bin" "$TMP_REPO/profiles"
  fetch "$RAW/bin/claude-swap"                "$TMP_REPO/bin/claude-swap"           || fail "download failed: bin/claude-swap"
  fetch "$RAW/profiles/zai.json.example"      "$TMP_REPO/profiles/zai.json.example" || fail "download failed: zai.json.example"
  fetch "$RAW/profiles/claude.json.example"   "$TMP_REPO/profiles/claude.json.example" || fail "download failed: claude.json.example"
  bash -n "$TMP_REPO/bin/claude-swap" || fail "downloaded claude-swap failed the syntax check — aborted"
  REPO_DIR="$TMP_REPO"
fi

# --- 1. pick a bin dir on PATH -------------------------------------------
pick_bindir() {
  local d
  for d in "$HOME/.local/bin" "$HOME/bin"; do
    case ":$PATH:" in *":$d:"*) printf '%s' "$d"; return;; esac
  done
  printf '%s' "$HOME/.local/bin"
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

# --- 4. profiles dir + import current settings as `claude` ---------------
mkdir -p "$PROFILES_DIR"
chmod 700 "$PROFILES_DIR" 2>/dev/null || true
if [ ! -e "$PROFILES_DIR/claude.json" ] && [ -f "$CLAUDE_DIR/settings.json" ]; then
  cp -p "$CLAUDE_DIR/settings.json" "$PROFILES_DIR/claude.json"
  chmod 600 "$PROFILES_DIR/claude.json" 2>/dev/null || true
  printf 'claude' > "$PROFILES_DIR/.active"
  ok "imported current settings.json as the ${B}claude${R} profile"
fi

# --- 5. smart Z.AI profile setup -----------------------------------------
# writes zai.json = template + your key + permissions inherited from the
# claude profile (so bypassPermissions applies in Z.AI mode too).
build_zai_json() {
  local key="$1" dest="$2" tpl="$REPO_DIR/profiles/zai.json.example"
  if command -v python3 >/dev/null 2>&1; then
    KEY="$key" TPL="$tpl" CLAUDEP="$PROFILES_DIR/claude.json" python3 - "$dest" <<'PY'
import json, os, sys
dest = sys.argv[1]
prof = json.load(open(os.environ['TPL']))
prof.setdefault('env', {})['ANTHROPIC_AUTH_TOKEN'] = os.environ['KEY']
cp = os.environ.get('CLAUDEP', '')
if cp and os.path.exists(cp):
    try:
        base = json.load(open(cp))
        # prefer the user's real permissions block (keeps additionalDirectories etc.)
        if isinstance(base.get('permissions'), dict):
            prof['permissions'] = base['permissions']
        if 'skipDangerousModePermissionPrompt' in base:
            prof['skipDangerousModePermissionPrompt'] = base['skipDangerousModePermissionPrompt']
    except Exception:
        pass
with open(dest, 'w') as f:
    json.dump(prof, f, indent=2)
    f.write('\n')
PY
  else
    # no python3: substitute in pure bash — never pass the key via argv,
    # where it would be briefly visible to other processes in `ps`
    local tpl_content
    tpl_content=$(cat "$tpl")
    printf '%s\n' "${tpl_content/PUT-YOUR-Z.AI-API-KEY-HERE/$key}" > "$dest"
  fi
}

setup_zai() {
  local dest="$PROFILES_DIR/zai.json"
  if [ -e "$dest" ]; then
    say "${D}  zai profile already exists — left untouched.${R}"
    return 0
  fi

  # key source: env var (non-interactive) or an interactive prompt on the tty.
  # open the terminal on fd 3 once; that both detects and gives us a tty to read.
  local key="${ZAI_API_KEY:-}" interactive=false tty_ok=false
  if { exec 3</dev/tty; } 2>/dev/null; then tty_ok=true; fi

  if [ -z "$key" ] && $tty_ok; then
    say ""
    printf '%sSet up the Z.AI profile now.%s\n' "$B" "$R"
    printf 'Enter your Z.AI API key %s(from https://z.ai — leave blank to skip)%s: ' "$D" "$R"
    read -r -s key <&3 || key=""
    printf '\n'
    interactive=true
  fi

  if [ -z "$key" ]; then
    $tty_ok && exec 3<&-
    cp "$REPO_DIR/profiles/zai.json.example" "$dest.example"
    warn "no key entered — template saved to ${B}$dest.example${R}"
    say "${D}  add your key later, then rename it to zai.json (or run: claude-swap edit zai)${R}"
    return 0
  fi

  # confirm before saving, but only for interactive entry (env var == intentional)
  if $interactive; then
    local masked ans
    if [ "${#key}" -gt 12 ]; then masked="${key:0:6}…${key: -4}"; else masked="********"; fi
    printf 'Save key %s%s%s to the Z.AI profile? [y/N] ' "$B" "$masked" "$R"
    read -r ans <&3 || ans=""
    case "$ans" in
      y|Y|yes|YES|Yes) ;;
      *) exec 3<&-; warn "cancelled — no key saved."; return 0 ;;
    esac
  fi
  $tty_ok && exec 3<&-

  build_zai_json "$key" "$dest"
  chmod 600 "$dest" 2>/dev/null || true
  say ""
  ok "Z.AI profile saved successfully."
  say "  ${B}File:${R} $dest"
  say "  ${D}To edit later: ${R}claude-swap edit zai${D}  (or open the file above)${R}"
}
setup_zai

# --- 6. done -------------------------------------------------------------
say ""
ok "Installation complete."
say "Try:  ${B}claude-swap${R}            ${D}# status${R}"
say "      ${B}claude-swap zai${R}        ${D}# switch to Z.AI / GLM${R}"
say "      ${B}claude-swap claude${R}     ${D}# switch back to native Claude${R}"
if ! $on_path; then
  say ""
  warn "open a new terminal (or 'source' your shell rc) before the command is found."
fi
