<#
.SYNOPSIS
	Test cases of the issue-kit configuration reader (scripts/IssueKitConfig.psm1). Exits with 1 when a case fails.

.EXAMPLE
	pwsh -NoProfile -File tests/issue-kit/Config.Cases.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$pluginRoot = Join-Path $PSScriptRoot '..' '..' 'plugins' 'issue-kit'
Import-Module (Join-Path $pluginRoot 'scripts' 'IssueKitConfig.psm1') -Force

$failures = 0
function Assert-Case {
	param([string]$Name, [bool]$Condition)
	if ($Condition) { Write-Host "PASS  $Name" }
	else { Write-Host "FAIL  $Name"; $script:failures++ }
}

$work = Join-Path ([IO.Path]::GetTempPath()) "issue-kit-config-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
New-Item -ItemType Directory -Force -Path $work | Out-Null
$userFile = Join-Path $work 'user.json'
$repoFile = Join-Path $work 'issue-kit.config.json'

function Read-Config {
	param([string]$User, [string]$Repo)
	Remove-Item -LiteralPath $userFile, $repoFile -ErrorAction SilentlyContinue
	if ($User) { Set-Content -LiteralPath $userFile -Value $User -Encoding utf8 }
	if ($Repo) { Set-Content -LiteralPath $repoFile -Value $Repo -Encoding utf8 }
	return Get-IssueKitConfig -RepoRoot $work -UserFile $userFile
}

function Get-Error {
	param([string]$User, [string]$Repo)
	try { $null = Read-Config -User $User -Repo $Repo; return '' } catch { return $_.Exception.Message }
}

