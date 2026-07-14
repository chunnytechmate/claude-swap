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
  claude-swap update          # update claude-swap itself from GitHub
  claude-swap help
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Command = '',
  [Parameter(Position = 1)][string]$Name
)

$ErrorActionPreference = 'Stop'
$Version = '1.3.0'
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
  $target = ProfilePath $n
  if (-not (Test-Path $target)) { Die "profile '$n' not found" }
  $ed = if ($env:EDITOR) { $env:EDITOR } else { 'notepad' }
  & $ed $target | Out-Null
  if (-not (Test-Json $target)) { Write-Host "warning: '$n' is no longer valid JSON" -ForegroundColor Yellow }
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
  Write-Host "fetching latest from $url" -ForegroundColor DarkGray
  $tmp = [IO.Path]::GetTempFileName()
  try {
    Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
  } catch {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
    Die "download failed: $($_.Exception.Message)"
  }
  $content = Get-Content -Raw -LiteralPath $tmp
  if (($content -notmatch 'claude-swap') -or ($content -notmatch 'Requires -Version')) {
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
    Die 'downloaded file does not look like claude-swap - aborted'
  }
  $newver = if ($content -match "Version\s*=\s*'([\d.]+)'") { $Matches[1] } else { '?' }
  Copy-Item -LiteralPath $tmp -Destination $self -Force
  Remove-Item -Force $tmp -ErrorAction SilentlyContinue
  Write-Host "updated claude-swap $Version -> $newver" -ForegroundColor Green -NoNewline
  Write-Host "  ($self)" -ForegroundColor DarkGray
}

function Show-Usage {
  @"
claude-swap $Version - switch %USERPROFILE%\.claude\settings.json between named profiles

usage:
  claude-swap                 interactive picker (arrow keys) - status if piped
  claude-swap <name>          switch to a profile (e.g. zai, claude)
  claude-swap list            list profiles
  claude-swap status          show active profile + drift check
  claude-swap which           print active profile name only
  claude-swap save <name>     save current settings.json into a profile
  claude-swap edit <name>     open a profile in `$EDITOR
  claude-swap update          update claude-swap itself from GitHub
  claude-swap help

profiles dir: $ProfilesDir
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
  'pick'    { Invoke-PickAndSwitch }
  'menu'    { Invoke-PickAndSwitch }
  'update'  { Cmd-Update }
  'upgrade' { Cmd-Update }
  'help'    { Show-Usage }
  '-h'      { Show-Usage }
  '--help'  { Show-Usage }
  'version' { Write-Host "claude-swap $Version" }
  default   { Cmd-Switch $Command }
}
