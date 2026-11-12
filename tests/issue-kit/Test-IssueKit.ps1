<#
.SYNOPSIS
	Runs every test case file of issue-kit (*.Cases.ps1 in this folder) and exits with 1 when any of them fails.

.DESCRIPTION
	The cases start no model session and make no GitHub call.

.EXAMPLE
	pwsh -NoProfile -File tests/issue-kit/Test-IssueKit.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$failed = [System.Collections.Generic.List[string]]::new()
foreach ($file in (Get-ChildItem -Path $PSScriptRoot -Filter '*.Cases.ps1' | Sort-Object Name)) {
	Write-Host "=== $($file.Name)"
	& pwsh -NoProfile -File $file.FullName
	if ($LASTEXITCODE -ne 0) { $failed.Add($file.Name) }
	Write-Host ''
}

if ($failed.Count) {
	Write-Host "Failed: $($failed -join ', ')"
	exit 1
}
Write-Host 'All issue-kit test files passed.'
