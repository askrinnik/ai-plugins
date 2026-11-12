<#
.SYNOPSIS
	Test cases of the issue-kit commit message hook (hooks/Test-CommitMessageHook.ps1) in temporary git repositories.
	Exits with 1 when a case fails.

.DESCRIPTION
	Each case makes a commit in a temporary repository and passes the hook input of a "git commit" tool call on
	standard input. The repositories have no GitHub remote, so the hook cannot read issue titles and compares only the
	format; that is enough to see whether the hook checks the commit at all.

.EXAMPLE
	pwsh -NoProfile -File tests/issue-kit/Hook.Cases.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$hook = Join-Path $PSScriptRoot '..' '..' 'plugins' 'issue-kit' 'hooks' 'Test-CommitMessageHook.ps1'

$failures = 0
function Assert-Case {
	param([string]$Name, [bool]$Condition)
	if ($Condition) { Write-Host "PASS  $Name" }
	else { Write-Host "FAIL  $Name"; $script:failures++ }
}

$work = Join-Path ([IO.Path]::GetTempPath()) "issue-kit-hook-$([guid]::NewGuid().ToString('N').Substring(0, 8))"

function New-Repository {
	<# Creates a repository on the given branch with one commit of the given message, and an optional config file. #>
	param([string]$Name, [string]$Branch, [string]$Message, [string]$Config)
	$dir = Join-Path $work $Name
	New-Item -ItemType Directory -Force -Path $dir | Out-Null
	& git -C $dir init -q -b $Branch
	& git -C $dir config user.name 'Test User'
	& git -C $dir config user.email 'test@example.com'
	& git -C $dir config commit.gpgsign false
	if ($Config) { Set-Content -LiteralPath (Join-Path $dir 'issue-kit.config.json') -Value $Config -Encoding utf8 }
	Set-Content -LiteralPath (Join-Path $dir 'file.txt') -Value 'content' -Encoding utf8
	& git -C $dir add -A
	$messageFile = Join-Path $work "$Name-message.txt"
	[IO.File]::WriteAllText($messageFile, $Message)
	& git -C $dir commit -q -F $messageFile
	return $dir
}

function Invoke-Hook {
	param([string]$Directory, [string]$Command = 'git commit -F message.txt')
	$hookInput = @{ cwd = $Directory; tool_name = 'Bash'; tool_input = @{ command = $Command } } | ConvertTo-Json -Compress
	$errorFile = Join-Path $work 'stderr.txt'
	$out = $hookInput | & pwsh -NoProfile -File $hook 2> $errorFile
	return [pscustomobject]@{
		Exit   = $LASTEXITCODE
		Output = ($out -join "`n")
		Error  = $(if (Test-Path $errorFile) { Get-Content -LiteralPath $errorFile -Raw } else { '' })
	}
}

$bad = "Did some work`nmore text"
$good = "- Fix a typo`n- Update the notes"

try {
	New-Item -ItemType Directory -Force -Path $work | Out-Null

	$dir = New-Repository -Name 'no-config' -Branch 'main' -Message $bad
	$r = Invoke-Hook $dir
	Assert-Case 'no issue-kit.config.json: the hook prints nothing for a bad message' ($r.Exit -eq 0 -and -not $r.Output -and -not $r.Error)

	$dir = New-Repository -Name 'enabled' -Branch 'main' -Message $bad -Config '{}'
	$r = Invoke-Hook $dir
	$decision = if ($r.Output) { $r.Output | ConvertFrom-Json } else { $null }
	Assert-Case 'config present: a bad message gives a block decision' ($r.Exit -eq 0 -and $decision.decision -eq 'block')
	Assert-Case 'the block reason names the skill and the line' ($decision.reason -like '*issue-kit:git-commit*' -and $decision.reason -like "*Line 1 must be an action*")

	$dir = New-Repository -Name 'good' -Branch 'main' -Message $good -Config '{}'
	$r = Invoke-Hook $dir
	Assert-Case 'config present: a good message prints nothing' ($r.Exit -eq 0 -and -not $r.Output)

	$dir = New-Repository -Name 'disabled' -Branch 'main' -Message $bad -Config '{ "commitCheck": { "enabled": false } }'
	$r = Invoke-Hook $dir
	Assert-Case 'commitCheck.enabled false: the hook prints nothing' ($r.Exit -eq 0 -and -not $r.Output)

	$dir = New-Repository -Name 'invalid' -Branch 'main' -Message $bad -Config '{ "commitChek": {} }'
	$r = Invoke-Hook $dir
	Assert-Case 'invalid config: no block, a warning that names the key' ($r.Exit -eq 0 -and -not $r.Output -and $r.Error -like "*'commitChek'*")

	$dir = New-Repository -Name 'base' -Branch 'develop' -Message "#5 Some title`n`n- Do it" -Config '{ "baseBranch": "develop" }'
	$r = Invoke-Hook $dir
	Assert-Case 'configured base branch: an issue header there is blocked' ($r.Output -like '*not tied to an issue*')

	$dir = New-Repository -Name 'other-command' -Branch 'main' -Message $bad -Config '{}'
	$r = Invoke-Hook $dir -Command 'git log -1'
	Assert-Case 'a command that is not git commit is ignored' ($r.Exit -eq 0 -and -not $r.Output)

	$parent = New-Item -ItemType Directory -Force -Path (Join-Path $work 'outside')
	$dir = New-Repository -Name 'nested' -Branch 'main' -Message $bad -Config '{}'
	$r = Invoke-Hook $parent.FullName -Command "git -C `"$dir`" commit -F m.txt"
	Assert-Case 'git -C <path> commit checks the repository at that path' ($r.Output -like '*"decision":"block"*')
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
