<#
.SYNOPSIS
	Prints the merged issue-kit configuration of the current repository as JSON, or one value of it.

.DESCRIPTION
	Reads the three layers (plugin defaults, the user file in the Claude config folder, issue-kit.config.json in the
	repository root), validates them and prints the result. An invalid file stops with exit code 1 and a message that
	names the file and the key.

.PARAMETER Key
	A dotted key ("commands.build"). Prints only that value: a text as it is, anything else as JSON.

.PARAMETER Sources
	Also print the files that were read, before the JSON.

.PARAMETER RepoRoot
	The repository root; defaults to the git root of the current folder.

.EXAMPLE
	pwsh -NoProfile -File <plugin>/scripts/Get-IssueKitConfig.ps1

.EXAMPLE
	pwsh -NoProfile -File <plugin>/scripts/Get-IssueKitConfig.ps1 -Key commands.build
#>
[CmdletBinding()]
param(
	[string]$Key,
	[switch]$Sources,
	[string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Import-Module (Join-Path $PSScriptRoot 'IssueKitConfig.psm1') -Force

try {
	$arguments = @{}
	if ($RepoRoot) { $arguments.RepoRoot = $RepoRoot }
	$result = Get-IssueKitConfig @arguments
	if ($Key) {
		$value = Get-IssueKitValue -Config $result.Config -Key $Key
		if ($value -is [string] -or $value -is [bool]) { Write-Output $value }
		else { Write-Output (ConvertTo-Json -InputObject $value -Depth 10 -Compress) }
		exit 0
	}
	if ($Sources) {
		Write-Output "Files read (a later one wins):"
		$result.Sources | ForEach-Object { Write-Output "  $_" }
		if (-not $result.HasRepoFile) { Write-Output "  (no repository file at $($result.RepoFile))" }
	}
	Write-Output (ConvertTo-Json -InputObject $result.Config -Depth 10)
}
catch {
	[Console]::Error.WriteLine("issue-kit configuration error: $($_.Exception.Message)")
	exit 1
}
