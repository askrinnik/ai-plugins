<#
.SYNOPSIS
	Test cases of the issue-kit configuration check (scripts/Test-IssueKitConfig.ps1, used by "init-config check") in
	a temporary git repository. Exits with 1 when a case fails.

.EXAMPLE
	pwsh -NoProfile -File tests/issue-kit/Check.Cases.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$check = Join-Path $PSScriptRoot '..' '..' 'plugins' 'issue-kit' 'scripts' 'Test-IssueKitConfig.ps1'

$failures = 0
function Assert-Case {
	param([string]$Name, [bool]$Condition)
	if ($Condition) { Write-Host "PASS  $Name" }
	else { Write-Host "FAIL  $Name"; $script:failures++ }
}

$work = Join-Path ([IO.Path]::GetTempPath()) "issue-kit-check-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$configFile = Join-Path $work 'issue-kit.config.json'

function Invoke-Check([string]$Config) {
	if ($Config) { Set-Content -LiteralPath $configFile -Value $Config -Encoding utf8 }
	else { Remove-Item -LiteralPath $configFile -ErrorAction SilentlyContinue }
	$out = & pwsh -NoProfile -File $check -RepoRoot $work 2>&1
	return [pscustomobject]@{ Exit = $LASTEXITCODE; Text = ($out -join "`n") }
}

try {
	New-Item -ItemType Directory -Force -Path (Join-Path $work '.claude/agents'), (Join-Path $work '.claude/skills/write-tests'), (Join-Path $work 'docs') | Out-Null
	& git -C $work init -q -b main
	& git -C $work -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false commit -q --allow-empty -m '- Start'
	Set-Content -LiteralPath (Join-Path $work '.claude/agents/architect.md') -Value "---`nname: architect`n---" -Encoding utf8
	Set-Content -LiteralPath (Join-Path $work '.claude/skills/write-tests/SKILL.md') -Value "---`nname: write-tests`n---" -Encoding utf8
	Set-Content -LiteralPath (Join-Path $work 'docs/requirements.md') -Value '# Requirements' -Encoding utf8

	$r = Invoke-Check ''
	Assert-Case 'no repository file: passes with a warning that the hook stays off' ($r.Exit -eq 0 -and $r.Text -match 'WARN .*hook stays off')

	$r = Invoke-Check '{ "commands": { "build": "git status" }, "prd": { "path": "docs/requirements.md" }, "roles": { "architect": "architect", "testsSkill": "write-tests", "debugSkill": "issue-kit:git-commit" } }'
	Assert-Case 'valid configuration passes' ($r.Exit -eq 0 -and $r.Text -match 'Result: 0 failed')
	Assert-Case 'repository agent is found' ($r.Text -match "OK +roles.architect: agent 'architect' found")
	Assert-Case 'repository skill is found by folder' ($r.Text -match "OK +roles.testsSkill: skill 'write-tests' found")
	Assert-Case 'plugin skill is found' ($r.Text -match "OK +roles.debugSkill: skill 'issue-kit:git-commit' found")
	Assert-Case 'empty command is a warning' ($r.Text -match 'WARN +commands.testFull: empty')

	$r = Invoke-Check '{ "prd": { "path": "docs/missing.md" } }'
	Assert-Case 'missing requirements document fails' ($r.Exit -eq 1 -and $r.Text -match 'FAIL +prd.path')

	$r = Invoke-Check '{ "commands": { "build": "no-such-program-xyz build" } }'
	Assert-Case 'missing program fails and is named' ($r.Exit -eq 1 -and $r.Text -match "program 'no-such-program-xyz'")

	$r = Invoke-Check '{ "roles": { "buildRunner": "build-runner" } }'
	Assert-Case 'plugin agent without prefix fails with a hint' ($r.Exit -eq 1 -and $r.Text -match "needs the prefix: 'issue-kit:build-runner'")

	$r = Invoke-Check '{ "roles": { "securityReviewer": "other-kit:reviewer" } }'
	Assert-Case 'agent of another plugin is a warning, not a failure' ($r.Exit -eq 0 -and $r.Text -match 'WARN +roles.securityReviewer')

	$r = Invoke-Check '{ "baseBranch": "develop" }'
	Assert-Case 'missing base branch fails' ($r.Exit -eq 1 -and $r.Text -match 'FAIL +baseBranch: develop')

	$r = Invoke-Check '{ "rolez": {} }'
	Assert-Case 'invalid key fails and names the file and the key' ($r.Exit -eq 1 -and $r.Text -match "issue-kit.config.json.*'rolez'")
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
