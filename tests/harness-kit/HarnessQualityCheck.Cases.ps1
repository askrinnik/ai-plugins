<#
.SYNOPSIS
	Test cases of harness-quality-check in harness-kit: Run-Harness.ps1 -DryRun from a temporary repository whose
	fixtures stay in that repository. Starts no model session. Exits with 1 when a case fails.

.EXAMPLE
	pwsh -NoProfile -File tests/harness-kit/HarnessQualityCheck.Cases.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$runner = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..' 'plugins' 'harness-kit' 'skills' 'harness-quality-check' 'scripts' 'Run-Harness.ps1'))

$failures = 0
function Assert-Case {
	param([string]$Name, [bool]$Condition)
	if ($Condition) { Write-Host "PASS  $Name" }
	else { Write-Host "FAIL  $Name"; $script:failures++ }
}

$work = Join-Path ([IO.Path]::GetTempPath()) "harness-check-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$repo = Join-Path $work 'repo'

function New-Fixture([string]$Dir, [string]$Name, [string]$Prompt) {
	$folder = Join-Path $repo "$Dir/fixtures/$Name"
	New-Item -ItemType Directory -Force -Path $folder | Out-Null
	Set-Content -LiteralPath (Join-Path $folder 'prompt.txt') -Value $Prompt -Encoding utf8
}

function Invoke-Runner([string]$Folder, [string[]]$Arguments) {
	Push-Location $Folder
	# Catch the exception text, so that the error view of pwsh (colours, line wrapping) does not break the matches.
	$quoted = ($Arguments | ForEach-Object { if ($_ -like '-*') { $_ } else { "'$($_ -replace "'", "''")'" } }) -join ' '
	$command = "try { & '$runner' $quoted } catch { Write-Output `$_.Exception.Message; exit 1 }"
	try { $out = & pwsh -NoProfile -Command $command 2>&1 }
	finally { Pop-Location }
	return [pscustomobject]@{ Exit = $LASTEXITCODE; Text = ($out -join "`n") }
}

try {
	New-Item -ItemType Directory -Force -Path $repo | Out-Null
	& git -C $repo init -q -b main
	Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value '# Sample' -Encoding utf8
	& git -C $repo add -A
	& git -C $repo -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -q -m '- Start'
	New-Fixture '.ai/benchmarks/harness' 'bench-base' 'Reply with OK.'
	New-Fixture '.ai/benchmarks/harness' 'bench-read' 'Read README.md and reply with OK.'

	$r = Invoke-Runner $repo @('-DryRun', '-Note', 'dry run test')
	Assert-Case 'dry run finds the fixtures of the repository in the default folder' ($r.Exit -eq 0 -and $r.Text -match 'bench-base x1, bench-read x1')
	Assert-Case 'dry run starts and writes nothing' ($r.Text -match 'Dry run finished' -and -not (Test-Path (Join-Path $repo '.ai/benchmarks/harness/runs')))
	Assert-Case 'the fixtures folder does not count as uncommitted changes' ($r.Text -match 'uncommitted changes: no')

	$sub = Join-Path $repo 'src'
	New-Item -ItemType Directory -Force -Path $sub | Out-Null
	$r = Invoke-Runner $sub @('-DryRun', '-Fixture', 'bench-r*')
	Assert-Case 'a subfolder of the repository finds the same fixtures, masks select them' ($r.Exit -eq 0 -and $r.Text -match 'Fixtures: bench-read x1 ')

	New-Fixture 'tools/bench' 'quality-x' 'Review.'
	Set-Content -LiteralPath (Join-Path $repo 'harness-quality-check.config.json') -Value '{ "dir": "tools/bench" }' -Encoding utf8
	$r = Invoke-Runner $repo @('-DryRun')
	Assert-Case 'the dir key of harness-quality-check.config.json moves the benchmark folder' ($r.Exit -eq 0 -and $r.Text -match 'Fixtures: quality-x x1 ')
	$r = Invoke-Runner $repo @('-DryRun', '-Dir', '.ai/benchmarks/harness')
	Assert-Case '-Dir overrides the settings file' ($r.Exit -eq 0 -and $r.Text -match 'bench-base x1')

	Set-Content -LiteralPath (Join-Path $repo 'harness-quality-check.config.json') -Value '{ "folder": "x" }' -Encoding utf8
	$r = Invoke-Runner $repo @('-DryRun')
	Assert-Case 'an unknown settings key stops and names the file and the key' ($r.Exit -ne 0 -and $r.Text -match "harness-quality-check.config.json : unknown key 'folder'")
	Remove-Item -LiteralPath (Join-Path $repo 'harness-quality-check.config.json')

	$r = Invoke-Runner $repo @('-DryRun', '-Fixture', 'nothing-*')
	Assert-Case 'a mask that matches no fixture names the available ones' ($r.Exit -ne 0 -and $r.Text -match 'Available: bench-base, bench-read')

	$outside = Join-Path $work 'outside'
	New-Item -ItemType Directory -Force -Path $outside | Out-Null
	$r = Invoke-Runner $outside @('-DryRun')
	Assert-Case 'outside a git repository the runner stops with a clear message' ($r.Exit -ne 0 -and $r.Text -match 'not inside a git repository')
}
finally {
	Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($failures -gt 0) {
	Write-Host "$failures case(s) failed."
	exit 1
}
Write-Host 'All cases passed.'
