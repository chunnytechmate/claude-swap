#Requires -Version 5.1
<#
.SYNOPSIS
  claude-swap - switch %USERPROFILE%\.claude\settings.json between named profiles.

.EXAMPLE
  claude-swap                 # interactive picker (arrow keys)
  claude-swap zai             # switch to the "zai" profile
  claude-swap claude          # switch to the "claude" profile
  claude-swap list
  claude-swap status
  claude-swap which
  claude-swap save <name>
  claude-swap edit <name>
  claude-swap changekey [name]   # replace the API key in a profile (default zai)
  claude-swap update          # update claude-swap itself from GitHub
  claude-swap help
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Command = '',
  [Parameter(Position = 1)][string]$Name
)

$ErrorActionPreference = 'Stop'
$Version = '1.5.2'
$RepoRaw = if ($env:CLAUDE_SWAP_REPO_RAW) { $env:CLAUDE_SWAP_REPO_RAW } else { 'https://raw.githubusercontent.com/chunnytechmate/claude-swap/main' }

# --- paths (override root with CLAUDE_SWAP_HOME for testing) ---------------
$ClaudeDir   = if ($env:CLAUDE_SWAP_HOME) { $env:CLAUDE_SWAP_HOME } else { Join-Path $HOME '.claude' }
$Settings    = Join-Path $ClaudeDir 'settings.json'
$ProfilesDir = Join-Path $ClaudeDir 'profiles'
$BackupDir   = Join-Path $ProfilesDir '.backups'
$ActiveMark  = Join-Path $ProfilesDir '.active'
$MaxBackups  = 10

function Die { param($m) Write-Host "error: $m" -ForegroundColor Red; exit 1 }

function Test-Json {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $false }
  try { Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json | Out-Null; return $true }
  catch { return $false }
}

function Get-Hash {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return 'MISSING' }
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function ProfilePath { param($n) Join-Path $ProfilesDir "$n.json" }

