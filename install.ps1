#Requires -Version 5.1
<#
  claude-swap installer (Windows)

  Smart install:
    * copies claude-swap.ps1 to %LOCALAPPDATA%\claude-swap\bin + a .cmd shim
    * adds that bin dir to your USER PATH (if missing)
    * creates %USERPROFILE%\.claude\profiles\
    * imports current settings.json as the `claude` profile
    * interactively sets up the `zai` profile: asks for your Z.AI API key,
      confirms, saves it (inheriting your permissions so bypassPermissions
      carries over), and prints the exact path for future edits

  Non-interactive: set $env:ZAI_API_KEY to skip the prompt.

  Usage:
    powershell -ExecutionPolicy Bypass -File .\install.ps1
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
  Warn "added $BinDir to your USER PATH - open a NEW terminal for it to take effect."
}

# --- 3. profiles dir + import current settings as `claude` ---------------
New-Item -ItemType Directory -Force -Path $ProfilesDir | Out-Null
$claudeProfile = Join-Path $ProfilesDir 'claude.json'
$settings = Join-Path $ClaudeDir 'settings.json'
if (-not (Test-Path $claudeProfile) -and (Test-Path $settings)) {
  Copy-Item -LiteralPath $settings -Destination $claudeProfile -Force
  Set-Content -LiteralPath (Join-Path $ProfilesDir '.active') -Value 'claude' -NoNewline
  Ok "imported current settings.json as the 'claude' profile"
}

# --- 4. smart Z.AI profile setup -----------------------------------------
function Build-ZaiJson {
  param([string]$Key, [string]$Dest)
  $prof = Get-Content -Raw -LiteralPath (Join-Path $RepoDir 'profiles\zai.json.example') | ConvertFrom-Json
  $prof.env.ANTHROPIC_AUTH_TOKEN = $Key
  if (Test-Path $claudeProfile) {
    try {
      $base = Get-Content -Raw -LiteralPath $claudeProfile | ConvertFrom-Json
      if ($base.permissions) { $prof.permissions = $base.permissions }
      if ($null -ne $base.skipDangerousModePermissionPrompt) {
        $prof.skipDangerousModePermissionPrompt = $base.skipDangerousModePermissionPrompt
      }
    } catch { }
  }
  ($prof | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $Dest -Encoding UTF8
}

$zaiDest = Join-Path $ProfilesDir 'zai.json'
if (Test-Path $zaiDest) {
  Write-Host "  zai profile already exists - left untouched." -ForegroundColor DarkGray
} else {
  $key = $env:ZAI_API_KEY
  if (-not $key) {
    Write-Host ''
    Write-Host 'Set up the Z.AI profile now.' -ForegroundColor White
    $secure = Read-Host -Prompt 'Enter your Z.AI API key (from https://z.ai - leave blank to skip)' -AsSecureString
    $key = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
             [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
  }
  if (-not $key) {
    Copy-Item -LiteralPath (Join-Path $RepoDir 'profiles\zai.json.example') -Destination "$zaiDest.example" -Force
    Warn "no key entered - template saved to $zaiDest.example"
    Write-Host "  add your key later, then rename it to zai.json (or run: claude-swap edit zai)" -ForegroundColor DarkGray
  } else {
    $masked = if ($key.Length -gt 12) { $key.Substring(0,6) + '...' + $key.Substring($key.Length-4) } else { '********' }
    $ans = Read-Host -Prompt "Save key $masked to the Z.AI profile? [y/N]"
    if ($ans -match '^(y|yes)$') {
      Build-ZaiJson -Key $key -Dest $zaiDest
      Write-Host ''
      Ok 'Z.AI profile saved successfully.'
      Write-Host "  File: $zaiDest"
      Write-Host "  To edit later: claude-swap edit zai  (or open the file above)" -ForegroundColor DarkGray
    } else {
      Warn 'cancelled - no key saved.'
    }
  }
}

# --- 5. done -------------------------------------------------------------
Write-Host ''
Ok 'Installation complete.'
Write-Host 'Try:  claude-swap            # status'
Write-Host '      claude-swap zai        # switch to Z.AI / GLM'
Write-Host '      claude-swap claude     # switch back to native Claude'
Warn 'open a NEW terminal before the command is found (PATH was updated).'
