<#
.SYNOPSIS
  Collects one test run: judges turns that have no score yet, reads the session metrics from the transcripts, writes
  the rows of run-history.csv and the report reports\<run id>.md.

.DESCRIPTION
    pwsh -File tests\jobsearch-kit\scripts\Collect-Tests.ps1 [-Run <runs\<run id> folder>] [-JudgeModel sonnet]

  Run-Tests.ps1 calls it at the end of every run. Call it yourself to rebuild the history rows and the report of a
  run (default: the latest run). Rows of the same run id are replaced, so it is safe to run twice.
#>
param(
  [string]$Run,
  [string]$JudgeModel = 'sonnet'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Session.ps1')
. (Join-Path $PSScriptRoot 'lib\Collect.ps1')

if (-not $Run) {
  $Run = Get-ChildItem (Join-Path $script:TestsDir 'runs') -Directory | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName
  if (-not $Run) { throw 'No run in tests\jobsearch-kit\runs' }
}
$info = Get-Content (Join-Path $Run 'run.json') -Raw | ConvertFrom-Json -DateKind String
$results = @(Get-ChildItem $Run -Recurse -Filter 'result.json' | Sort-Object FullName | ForEach-Object {
    $r = Get-Content $_.FullName -Raw | ConvertFrom-Json
    if ($r.status -in 'running', $null) { $r = Complete-Result -ResultFile $_.FullName -JudgeModel $JudgeModel }
    $r
  })
$rows = @($results | ForEach-Object { ConvertTo-HistoryRow $info $_ })
Update-History -Rows $rows -RunId $info.runId
$report = Write-Report -Run $info -Results $results

$pass = @($results | Where-Object status -eq 'pass').Count
$skip = @($results | Where-Object status -eq 'skipped').Count
Write-Output ''
Write-Output "Run $($info.runId): $pass of $($results.Count) passed$(if ($skip) { ", $skip skipped" })."
Write-Output "History: $script:HistoryFile"
Write-Output "Report:  $report"
Get-Content $report | Select-Object -Skip 6 | Where-Object { $_ -match '^\|' } | ForEach-Object { Write-Output $_ }