# security: profile names may not traverse paths or start with a dot
function Test-Name { param($n) return ($n -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') }

function Get-Profiles {
  if (-not (Test-Path $ProfilesDir)) { return @() }
  Get-ChildItem -LiteralPath $ProfilesDir -Filter '*.json' -File | ForEach-Object { $_.BaseName }
}

function Get-Marker {
  if (Test-Path $ActiveMark) { (Get-Content -Raw -LiteralPath $ActiveMark).Trim() } else { '' }
}

function Get-Matched {
  if (-not (Test-Path $Settings)) { return '' }
  $want = Get-Hash $Settings
  foreach ($p in Get-Profiles) {
    if ((Get-Hash (ProfilePath $p)) -eq $want) { return $p }
  }
  return ''
}

function Invoke-Prune {
  if (-not (Test-Path $BackupDir)) { return }
  Get-ChildItem -LiteralPath $BackupDir -Filter 'settings.*.json' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip $MaxBackups |
    Remove-Item -Force -ErrorAction SilentlyContinue
}

function Cmd-List {
  $marker = Get-Marker
  $profiles = @(Get-Profiles)
  if (-not $profiles) { Write-Host "no profiles in $ProfilesDir" -ForegroundColor DarkGray; return }
  foreach ($p in $profiles) {
    if ($p -eq $marker) { Write-Host "  * $p" -ForegroundColor Green }
    else { Write-Host "    $p" }
  }
}

function Cmd-Status {
  $marker  = Get-Marker
  $matched = Get-Matched
  if     ($marker)  { Write-Host "active: " -NoNewline; Write-Host $marker -ForegroundColor Cyan }
  elseif ($matched) { Write-Host "active: " -NoNewline; Write-Host "$matched (detected)" -ForegroundColor Cyan }
  else              { Write-Host "active: (unknown - settings.json matches no profile)" -ForegroundColor Yellow }

  if ($marker -and (Test-Path (ProfilePath $marker))) {
    if ((Get-Hash $Settings) -ne (Get-Hash (ProfilePath $marker))) {
      Write-Host "! settings.json edited since last swap (drift from '$marker')." -ForegroundColor Yellow
      Write-Host "  Run 'claude-swap $marker' to reset, or 'claude-swap save $marker' to capture edits." -ForegroundColor DarkGray
    }
  }
  Write-Host ''
  Write-Host 'profiles:'
  Cmd-List
}

function Cmd-Switch {
  param([string]$n)
  if (-not (Test-Name $n)) { Die "invalid profile name: '$n' (letters, digits, . _ - only)" }
  $target = ProfilePath $n
  if (-not (Test-Path $target)) { Die "profile '$n' not found - run: claude-swap list" }
  if (-not (Test-Json $target)) { Die "profile '$n' is not valid JSON: $target" }

  New-Item -ItemType Directory -Force -Path $ProfilesDir, $BackupDir | Out-Null

  if (Test-Path $Settings) {
    if ((Get-Hash $Settings) -eq (Get-Hash $target)) {
      Write-Host "already on $n" -ForegroundColor Green
      Set-Content -LiteralPath $ActiveMark -Value $n -NoNewline
      return
    }
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    Copy-Item -LiteralPath $Settings -Destination (Join-Path $BackupDir "settings.$ts.json") -Force
    Invoke-Prune
  }

  # atomic-ish: write temp in same dir, validate, then move
  $tmp = Join-Path $ClaudeDir (".settings." + [guid]::NewGuid().ToString('N'))
  Copy-Item -LiteralPath $target -Destination $tmp -Force
  if (-not (Test-Json $tmp)) { Remove-Item -Force $tmp; Die "staged settings invalid - aborted" }
  Move-Item -LiteralPath $tmp -Destination $Settings -Force
  Set-Content -LiteralPath $ActiveMark -Value $n -NoNewline
  Write-Host "switched to $n" -ForegroundColor Green -NoNewline; Write-Host "  -> $Settings" -ForegroundColor DarkGray
  Write-Host "  restart Claude Code / reload the window for env changes to take effect." -ForegroundColor DarkGray
}

function Cmd-Save {
  param([string]$n)
  if (-not $n) { Die 'usage: claude-swap save <name>' }
  if (-not (Test-Name $n)) { Die "invalid profile name: '$n' (letters, digits, . _ - only)" }
  if (-not (Test-Path $Settings)) { Die 'no settings.json to save' }
  if (-not (Test-Json $Settings)) { Die 'current settings.json is not valid JSON' }
  New-Item -ItemType Directory -Force -Path $ProfilesDir | Out-Null
  Copy-Item -LiteralPath $Settings -Destination (ProfilePath $n) -Force
  Set-Content -LiteralPath $ActiveMark -Value $n -NoNewline
  Write-Host "saved current settings.json to profile $n" -ForegroundColor Green
}

function Cmd-Edit {
  param([string]$n)
  if (-not $n) { Die 'usage: claude-swap edit <name>' }
  if (-not (Test-Name $n)) { Die "invalid profile name: '$n' (letters, digits, . _ - only)" }
  $target = ProfilePath $n
  if (-not (Test-Path $target)) { Die "profile '$n' not found" }
  $ed = if ($env:EDITOR) { $env:EDITOR } else { 'notepad' }
  & $ed $target | Out-Null
  if (-not (Test-Json $target)) { Write-Host "warning: '$n' is no longer valid JSON" -ForegroundColor Yellow }
}

function Cmd-ChangeKey {
  param([string]$n)
  if (-not $n) { $n = 'zai' }
  if (-not (Test-Name $n)) { Die "invalid profile name: '$n' (letters, digits, . _ - only)" }
  $target = ProfilePath $n
  if (-not (Test-Path $target)) { Die "profile '$n' not found - run: claude-swap list" }

  # which key field does this profile use?
  $raw = Get-Content -Raw -LiteralPath $target
  $field = $null
  if     ($raw -match '"ANTHROPIC_AUTH_TOKEN"') { $field = 'ANTHROPIC_AUTH_TOKEN' }
  elseif ($raw -match '"ANTHROPIC_API_KEY"')    { $field = 'ANTHROPIC_API_KEY' }
  if (-not $field) { Die "profile '$n' has no ANTHROPIC_AUTH_TOKEN / ANTHROPIC_API_KEY field - try: claude-swap edit $n" }

  Write-Host "Change API key for $n ($field)"
  $secure = Read-Host -Prompt 'Enter new API key (blank to cancel)' -AsSecureString
  $key = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
           [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
  if (-not $key) { Write-Host 'cancelled - no changes' -ForegroundColor DarkGray; return }

  $masked = if ($key.Length -gt 12) { $key.Substring(0,6) + '...' + $key.Substring($key.Length-4) } else { '********' }
  $ans = Read-Host -Prompt "Save key $masked to $n? [y/N]"
  if ($ans -notmatch '^(y|yes)$') { Write-Host 'cancelled - no changes' -ForegroundColor DarkGray; return }

  # replace only env.<field>, preserving everything else
  try {
    $prof = Get-Content -Raw -LiteralPath $target | ConvertFrom-Json
    if (-not $prof.env) { Die "profile '$n' has no env block - try: claude-swap edit $n" }
    $prof.env.$field = $key
    ($prof | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $target -Encoding UTF8
  } catch { Die "failed to update '$n': $($_.Exception.Message)" }

  Write-Host "updated $field in profile $n" -ForegroundColor Green -NoNewline
  Write-Host "  ($target)" -ForegroundColor DarkGray

  # if this is the active profile, re-deploy so the new key takes effect now
  if ((Get-Marker) -eq $n) {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    if (Test-Path $Settings) {
      $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
      Copy-Item -LiteralPath $Settings -Destination (Join-Path $BackupDir "settings.$ts.json") -Force
      Invoke-Prune
    }
    $tmp = Join-Path $ClaudeDir (".settings." + [guid]::NewGuid().ToString('N'))
    Copy-Item -LiteralPath $target -Destination $tmp -Force
    if (Test-Json $tmp) {
      Move-Item -LiteralPath $tmp -Destination $Settings -Force
      Write-Host "  also applied to live settings.json ($n is active)" -ForegroundColor DarkGray
    } else {
      Remove-Item -Force $tmp
      Write-Host "  profile is active but settings.json was NOT updated (invalid JSON)" -ForegroundColor Yellow
    }
    Write-Host "  restart Claude Code / reload the window for the change to take effect." -ForegroundColor DarkGray
  } else {
    Write-Host "  (not active - run 'claude-swap $n' to apply)" -ForegroundColor DarkGray
  }
}

# Best-effort: enable ANSI/VT output for legacy conhost (Win10 < 1903).
# ConPTY / Windows Terminal / VS Code already have VirtualTerminalLevel = 1.
function Enable-Vt {
  try {
    if (-not ('ClaudeSwap.CsVt' -as [type])) {
      Add-Type -Name CsVt -Namespace ClaudeSwap -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int h);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@
    }
    $h = [ClaudeSwap.CsVt]::GetStdHandle(-11)
    $m = [uint32]0
    if ([ClaudeSwap.CsVt]::GetConsoleMode($h, [ref]$m)) {
      [void][ClaudeSwap.CsVt]::SetConsoleMode($h, ($m -bor 0x4))
    }
  } catch { }
}

# Interactive arrow-key picker (ANSI redraw). Returns the chosen profile, or $null.
# Redraws with VT escape sequences (which ConPTY interprets) instead of the
# Win32 cursor API, and reads keys with [Console]::ReadKey.
function Invoke-Pick {
  $opts = @(Get-Profiles)
  if ($opts.Count -eq 0) { Die "no profiles in $ProfilesDir" }
  $active = Get-Marker
  $cur = [Array]::IndexOf($opts, $active); if ($cur -lt 0) { $cur = 0 }

  Enable-Vt
  $e = [char]27

  Write-Host 'Select a profile  ' -NoNewline
  Write-Host '(Up/Down or j/k, Enter to switch, q to cancel)' -ForegroundColor DarkGray
  [Console]::Out.Write("$e[?25l")   # hide cursor
  try {
    $first = $true
    while ($true) {
      if (-not $first) { [Console]::Out.Write("$e[$($opts.Count)A") }  # cursor up N lines
      $first = $false
      for ($i = 0; $i -lt $opts.Count; $i++) {
        $tag  = if ($opts[$i] -eq $active) { '  (active)' } else { '' }
        $mark = if ($i -eq $cur) { '> ' } else { '  ' }
        [Console]::Out.Write("$e[2K`r")   # clear the whole line
        if ($i -eq $cur) { Write-Host "  $mark$($opts[$i])$tag" -ForegroundColor Cyan }
        else             { Write-Host "  $mark$($opts[$i])$tag" }
      }
      $k = [Console]::ReadKey($true)
      switch ($k.Key) {
        'UpArrow'   { $cur = ($cur - 1 + $opts.Count) % $opts.Count }
        'DownArrow' { $cur = ($cur + 1) % $opts.Count }
        'K'         { $cur = ($cur - 1 + $opts.Count) % $opts.Count }
        'J'         { $cur = ($cur + 1) % $opts.Count }
        'Enter'     { return $opts[$cur] }
        'Q'         { return $null }
        'Escape'    { return $null }
      }
    }
  } finally { [Console]::Out.Write("$e[?25h") }   # always restore cursor
}

function Cmd-Update {
  $url  = "$RepoRaw/bin/claude-swap.ps1"
  $self = $PSCommandPath
  if (-not $self) { $self = $MyInvocation.MyCommand.Path }

  # security: https only, unless the source was explicitly overridden (testing/forks)
  if ($url -notlike 'https://*') {
    if (-not $env:CLAUDE_SWAP_REPO_RAW) { Die "refusing non-https update source: $url" }
    Write-Host "!   using overridden update source: $url" -ForegroundColor Yellow
  }
  # floor TLS at 1.2 (Windows PowerShell 5.1 may otherwise negotiate older TLS)
  try {
    [Net.ServicePointManager]::SecurityProtocol =
      [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  } catch { }

  Write-Host "fetching latest from $url" -ForegroundColor DarkGray
  $tmp = [IO.Path]::GetTempFileName()
  try {
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
  } catch {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
    Die "download failed: $($_.Exception.Message)"
  }

  # integrity gate: everything must pass before we touch the installed file
  $content = Get-Content -Raw -LiteralPath $tmp
  if (($content.Length -lt 4096) -or ($content -notmatch 'claude-swap') -or ($content -notmatch 'Requires -Version')) {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
    Die 'downloaded file failed validation (wrong content or truncated) - aborted'
  }
  $parseErrors = $null
  [void][System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$null, [ref]$parseErrors)
  if ($parseErrors -and $parseErrors.Count -gt 0) {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
    Die 'downloaded file has PowerShell syntax errors - aborted'
  }

  $newver = if ($content -match "Version\s*=\s*'([\d.]+)'") { $Matches[1] } else { '?' }
  if ($newver -eq $Version) {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
    Write-Host "already up to date ($Version)" -ForegroundColor Green
    return
  }

  # atomic-ish replace: stage next to the target, then move over it
  $staged = "$self.new"
  Copy-Item -LiteralPath $tmp -Destination $staged -Force
  Move-Item -LiteralPath $staged -Destination $self -Force
  Remove-Item -Force $tmp -ErrorAction SilentlyContinue
  Write-Host "updated claude-swap $Version -> $newver" -ForegroundColor Green -NoNewline
  Write-Host "  ($self)" -ForegroundColor DarkGray
}

function Show-Usage-Short {
  @"
claude-swap $Version
Switch Claude Code's settings.json between named profiles.

COMMANDS (claude-swap <command>):
  (no args)        interactive arrow-key picker (status if piped)
  <name>           switch to a profile (e.g. zai, claude)
  list             list profiles (* = active)
  status           show active profile + drift check
  which            print the active profile name (scriptable)
  save <name>      copy settings.json into a profile
  edit <name>      open a profile in `$EDITOR
  changekey [name] replace the API key (default: zai)
  update           update claude-swap from GitHub
  version          print the version
  help [all]       show this help, or full details

run 'claude-swap help all' for examples, file locations, and env vars
"@ | Write-Host
}

function Show-Usage-Full {
  @"
claude-swap $Version
Switch Claude Code's settings.json between named profiles (e.g. native
'claude' and a provider like 'zai' / Z.AI-GLM).

USAGE
  claude-swap [command] [args]

COMMANDS
  (no args)        interactive arrow-key picker (status if piped)
  <name>           switch to profile <name>   (e.g. zai, claude)
  list             list profiles (* marks the active one)
  status           show active profile + drift check
  which            print the active profile name only (scriptable)
  save <name>      copy current settings.json into a profile
  edit <name>      open a profile in `$EDITOR
  changekey [name] replace the API key in a profile (default: zai)
  update           update claude-swap itself from GitHub
  version          print the version
  help [all]       show short help, or full details with 'all' / '-a'

EXAMPLES
  claude-swap             pick a profile with the arrow keys
  claude-swap zai         switch to Z.AI / GLM
  claude-swap claude      switch back to native Claude
  claude-swap changekey   rotate the API key (re-applies if active)
  claude-swap save work   snapshot current settings.json as 'work'

PROFILES
  Each profile is a complete settings.json, stored in:
    $ProfilesDir
  The active profile is copied to:
    $Settings
  After switching, restart Claude Code (or reload the IDE window) so the
  new env / model settings take effect.

ENVIRONMENT
  CLAUDE_SWAP_HOME        config root (default: ~/.claude)
  CLAUDE_SWAP_REPO_RAW    source for 'update' / install (default: main branch)

Docs:  https://github.com/chunnytechmate/claude-swap
"@ | Write-Host
}

function Invoke-PickAndSwitch {
  $sel = Invoke-Pick
  if ($sel) { Cmd-Switch $sel } else { Write-Host 'cancelled' -ForegroundColor DarkGray }
}

# --- dispatch ------------------------------------------------------------
if ([string]::IsNullOrEmpty($Command)) {
  if (-not [Console]::IsInputRedirected) { Invoke-PickAndSwitch } else { Cmd-Status }
  return
}

switch ($Command.ToLower()) {
  'status'  { Cmd-Status }
  'list'    { Cmd-List }
  'ls'      { Cmd-List }
  'which'   { Get-Marker }
  'save'    { Cmd-Save $Name }
  'edit'    { Cmd-Edit $Name }
  'changekey'  { Cmd-ChangeKey $Name }
  'change-key' { Cmd-ChangeKey $Name }
  'key'        { Cmd-ChangeKey $Name }
  'pick'    { Invoke-PickAndSwitch }
  'menu'    { Invoke-PickAndSwitch }
  'update'  { Cmd-Update }
  'upgrade' { Cmd-Update }
  'help'    { if ($Name -in @('all','-a','--all')) { Show-Usage-Full } else { Show-Usage-Short } }
  '-h'      { Show-Usage-Short }
  '--help'  { Show-Usage-Short }
  'version' { Write-Host "claude-swap $Version" }
  default   { Cmd-Switch $Command }
}
