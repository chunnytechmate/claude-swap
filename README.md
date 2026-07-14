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
git clone https://github.com/<you>/claude-swap.git
cd claude-swap
./install.sh
```

Or one-liner (once it's on GitHub):

```bash
curl -fsSL https://raw.githubusercontent.com/<you>/claude-swap/main/install.sh | bash
```

The installer copies `claude-swap` to `~/.local/bin` (adding it to your PATH if
needed), creates `~/.claude/profiles/`, and imports your **current**
`settings.json` as the `claude` profile.

### Windows (PowerShell)

```powershell
git clone https://github.com/<you>/claude-swap.git
cd claude-swap
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Installs to `%LOCALAPPDATA%\claude-swap\bin`, adds it to your user PATH, and
writes a `claude-swap.cmd` shim so `claude-swap` just works in any new terminal.

## Setup your profiles

After install you'll have a `claude` profile (imported from your current
settings). Create the `zai` profile from the template:

```bash
cd ~/.claude/profiles
cp zai.json.example zai.json
$EDITOR zai.json          # paste your real Z.AI API key
```

Then:

```bash
claude-swap zai       # use Z.AI / GLM
claude-swap claude    # back to native Claude
```

> After switching, **restart Claude Code** (or reload the IDE window) so the new
> `env` / model settings are picked up.

## Commands

| Command | What it does |
| --- | --- |
| `claude-swap` | show active profile + list |
| `claude-swap <name>` | switch to `<name>` (e.g. `zai`, `claude`) |
| `claude-swap list` | list profiles (`*` = active) |
| `claude-swap status` | active profile + drift check |
| `claude-swap which` | print active profile name only (scriptable) |
| `claude-swap save <name>` | save current `settings.json` into a profile |
| `claude-swap edit <name>` | open a profile in `$EDITOR` |
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

## Notes

- **Profiles are whole files.** If your `claude` profile has a `permissions`
  block and your `zai` profile doesn't, switching to `zai` drops those
  permissions. Keep any settings you want in *both* modes in *both* profiles
  (or add them once and re-`save`).
- Override the config root for testing with `CLAUDE_SWAP_HOME=/path/to/.claude`.

## License

MIT — see [LICENSE](LICENSE).
