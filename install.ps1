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

$RepoDir = $null
try { $RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path } catch { }
if (-not $RepoDir) { $RepoDir = (Get-Location).Path }

$ClaudeDir   = if ($env:CLAUDE_SWAP_HOME) { $env:CLAUDE_SWAP_HOME } else { Join-Path $HOME '.claude' }
$ProfilesDir = Join-Path $ClaudeDir 'profiles'
$BinDir      = Join-Path $env:LOCALAPPDATA 'claude-swap\bin'

function Ok   { param($m) Write-Host "OK  $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "!   $m" -ForegroundColor Yellow }
function Fail { param($m) Write-Host "X   $m" -ForegroundColor Red; exit 1 }

# Defense-in-depth: owner-only ACL on token-bearing paths (mirrors bash chmod 700/600)
function Lock-Path {
  param([string]$Path)
  if (-not $Path) { return }
  if (-not (Test-Path -LiteralPath $Path)) { return }
  try {
    $u = $env:USERNAME
    $isDir = (Get-Item -LiteralPath $Path -Force).PSIsContainer
    if ($isDir) {
      & icacls "$Path" /inheritance:r /grant:r "$u:(OI)(CI)F" 2>$null | Out-Null
    } else {
      & icacls "$Path" /inheritance:r /grant:r "$u:F" 2>$null | Out-Null
    }
  } catch { }
}

# --- 0. bootstrap: support `irm ... | iex` (no local checkout) -------------
# floor TLS at 1.2 for all downloads in this session
try {
  [Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

if (-not (Test-Path (Join-Path $RepoDir 'bin\claude-swap.ps1'))) {
  $raw = if ($env:CLAUDE_SWAP_REPO_RAW) { $env:CLAUDE_SWAP_REPO_RAW } else { 'https://raw.githubusercontent.com/chunnytechmate/claude-swap/main' }
  if (($raw -notlike 'https://*') -and (-not $env:CLAUDE_SWAP_REPO_RAW)) { Fail "refusing non-https source: $raw" }
  Write-Host "no local checkout found - downloading from $raw" -ForegroundColor DarkGray
  $tmpRepo = Join-Path ([IO.Path]::GetTempPath()) ("claude-swap-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path "$tmpRepo\bin", "$tmpRepo\profiles" | Out-Null
  try {
    $resp = Invoke-WebRequest -Uri "$raw/bin/claude-swap.ps1" -OutFile "$tmpRepo\bin\claude-swap.ps1" -UseBasicParsing
    Invoke-WebRequest -Uri "$raw/profiles/zai.json.example" -OutFile "$tmpRepo\profiles\zai.json.example" -UseBasicParsing
    Invoke-WebRequest -Uri "$raw/profiles/claude.json.example" -OutFile "$tmpRepo\profiles\claude.json.example" -UseBasicParsing
  } catch { Fail "download failed: $($_.Exception.Message)" }
  # security: reject a redirect downgrade to plain http (default source only)
  if (-not $env:CLAUDE_SWAP_REPO_RAW) {
    try {
      $final = $resp.BaseResponse.ResponseUri.AbsoluteUri
      if ($final -and ($final -notlike 'https://*')) { Fail "download source redirected to non-https: $final" }
    } catch { }
  }
  # validate the downloaded CLI parses before installing it
  $dl = Get-Content -Raw -LiteralPath "$tmpRepo\bin\claude-swap.ps1"
  $parseErrors = $null
  [void][System.Management.Automation.Language.Parser]::ParseInput($dl, [ref]$null, [ref]$parseErrors)
  if ($parseErrors -and $parseErrors.Count -gt 0) { Fail 'downloaded claude-swap.ps1 has syntax errors - aborted' }
  $RepoDir = $tmpRepo
}

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
Lock-Path $ProfilesDir
$claudeProfile = Join-Path $ProfilesDir 'claude.json'
$settings = Join-Path $ClaudeDir 'settings.json'
if (-not (Test-Path $claudeProfile) -and (Test-Path $settings)) {
  Copy-Item -LiteralPath $settings -Destination $claudeProfile -Force
  Lock-Path $claudeProfile
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
  Lock-Path $Dest
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
