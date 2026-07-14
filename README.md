# claude-swap

Switch [Claude Code](https://claude.com/claude-code)'s `~/.claude/settings.json`
between named **profiles** with one command — jump between your native Claude
subscription and an alternate provider (e.g. **Z.AI / GLM**) instantly.

```console
$ claude-swap
active: claude

profiles:
  * claude
    zai

$ claude-swap zai
✓ switched to zai  → /home/you/.claude/settings.json
  restart Claude Code / reload the window for env changes to take effect.
```

Each profile is a **complete** `settings.json` stored in
`~/.claude/profiles/<name>.json`. Switching copies the chosen profile over
`~/.claude/settings.json` (backing up the old one first). Works on **Linux,
macOS, and Windows**.

---

## Why

Claude Code reads provider/model/env config from `settings.json`. To point it
at a different backend (a proxy like Z.AI, a company gateway, a different model
default) you have to rewrite that file — and remember to put the original back.
`claude-swap` turns that into `claude-swap zai` / `claude-swap claude`, safely:

- **Atomic + validated** — the target profile is JSON-checked before it is
  installed; a bad profile never leaves you with a broken `settings.json`.
- **Automatic backups** — the previous `settings.json` is saved to
  `~/.claude/profiles/.backups/` (last 10 kept).
- **Drift detection** — `claude-swap status` warns if you hand-edited
  `settings.json` since the last swap, and `claude-swap save <name>` captures
  those edits back into the profile.
- **Secrets stay local** — real profiles (with API tokens) live under
  `~/.claude/`, never in this repo. Only sanitized `*.json.example` templates
  are committed.

## Install

### Linux / macOS

```bash
git clone https://github.com/chunnytechmate/claude-swap.git
cd claude-swap
./install.sh
```

Or one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/chunnytechmate/claude-swap/main/install.sh | bash
```

The installer is interactive and smart. It:

1. copies `claude-swap` to `~/.local/bin` (adding it to your PATH if needed),
2. imports your **current** `settings.json` as the `claude` profile,
3. **asks for your Z.AI API key**, shows a masked confirmation, and on `y`
   saves the `zai` profile — inheriting your `permissions` block (so
   `bypassPermissions` applies in Z.AI mode too),
4. prints the exact file path so you can edit it later.

```console
Enter your Z.AI API key (from https://z.ai — leave blank to skip): ******
Save key e66336…66Sq to the Z.AI profile? [y/N] y

✓ Z.AI profile saved successfully.
  File: /home/you/.claude/profiles/zai.json
  To edit later: claude-swap edit zai  (or open the file above)
```

Prefer non-interactive? Set the key up front: `ZAI_API_KEY=... ./install.sh`.

### Windows (PowerShell)

```powershell
git clone https://github.com/chunnytechmate/claude-swap.git
cd claude-swap
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Installs to `%LOCALAPPDATA%\claude-swap\bin`, adds it to your user PATH, and
writes a `claude-swap.cmd` shim so `claude-swap` just works in any new terminal.

## Using it

The installer already created both profiles. Run `claude-swap` with **no
arguments** to get an interactive picker — move with **↑/↓** (or `j`/`k`),
**Enter** to switch, **q** to cancel:

```text
Select a profile  (Up/Down or j/k, Enter to switch, q to cancel)
  > claude  (active)
    zai
```

The picker redraws with ANSI/VT escape sequences, which every modern terminal
(Windows Terminal, VS Code, ConPTY, all Linux/macOS terminals) interprets
natively. Or name the profile directly:

```bash
claude-swap zai       # use Z.AI / GLM
claude-swap claude    # back to native Claude
```

Skipped the key at install time (or want to change it later)?

```bash
claude-swap edit zai  # opens ~/.claude/profiles/zai.json in $EDITOR
```

## Updating

Update the tool in place from GitHub (works on Linux, macOS, and Windows):

```bash
claude-swap update
```

It replaces only the `claude-swap` program — your profiles and API keys are
never touched.

> After switching, **restart Claude Code** (or reload the IDE window) so the new
> `env` / model settings are picked up.

## Commands

| Command | What it does |
| --- | --- |
| `claude-swap` | interactive arrow-key picker (falls back to `status` when piped) |
| `claude-swap <name>` | switch to `<name>` (e.g. `zai`, `claude`) |
| `claude-swap list` | list profiles (`*` = active) |
| `claude-swap status` | active profile + drift check |
| `claude-swap which` | print active profile name only (scriptable) |
| `claude-swap save <name>` | save current `settings.json` into a profile |
| `claude-swap edit <name>` | open a profile in `$EDITOR` |
| `claude-swap update` | update claude-swap itself from GitHub |
| `claude-swap help` | usage |

## Shortcuts

The command is already short, but you can go shorter with a shell alias:

```bash
# ~/.bashrc / ~/.zshrc
alias cz='claude-swap zai'
alias cc='claude-swap claude'
alias cs='claude-swap status'
```

PowerShell (`$PROFILE`):

```powershell
function cz { claude-swap zai }
function cc { claude-swap claude }
function cs { claude-swap status }
```

## How it stores things

```
~/.claude/
├── settings.json                 # the live config Claude Code reads
└── profiles/
    ├── claude.json               # your profiles (complete settings.json each)
    ├── zai.json                  # (gitignored — contains your API token)
    ├── .active                   # name of the current profile
    └── .backups/                 # timestamped copies of previous settings.json
```

## Security

`claude-swap` is designed to be a minimal, auditable attack surface:

- **Zero dependencies** — one bash script / one PowerShell script. No npm, no
  pip, nothing to supply-chain.
- **Secrets never leave your machine.** API tokens live in
  `~/.claude/profiles/*.json` with `600` permissions (dir `700`); the repo
  ships only sanitized `*.json.example` templates and gitignores the rest.
  The installer reads your key without echoing it and never passes it through
  process arguments (where other local processes could briefly see it).
- **Hardened self-update.** `claude-swap update` fetches over **HTTPS only**
  with **TLS ≥ 1.2** enforced (redirects included), then must pass an
  integrity gate before anything is replaced: shebang/marker check, minimum
  size (anti-truncation), version marker, and a full **syntax parse**
  (`bash -n` / PowerShell `Parser`). The replacement itself is **atomic**
  (staged next to the target, then renamed) — a failed update can never brick
  the installed tool, and your profiles are never touched.
- **Path-traversal guard.** Profile names are validated
  (`[A-Za-z0-9][A-Za-z0-9._-]*`), so a name like `../../evil` can't read or
  write outside the profiles directory.
- **Safe switching.** Every switch validates JSON, backs up the previous
  `settings.json` (mode `600` — backups can contain tokens), and installs the
  new file atomically. A corrupt profile aborts with the live config untouched.
- `CLAUDE_SWAP_REPO_RAW` can point `update` at a fork/branch; non-HTTPS
  sources are refused unless this override is explicitly set, and a warning is
  printed when it is.

Found a vulnerability? Please open a GitHub issue (or contact the author
privately for anything sensitive).

## Notes

- **Profiles are whole files.** If your `claude` profile has a `permissions`
  block and your `zai` profile doesn't, switching to `zai` drops those
  permissions. Keep any settings you want in *both* modes in *both* profiles
  (or add them once and re-`save`).
- Override the config root for testing with `CLAUDE_SWAP_HOME=/path/to/.claude`.

## License

MIT — see [LICENSE](LICENSE).
