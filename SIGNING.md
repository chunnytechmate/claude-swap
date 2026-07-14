# Signed updates (minisign)

`claude-swap update` can verify each release with an **ed25519 minisign
signature** before installing it. This closes the biggest residual risk: even if
GitHub or the repo is compromised, a forged update can't install unless it is
signed with your private key.

The mechanism is built in but **inert until you activate it** (the embedded
public key is empty by default). Activating it is a one-time setup; after that,
signing each release takes one command.

> Why it is opt-in: verifying needs the `minisign` tool on the *receiving*
> machine, which not everyone has. So verification is **graceful** — if minisign
> is present and a signature exists, the update is verified and a forged file is
> refused; if minisign is absent or no signature is found, `update` prints a
> warning and still installs (it never breaks existing users).

## 1. Install minisign

- **Linux:** `sudo apt install minisign` (or build from source)
- **macOS:** `brew install minisign`
- **Windows:** `scoop install minisign` (or a build from upstream)

## 2. Generate your keypair (once)

Run anywhere you control (this produces your **secret key** — keep it safe and
**never commit it**):

```bash
minisign -G -p claude-swap.pub -s minisign.key
```

- `minisign.key` — your **private** key (password-protected). Back it up offline.
  Add it to `.gitignore` if it lives inside the repo.
- `claude-swap.pub` — your **public** key (safe to share).

`claude-swap.pub` looks like:

```
untrusted comment: minisign public key ...
ed25519: ABCDEF1234567890...
```

## 3. Embed the public key

Copy the `ed25519: ...` line and paste it into the `MINISIGN_PUB` / `$MinisignPub`
constant at the top of **both** scripts:

- `bin/claude-swap`        → `MINISIGN_PUB='ed25519:...'`
- `bin/claude-swap.ps1`    → `$MinisignPub = 'ed25519:...'`

Commit this change. From the next release on, every installed copy will verify
updates against this key.

## 4. Sign a release

Before tagging a release, sign the two scripts with your private key:

```bash
scripts/sign-release.sh minisign.key
```

This writes `bin/claude-swap.minisig` and `bin/claude-swap.ps1.minisig`.
**Commit the `.minisig` files**, then tag/push as usual. `update` fetches
`<file>.minisig` next to the script and verifies it.

## 5. Verify it works

On a machine with minisign installed, run `claude-swap update`. You should see:

```
✓ release signature verified
```

If you tamper with the downloaded file, `update` aborts with
`SIGNATURE VERIFICATION FAILED`.

## Notes

- The **first** install trusts the public key embedded in the script (delivered
  over HTTPS). After that, existing installs only accept updates signed with the
  matching private key — so changing the public key itself requires a validly
  signed update.
- If you ever lose the private key, generate a new keypair, bump the embedded
  public key in a signed release (using the *old* key once more), and continue.
- Users without minisign are unaffected (warning + normal install).
