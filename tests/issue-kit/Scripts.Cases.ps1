<#
.SYNOPSIS
	Test cases of the issue-kit skill scripts that need no GitHub access: Set-AcceptanceChecks.ps1 with -BodyFile and
	Get-NextIssue.ps1 with -IssuesFile. Exits with 1 when a case fails.

.EXAMPLE
	pwsh -NoProfile -File tests/issue-kit/Scripts.Cases.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$skills = Join-Path $PSScriptRoot '..' '..' 'plugins' 'issue-kit' 'skills'
$materials = Join-Path $PSScriptRoot 'materials'
$acceptance = Join-Path $skills 'github-issue' 'scripts' 'Set-AcceptanceChecks.ps1'
$nextIssue = Join-Path $skills 'next-issue' 'scripts' 'Get-NextIssue.ps1'
$body = Join-Path $materials 'issue-body.md'
$issues = Join-Path $materials 'issues.json'

$failures = 0
function Assert-Case {
	param([string]$Name, [bool]$Condition)
	if ($Condition) { Write-Host "PASS  $Name" }
	else { Write-Host "FAIL  $Name"; $script:failures++ }
}

function Invoke-Script {
	param([string]$Script, [string[]]$Arguments)
	$out = & pwsh -NoProfile -File $Script @Arguments 2>&1
	return [pscustomobject]@{ Exit = $LASTEXITCODE; Lines = @($out | ForEach-Object { "$_" }); Text = ($out -join "`n") }
}

# Set-AcceptanceChecks.ps1
$r = Invoke-Script $acceptance @('-Issue', '1', '-Items', '1,3', '-BodyFile', $body, '-Heading', 'Done when')
Assert-Case 'acceptance: custom heading with a note is found' ($r.Exit -eq 0)
Assert-Case 'acceptance: the section has four checkboxes, nested and * items included' (@($r.Lines | Where-Object { $_ -match '^\s*\d+\. ' }).Count -eq 4)
Assert-Case 'acceptance: item 1 is ticked now' ($r.Text -match '1\. \[x\] Orders export as CSV  \(ticked now\)')
Assert-Case 'acceptance: item 2 stays already ticked' ($r.Text -match '2\. \[x\] Empty export writes a header only  \(already ticked\)')
Assert-Case 'acceptance: nested item 3 is ticked now' ($r.Text -match '3\. \[x\] Header names match the spec  \(ticked now\)')
Assert-Case 'acceptance: item 4 is left unticked' ($r.Text -match '4\. \[ \] Large export streams rows  \(left unticked\)')
Assert-Case 'acceptance: -BodyFile changes nothing' ($r.Text -match 'dry run, 2 item\(s\) would be ticked')
$r = Invoke-Script $acceptance @('-Issue', '1', '-Items', '5', '-BodyFile', $body, '-Heading', 'Done when')
Assert-Case 'acceptance: a position out of range is an error' ($r.Exit -ne 0 -and $r.Text -match 'out of range')
$r = Invoke-Script $acceptance @('-Issue', '1', '-Items', '1', '-BodyFile', $body, '-Heading', 'Definition of done')
Assert-Case 'acceptance: a missing section names the headings it looked for' ($r.Exit -ne 0 -and $r.Text -match "'## Definition of done', '## Acceptance criteria', '## Acceptance'")
$fallback = Join-Path ([IO.Path]::GetTempPath()) "issue-kit-body-$([guid]::NewGuid().ToString('N').Substring(0, 8)).md"
try {
	Set-Content -LiteralPath $fallback -Value "## acceptance   criteria`n- [ ] One" -Encoding utf8
	$r = Invoke-Script $acceptance @('-Issue', '1', '-Items', '1', '-BodyFile', $fallback, '-Heading', 'Done when')
	Assert-Case 'acceptance: "Acceptance criteria" is found in any case and spacing' ($r.Exit -eq 0 -and $r.Text -match 'ticked now')
}
finally { Remove-Item -LiteralPath $fallback -ErrorAction SilentlyContinue }
$r = Invoke-Script $acceptance @('-Issue', '1', '-Items', 'a', '-BodyFile', $body, '-Heading', 'Done when')
Assert-Case 'acceptance: a non-number item is an error' ($r.Exit -ne 0 -and $r.Text -match "Invalid item 'a'")

# Get-NextIssue.ps1
function Get-Ready([string]$Text) {
	$section = ($Text -split 'Ready to start \(recommended first\):')[1]
	if (-not $section) { return @() }
	return @(([regex]::Matches(($section -split "`n`n")[0], '#(\d+) ')) | ForEach-Object { [int]$_.Groups[1].Value })
}

$r = Invoke-Script $nextIssue @('-IssuesFile', $issues, '-TitleCodePattern', '^P(\d+)\.(\d+)', '-Top', '5')
$ready = Get-Ready $r.Text
Assert-Case 'next-issue: codes sort as numbers (P1.2 before P1.10) and issues without a code go last' (($ready -join ',') -eq '10,11,3')
Assert-Case 'next-issue: an issue blocked by an issue with an open pull request waits for that pull request' ($r.Text -match '#12 P0\.1: First .*after PR #50')
Assert-Case 'next-issue: an issue with an open pull request is in progress' ($r.Text -match 'In progress:\s+#13 P0\.0: Blocker .*PR #50')
$r = Invoke-Script $nextIssue @('-IssuesFile', $issues, '-TitleCodePattern', '', '-Top', '5')
Assert-Case 'next-issue: without a pattern the order is the issue number' (((Get-Ready $r.Text) -join ',') -eq '3,10,11')
$r = Invoke-Script $nextIssue @('-IssuesFile', $issues, '-TitleCodePattern', '^P\d+\.(\d+)', '-Top', '5')
Assert-Case 'next-issue: a pattern with one group sorts by that group' (((Get-Ready $r.Text) -join ',') -eq '10,11,3')
$r = Invoke-Script $nextIssue @('-IssuesFile', $issues, '-TitleCodePattern', '^P(\d+)\.(\d+)', '-AssumeClosed', '13', '-Top', '5')
Assert-Case 'next-issue: -AssumeClosed makes the blocked issue ready and first' (((Get-Ready $r.Text) | Select-Object -First 1) -eq 12)
$r = Invoke-Script $nextIssue @('-IssuesFile', $issues, '-TitleCodePattern', '', '-Json')
$json = $r.Text | ConvertFrom-Json
Assert-Case 'next-issue: -Json gives the recommendation' ($json.recommended.number -eq 3 -and $json.openCount -eq 5)

Write-Host ''
if ($failures -gt 0) {
	Write-Host "$failures case(s) failed."
	exit 1
}
Write-Host 'All cases passed.'
