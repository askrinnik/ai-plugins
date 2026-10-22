<#
.SYNOPSIS
  Tests of the PowerShell scripts of jobsearch-kit and of the test tool New-CallAudio.ps1. Plain assertions, no
  Pester. Run by Test-Scripts.ps1; prints one line per test and exits with the number of failed tests.
#>
param(
  [switch]$SkipWord,
  [switch]$SkipAudio
)
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$config = Get-Content (Join-Path $repo 'tests\jobsearch-kit\config.json') -Raw | ConvertFrom-Json
$scripts = Join-Path $repo "$($config.plugin)\scripts"
$seed = Join-Path $repo $config.seed
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) 'jobsearch-tests\unit'
New-Item -ItemType Directory -Force $tempRoot | Out-Null

$script:failed = 0
$script:passed = 0
$script:skipped = 0

function Test-Case([string]$Name, [scriptblock]$Body) {
  try {
    & $Body
    Write-Output "ok    $Name"
    $script:passed++
  }
  catch {
    Write-Output "FAIL  $Name"
    Write-Output "      $($_.Exception.Message)"
    $script:failed++
  }
}

function Skip-Case([string]$Name, [string]$Reason) {
  Write-Output "skip  $Name ($Reason)"
  $script:skipped++
}

function Assert-True($Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

function Assert-Equal($Expected, $Actual, [string]$What) {
  if ($Expected -ne $Actual) { throw "${What}: expected <$Expected>, actual <$Actual>" }
}

function New-TempDir([string]$Name) {
  $dir = Join-Path $tempRoot ("$Name-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory $dir | Out-Null
  $dir
}

# --- folder-variable.ps1 -------------------------------------------------------------------------------------------
# Sync-FolderVariable writes the user environment. The tests use a throwaway variable name and remove it afterwards.
# PowerShell passes $null to a .NET string parameter as "", which leaves an empty variable; [NullString]::Value removes it.
. (Join-Path $scripts 'folder-variable.ps1')
$var = 'JOBSEARCH_TEST_' + [guid]::NewGuid().ToString('N').Substring(0, 8).ToUpperInvariant()
$default = Join-Path $tempRoot 'default-folder'
$custom = Join-Path $tempRoot 'custom-folder'
$other = Join-Path $tempRoot 'other-folder'
function Get-UserVar { [Environment]::GetEnvironmentVariable($var, 'User') }
function Clear-Var {
  [Environment]::SetEnvironmentVariable($var, [NullString]::Value, 'User')
  Remove-Item "Env:$var" -ErrorAction SilentlyContinue
}

try {
  Test-Case 'folder-variable: the default folder sets nothing' {
    Clear-Var
    $out = Sync-FolderVariable -Name $var -Folder $default -Default $default 3>&1 | Out-String
    Assert-True ($null -eq (Get-UserVar)) "the variable must stay unset, but it is '$(Get-UserVar)'"
    Assert-True (-not $out.Trim()) "no output expected, got: $out"
  }

  Test-Case 'folder-variable: a custom folder sets the user and process variable' {
    Clear-Var
    $out = Sync-FolderVariable -Name $var -Folder "$custom\" -Default $default | Out-String
    Assert-Equal $custom (Get-UserVar) 'user variable'
    Assert-Equal $custom (Get-Item "Env:$var").Value 'process variable'
    Assert-True ($out -match "$var set to") "the output must say that the variable was set: $out"
  }

  Test-Case 'folder-variable: a variable that already points to the folder is kept' {
    [Environment]::SetEnvironmentVariable($var, $custom, 'User')
    $out = Sync-FolderVariable -Name $var -Folder $custom -Default $default | Out-String
    Assert-True ($out -match 'already points to') "the output must say 'already points to': $out"
    Assert-Equal $custom (Get-UserVar) 'user variable'
  }

  Test-Case 'folder-variable: the default folder while the variable points elsewhere only warns' {
    [Environment]::SetEnvironmentVariable($var, $other, 'User')
    $warning = Sync-FolderVariable -Name $var -Folder $default -Default $default 3>&1 | Out-String
    Assert-True ($warning -match "points to .*other-folder") "a warning naming the other folder is expected: $warning"
    Assert-Equal $other (Get-UserVar) 'the variable must not change'
  }
}
finally {
  Clear-Var
}

Test-Case 'folder-variable: the throwaway variable is removed' {
  $left = (Get-Item 'HKCU:\Environment').Property -contains $var
  Assert-True (-not $left) "$var is still in the user environment"
}

# --- New-CallAudio.ps1 ---------------------------------------------------------------------------------------------
function Get-WavSeconds([string]$Path) {
  $b = [IO.File]::ReadAllBytes($Path)
  Assert-Equal 'RIFF' ([Text.Encoding]::ASCII.GetString($b, 0, 4)) 'WAV header'
  $pos = 12; $byteRate = $null; $dataLength = $null
  while ($pos + 8 -le $b.Length) {
    $id = [Text.Encoding]::ASCII.GetString($b, $pos, 4)
    $len = [BitConverter]::ToInt32($b, $pos + 4)
    if ($id -eq 'fmt ') {
      Assert-Equal 1 ([BitConverter]::ToInt16($b, $pos + 10)) 'channels'
      $byteRate = [BitConverter]::ToInt32($b, $pos + 16)
    }
    if ($id -eq 'data') { $dataLength = $len }
    $pos += 8 + $len + ($len % 2)
  }
  Assert-True ($byteRate -and $dataLength) 'the WAV must have a fmt and a data chunk'
  $dataLength / $byteRate
}

if ($SkipAudio) {
  Skip-Case 'New-CallAudio: WAV of the expected length' '-SkipAudio'
}
else {
  Test-Case 'New-CallAudio: WAV of the expected length' {
    $dir = New-TempDir 'audio'
    $dialogue = Join-Path $dir 'dialogue.tsv'
    Set-Content -LiteralPath $dialogue -Encoding UTF8 -Value "Anna`ten`tHello Jordan.", "Jordan`ten`tHello Anna."
    $tool = Join-Path $repo 'tests\jobsearch-kit\tools\New-CallAudio.ps1'
    $seconds = @{}
    foreach ($pause in 0, 1000) {
      $wav = Join-Path $dir "call-$pause.wav"
      $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tool -Dialogue $dialogue -Out $wav -PauseMs $pause 2>&1 | Out-String
      Assert-Equal 0 $LASTEXITCODE "exit code of New-CallAudio.ps1 (output: $out)"
      Assert-True ($out -match '2 utterances') "the tool must report 2 utterances: $out"
      $seconds[$pause] = Get-WavSeconds $wav
    }
    Assert-True ($seconds[0] -gt 0.5 -and $seconds[0] -lt 10) "two short utterances must last 0.5-10 s, got $($seconds[0]) s"
    $added = [math]::Round($seconds[1000] - $seconds[0], 2)
    Assert-Equal 2 $added 'seconds added by two pauses of 1000 ms'
    Remove-Item $dir -Recurse -Force
  }
}

# --- Word-dependent scripts ----------------------------------------------------------------------------------------
$hasWord = [bool](Get-Item 'Registry::HKEY_CLASSES_ROOT\Word.Application' -ErrorAction SilentlyContinue)
if ($SkipWord -or -not $hasWord) {
  $reason = if ($SkipWord) { '-SkipWord' } else { 'Microsoft Word is not installed' }
  Skip-Case 'export-pdf.ps1: PDF with pages and links' $reason
  Skip-Case 'render-preview.ps1: one PNG per page' $reason
}
else {
  $ws = New-TempDir 'word'
  Copy-Item (Join-Path $seed '*') $ws -Recurse -Force
  Push-Location $ws
  try {
    & node (Join-Path $scripts 'cv.js') MyProfile/cv/profile_full.yaml | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'cv.js failed to build the template full CV' }
  }
  finally { Pop-Location }
  $docx = Get-ChildItem (Join-Path $ws 'MyProfile\cv') -Filter '*.docx' | Select-Object -First 1

  Test-Case 'export-pdf.ps1: PDF with pages and links' {
    $out = & pwsh -NoProfile -File (Join-Path $scripts 'export-pdf.ps1') -Docx $docx.FullName 2>&1 | Out-String
    Assert-Equal 0 $LASTEXITCODE "exit code (output: $out)"
    Assert-True (Test-Path ([IO.Path]::ChangeExtension($docx.FullName, '.pdf'))) 'the PDF must be written next to the .docx'
    Assert-True ($out -match 'Pages: [1-9]') "the page count must be printed: $out"
    foreach ($link in 'mailto:jordan.sample@example.com', 'https://github.com/example') {
      Assert-True ($out -match [regex]::Escape($link)) "the PDF must keep the link $link; output: $out"
    }
  }

  Test-Case 'render-preview.ps1: one PNG per page' {
    $outDir = Join-Path $ws 'preview'
    $out = & pwsh -NoProfile -File (Join-Path $scripts 'render-preview.ps1') -Docx $docx.FullName -OutDir $outDir 2>&1 | Out-String
    Assert-Equal 0 $LASTEXITCODE "exit code (output: $out)"
    $pages = if ($out -match 'Word pages: (\d+)') { [int]$Matches[1] } else { throw "no page count in the output: $out" }
    $pngs = @(Get-ChildItem $outDir -Filter 'page*.png')
    Assert-Equal $pages $pngs.Count 'PNG files (one per Word page)'
  }
  Remove-Item $ws -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ''
Write-Output "PowerShell tests: $script:passed passed, $script:failed failed, $script:skipped skipped"
exit $script:failed