try {
	# Defaults
	$r = Read-Config
	Assert-Case 'defaults load without user and repository files' ($r.Sources.Count -eq 1 -and -not $r.HasRepoFile)
	Assert-Case 'default planner is the plugin agent' ($r.Config.roles.planner -eq 'issue-kit:issue-planner')
	Assert-Case 'default commit check is on' ($r.Config.commitCheck.enabled -eq $true)
	Assert-Case 'default lanes.bug is a list' (@($r.Config.lanes.bug).Count -eq 1 -and $r.Config.lanes.bug[0] -eq 'bug')

	# Merge
	$r = Read-Config -User '{ "shipLanguage": "German", "commands": { "build": "make" } }' -Repo '{ "commands": { "testFull": "make test" } }'
	Assert-Case 'user layer is read' ($r.Config.shipLanguage -eq 'German')
	Assert-Case 'objects merge key by key across layers' ($r.Config.commands.build -eq 'make' -and $r.Config.commands.testFull -eq 'make test')
	Assert-Case 'untouched nested keys keep the default' ($r.Config.commands.format -eq '')
	Assert-Case 'three sources are listed in order' ($r.Sources.Count -eq 3 -and $r.Sources[2] -eq $repoFile -and $r.HasRepoFile)
	$r = Read-Config -User '{ "commands": { "build": "make" } }' -Repo '{ "commands": { "build": "npm run build" } }'
	Assert-Case 'repository layer wins over the user layer' ($r.Config.commands.build -eq 'npm run build')
	$r = Read-Config -Repo '{ "lanes": { "bug": ["defect", "regression"] } }'
	Assert-Case 'a list replaces the earlier list as a whole' (@($r.Config.lanes.bug).Count -eq 2 -and $r.Config.lanes.bug[0] -eq 'defect')
	$r = Read-Config -Repo '{ "securityReview": { "triggers": [] } }'
	Assert-Case 'an empty list is allowed' (@($r.Config.securityReview.triggers).Count -eq 0)
	$r = Read-Config -Repo '{ "commitCheck": { "enabled": false } }'
	Assert-Case 'a true/false value is read' ($r.Config.commitCheck.enabled -eq $false)
	Assert-Case 'Get-IssueKitValue reads a dotted key' ((Get-IssueKitValue -Config $r.Config -Key 'roles.skillRunner') -eq 'issue-kit:skill-runner')

	# Errors name the file and the key
	$e = Get-Error -Repo '{ "commands": { "biuld": "make" } }'
	Assert-Case 'unknown nested key names the file and the key' ($e -like "*issue-kit.config.json*" -and $e -like "*'commands.biuld'*")
	$e = Get-Error -User '{ "colour": "blue" }'
	Assert-Case 'unknown key in the user file names that file' ($e -like "*user.json*" -and $e -like "*'colour'*")
	$e = Get-Error -Repo '{ "baseBranch": 5 }'
	Assert-Case 'wrong type names the key and both types' ($e -like "*'baseBranch' must be a text; found a number*")
	$e = Get-Error -Repo '{ "lanes": { "bug": "bug" } }'
	Assert-Case 'a text where a list is expected is an error' ($e -like "*'lanes.bug' must be a list*")
	$e = Get-Error -Repo '{ "lanes": { "bug": [1] } }'
	Assert-Case 'a list of numbers is an error' ($e -like "*'lanes.bug' must be a list of non-empty texts*")
	$e = Get-Error -Repo '{ "commands": "make" }'
	Assert-Case 'a text where an object is expected is an error' ($e -like "*'commands' must be an object*")
	$e = Get-Error -Repo '{ "profile": { "enabled": "yes" } }'
	Assert-Case 'a text where true/false is expected is an error' ($e -like "*'profile.enabled' must be true or false*")
	$e = Get-Error -Repo '{ "ordering": { "titleCodePattern": "F(\\d+" } }'
	Assert-Case 'an invalid regular expression is an error' ($e -like "*'ordering.titleCodePattern' is not a valid regular expression*")
	$e = Get-Error -Repo '{ "branchPattern": "{slug}" }'
	Assert-Case 'a branch pattern without {n} is an error' ($e -like "*'branchPattern' must contain {n}*")
	$e = Get-Error -Repo '{ "commands": { "testProject": "npm test" } }'
	Assert-Case 'a project test command without {project} is an error' ($e -like "*'commands.testProject' must contain {project}*")
	$e = Get-Error -Repo '{ "roles": { "planner": "" } }'
	Assert-Case 'an empty required role is an error' ($e -like "*'roles.planner' must not be empty*")
	$e = Get-Error -Repo '{ "roles": { "architect": "" } }'
	Assert-Case 'an empty optional role is allowed' ($e -eq '')
	$e = Get-Error -Repo '{ not json'
	Assert-Case 'invalid JSON names the file' ($e -like "*issue-kit.config.json*not valid JSON*")
	$e = Get-Error -Repo '[1, 2]'
	Assert-Case 'a JSON list instead of an object is an error' ($e -like '*must hold a JSON object*')

	# Branch patterns
	$issue = ConvertTo-BranchRegex '{n}-{slug}'
	$batch = ConvertTo-BranchRegex '{first}-{last}-{slug}'
	Assert-Case 'issue branch regex matches and captures the number' ('42-add-export' -match $issue -and $Matches['n'] -eq '42')
	Assert-Case 'batch branch regex captures first and last' ('5-7-cli-options' -match $batch -and $Matches['first'] -eq '5' -and $Matches['last'] -eq '7')
	Assert-Case 'issue branch regex does not match main' (-not ('main' -match $issue))
	$prefixed = ConvertTo-BranchRegex 'issue/{n}-{slug}'
	Assert-Case 'a prefixed pattern escapes literal characters' ('issue/9-x' -match $prefixed -and -not ('issueX9-x' -match $prefixed))

	# Command-line wrapper
	Push-Location $work
	try {
		Set-Content -LiteralPath $repoFile -Value '{ "commands": { "build": "make all" } }' -Encoding utf8
		$out = & pwsh -NoProfile -File (Join-Path $pluginRoot 'scripts' 'Get-IssueKitConfig.ps1') -RepoRoot $work -Key commands.build
		Assert-Case 'Get-IssueKitConfig.ps1 -Key prints a text value' ($LASTEXITCODE -eq 0 -and $out -eq 'make all')
		Set-Content -LiteralPath $repoFile -Value '{ "commandz": {} }' -Encoding utf8
		$out = & pwsh -NoProfile -File (Join-Path $pluginRoot 'scripts' 'Get-IssueKitConfig.ps1') -RepoRoot $work 2>&1
		Assert-Case 'Get-IssueKitConfig.ps1 exits 1 on an invalid file and names the key' ($LASTEXITCODE -eq 1 -and ($out -join ' ') -like "*'commandz'*")
	}
	finally { Pop-Location }
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
