<#
.SYNOPSIS
  Runs the jobsearch-kit script tests: no model session, no usage limit, seconds to run.

.DESCRIPTION
    pwsh -File tests\jobsearch-kit\scripts\Test-Scripts.ps1 [-SkipWord] [-SkipAudio] [-UpdateExpected]

  - Node tests (node --test): unit\*.test.js — workspace.js, cv.js, build-cv.js, build-letter.js and the
    template consistency check.
  - PowerShell tests: unit\scripts.Tests.ps1 — folder-variable.ps1, New-CallAudio.ps1 and the Word scripts
    (export-pdf.ps1, render-preview.ps1; skipped with a message when Word is not installed).

  -SkipWord leaves out the Word tests (they take about 20 s), -SkipAudio the speech synthesis test.
  -UpdateExpected rewrites unit\expected\ from the current template; use it only after a deliberate template change
  and review the diff.
  Needs the npm packages of the plugin (scripts\install-deps.ps1). Temporary files go to %TEMP%\jobsearch-tests\unit.
  Exit code: 0 when every test passes.
#>
param(
  [switch]$SkipWord,
  [switch]$SkipAudio,
  [switch]$UpdateExpected
)
$ErrorActionPreference = 'Stop'
$unit = Join-Path $PSScriptRoot 'unit'
$started = Get-Date

if ($UpdateExpected) { $env:UPDATE_EXPECTED = '1' }
try {
  Push-Location $unit
  & node --test --test-reporter=spec (Get-ChildItem $unit -Filter '*.test.js' | ForEach-Object Name)
  $nodeFailed = $LASTEXITCODE -ne 0
}
finally {
  Pop-Location
  Remove-Item Env:UPDATE_EXPECTED -ErrorAction SilentlyContinue
}

Write-Output ''
& pwsh -NoProfile -File (Join-Path $unit 'scripts.Tests.ps1') -SkipWord:$SkipWord -SkipAudio:$SkipAudio
$psFailed = $LASTEXITCODE -ne 0

$seconds = [math]::Round(((Get-Date) - $started).TotalSeconds)
Write-Output ''
if ($nodeFailed -or $psFailed) {
  Write-Output "FAILED in $seconds s (node tests failed: $nodeFailed; PowerShell tests failed: $psFailed)"
  exit 1
}
Write-Output "All script tests passed in $seconds s"
