#Requires -Version 5.1
<#
  claude-swap installer (Windows)

  Smart install:
    * copies claude-swap.ps1 to %LOCALAPPDATA%\claude-swap\bin
    * writes a claude-swap.cmd shim so you can just type `claude-swap`
    * adds that bin dir to your USER PATH (if missing)
    * creates %USERPROFILE%\.claude\profiles\
    * imports current settings.json as the `claude` profile (if no profiles yet)
    * drops profile templates

  Usage:
    powershell -ExecutionPolicy Bypass -File .\install.ps1
    irm <raw-url>/install.ps1 | iex        # (from the repo root)
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RepoDir) { $RepoDir = (Get-Location).Path }

$ClaudeDir   = if ($env:CLAUDE_SWAP_HOME) { $env:CLAUDE_SWAP_HOME } else { Join-Path $HOME '.claude' }
$ProfilesDir = Join-Path $ClaudeDir 'profiles'
$BinDir      = Join-Path $env:LOCALAPPDATA 'claude-swap\bin'

function Ok   { param($m) Write-Host "OK  $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "!   $m" -ForegroundColor Yellow }

# --- 1. install script + cmd shim ----------------------------------------
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
Copy-Item -LiteralPath (Join-Path $RepoDir 'bin\claude-swap.ps1') -Destination (Join-Path $BinDir 'claude-swap.ps1') -Force

$shim = @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-swap.ps1" %*
"@
Set-Content -LiteralPath (Join-Path $BinDir 'claude-swap.cmd') -Value $shim -Encoding ASCII
Ok "installed claude-swap -> $BinDir"

# --- 2. add to USER PATH -------------------------------------------------
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$BinDir*") {
  $newPath = if ([string]::IsNullOrEmpty($userPath)) { $BinDir } else { "$userPath;$BinDir" }
  [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
  Warn "added $BinDir to your USER PATH — open a NEW terminal for it to take effect."
}

# --- 3. profiles dir + smart import --------------------------------------
New-Item -ItemType Directory -Force -Path $ProfilesDir | Out-Null
$haveProfiles = (Get-ChildItem -LiteralPath $ProfilesDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
$settings = Join-Path $ClaudeDir 'settings.json'
if (-not $haveProfiles -and (Test-Path $settings)) {
  Copy-Item -LiteralPath $settings -Destination (Join-Path $ProfilesDir 'claude.json') -Force
  Set-Content -LiteralPath (Join-Path $ProfilesDir '.active') -Value 'claude' -NoNewline
  Ok "imported current settings.json as the 'claude' profile"
}

Get-ChildItem -LiteralPath (Join-Path $RepoDir 'profiles') -Filter '*.json.example' -File -ErrorAction SilentlyContinue | ForEach-Object {
  $base = $_.Name -replace '\.example$',''      # zai.json
  $dest = Join-Path $ProfilesDir $base
  if (-not (Test-Path $dest)) {
    Copy-Item -LiteralPath $_.FullName -Destination "$dest.example" -Force
    Write-Host "  template available: $dest.example (fill in and rename to $base)" -ForegroundColor DarkGray
  }
}

Write-Host ''
Ok 'done.'
Write-Host 'Try:  claude-swap            # status'
Write-Host '      claude-swap zai        # switch to Z.AI'
Write-Host '      claude-swap claude     # switch back to native Claude'
Warn 'open a NEW terminal before the command is found (PATH was updated).'
