<#
.SYNOPSIS
	Checks the issue-kit configuration of the current repository: keys, paths, commands, and the agents and skills of
	roles. Prints one line per check and exits with 1 when a check fails.

.DESCRIPTION
	- Keys and types: the configuration reader (an invalid file fails here and names the file and the key).
	- Paths: prd.path must be a file and plans.dir a folder, relative to the repository root.
	- Commands: the program of each non-empty commands.* entry must be on the path (or a file in the repository).
	- Roles: a plugin agent or skill "issue-kit:<name>" must exist in this plugin; a repository agent "<name>" must
	  exist in .claude/agents/<name>.md and a repository skill in .claude/skills/<folder>/SKILL.md. A name of another
	  plugin ("<plugin>:<name>") is reported as not checked.
	- The base branch must exist locally or on origin.
	A warning does not fail the check.

.PARAMETER RepoRoot
	The repository root; defaults to the git root of the current folder.

.EXAMPLE
	pwsh -NoProfile -File <plugin>/scripts/Test-IssueKitConfig.ps1
#>
[CmdletBinding()]
param([string]$RepoRoot)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Import-Module (Join-Path $PSScriptRoot 'IssueKitConfig.psm1') -Force
$pluginRoot = Split-Path $PSScriptRoot -Parent
if (-not $RepoRoot) { $RepoRoot = Get-IssueKitRepoRoot }

$script:errors = 0
$script:warnings = 0
function Write-Check([string]$State, [string]$Text) {
	if ($State -eq 'FAIL') { $script:errors++ }
	if ($State -eq 'WARN') { $script:warnings++ }
	Write-Output ('{0,-4}  {1}' -f $State, $Text)
}

try {
	$result = Get-IssueKitConfig -RepoRoot $RepoRoot
}
catch {
	Write-Check 'FAIL' $_.Exception.Message
	Write-Output ''
	Write-Output 'Result: 1 failed check.'
	exit 1
}
$c = $result.Config
Write-Check 'OK' "Keys and types: $($result.Sources.Count) file(s) read: $($result.Sources -join ', ')"
if (-not $result.HasRepoFile) { Write-Check 'WARN' "No repository file $($result.RepoFile): the defaults apply and the commit message hook stays off." }

# Paths
if ($c.prd.path) {
	if (Test-Path -LiteralPath (Join-Path $RepoRoot $c.prd.path) -PathType Leaf) { Write-Check 'OK' "prd.path: $($c.prd.path) exists" }
	else { Write-Check 'FAIL' "prd.path: $($c.prd.path) is not a file in the repository" }
}
else { Write-Check 'OK' 'prd.path: empty, the requirements-document step is skipped' }
if (Test-Path -LiteralPath (Join-Path $RepoRoot $c.plans.dir) -PathType Container) { Write-Check 'OK' "plans.dir: $($c.plans.dir) exists" }
else { Write-Check 'WARN' "plans.dir: $($c.plans.dir) does not exist yet; the first plan creates it" }

# Commands
foreach ($key in 'build', 'testFull', 'testProject', 'format') {
	$command = [string]$c.commands[$key]
	if (-not $command) { Write-Check 'WARN' "commands.${key}: empty, build-runner reports this step as NOT CONFIGURED"; continue }
	$program = ($command.Trim() -split '\s+')[0].Trim('"', "'")
	$inRepo = Test-Path -LiteralPath (Join-Path $RepoRoot $program) -PathType Leaf
	if ($inRepo -or (Get-Command $program -ErrorAction SilentlyContinue)) { Write-Check 'OK' "commands.${key}: '$program' found" }
	else { Write-Check 'FAIL' "commands.${key}: program '$program' is not on the path and not a file in the repository" }
}

# Roles
function Test-Agent([string]$Name) {
	if ($Name -match '^issue-kit:(.+)$') { return Test-Path -LiteralPath (Join-Path $pluginRoot "agents/$($Matches[1]).md") }
	if ($Name -match ':') { return $null }
	return Test-Path -LiteralPath (Join-Path $RepoRoot ".claude/agents/$Name.md")
}
function Test-Skill([string]$Name) {
	if ($Name -match '^issue-kit:(.+)$') { return Test-Path -LiteralPath (Join-Path $pluginRoot "skills/$($Matches[1])/SKILL.md") }
	if ($Name -match ':') { return $null }
	$skillsDir = Join-Path $RepoRoot '.claude/skills'
	if (-not (Test-Path -LiteralPath $skillsDir)) { return $false }
	foreach ($file in (Get-ChildItem -LiteralPath $skillsDir -Filter SKILL.md -Recurse -Depth 1)) {
		if ($file.Directory.Name -eq $Name) { return $true }
		$head = Get-Content -LiteralPath $file.FullName -TotalCount 10
		if ($head -match "^name:\s*['""]?$([regex]::Escape($Name))['""]?\s*$") { return $true }
	}
	return $false
}
foreach ($role in 'planner', 'developer', 'buildRunner', 'skillRunner', 'architect', 'securityReviewer', 'debugSkill', 'testsSkill') {
	$name = [string]$c.roles[$role]
	if (-not $name) { Write-Check 'OK' "roles.${role}: empty, the workflow skips this role"; continue }
	$isSkill = $role -like '*Skill'
	$found = if ($isSkill) { Test-Skill $name } else { Test-Agent $name }
	$kind = if ($isSkill) { 'skill' } else { 'agent' }
	if ($null -eq $found) { Write-Check 'WARN' "roles.${role}: $kind '$name' belongs to another plugin and is not checked; make sure that plugin is enabled" }
	elseif ($found) { Write-Check 'OK' "roles.${role}: $kind '$name' found" }
	else {
		$pluginPath = if ($isSkill) { "skills/$name/SKILL.md" } else { "agents/$name.md" }
		$hint = if ($name -notmatch ':' -and (Test-Path (Join-Path $pluginRoot $pluginPath))) { " (a plugin $kind needs the prefix: 'issue-kit:$name')" } else { '' }
		Write-Check 'FAIL' "roles.${role}: $kind '$name' not found$hint"
	}
}
if ($c.securityReview.triggers.Count -and -not $c.roles.securityReviewer) {
	Write-Check 'WARN' 'securityReview.triggers is set but roles.securityReviewer is empty: no review runs'
}

# Base branch
& git -C $RepoRoot rev-parse --verify --quiet "refs/heads/$($c.baseBranch)" *> $null
$local = $LASTEXITCODE -eq 0
& git -C $RepoRoot rev-parse --verify --quiet "refs/remotes/origin/$($c.baseBranch)" *> $null
$remote = $LASTEXITCODE -eq 0
if ($local -or $remote) { Write-Check 'OK' "baseBranch: $($c.baseBranch) exists" }
else { Write-Check 'FAIL' "baseBranch: $($c.baseBranch) exists neither locally nor on origin" }

Write-Output ''
Write-Output "Result: $script:errors failed, $script:warnings warning(s)."
if ($script:errors) { exit 1 }
exit 0
