<#
.SYNOPSIS
  Checks a workspace made by init-workspace: no data of the fictional seed candidate, no placeholder left, every
  fact marked "confirmed <date>" or "from the CV, <date>". A "script" check of the skill fixtures; exit code 1 on a
  problem.

.DESCRIPTION
    pwsh -File Test-NewWorkspace.ps1 -Workspace <ws> [-Root <subfolder>]
#>
param(
  [Parameter(Mandatory)][string]$Workspace,
  [string]$AnswerFile,
  [string]$Root = '.',
  [switch]$AllowSeedCandidate
)
$ErrorActionPreference = 'Stop'
$ws = (Resolve-Path (Join-Path $Workspace $Root)).Path
$problems = New-Object System.Collections.Generic.List[string]

# 1. No data of the fictional template candidate (Jordan Sample).
$seedMarks = @('Your_Name', 'Your Name') + $(if ($AllowSeedCandidate) { @() } else { @('Jordan Sample', 'jordan.sample', 'Example Payments', 'Sample Retail', 'Ledger demo') })
$texts = Get-ChildItem $ws -Recurse -File -Include *.md, *.yaml, *.yml, *.json |
  Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.Name -notlike 'base-cv*' }
foreach ($f in $texts) {
  $t = Get-Content $f.FullName -Raw
  foreach ($m in $seedMarks) { if ($t -match [regex]::Escape($m)) { $problems.Add("$($f.Name): template data '$m'") } }
}

# 2. No placeholder <...> outside comments.
$files = @('CLAUDE.md', 'MyProfile\candidate_facts.md', 'MyProfile\cv\cv_master.yaml', 'MyProfile\cv\profile_full.yaml',
  'MyProfile\cv\cv_rules.yaml', 'MyProfile\application_defaults.yaml') | ForEach-Object { Join-Path $ws $_ }
foreach ($file in $files) {
  if (-not (Test-Path $file)) { $problems.Add("missing: $file"); continue }
  $n = 0
  foreach ($line in Get-Content $file) {
    $n++
    if ($line -match '^\s*#' -and $file -like '*.y*ml') { continue }
    # The facts header may describe the format: "confirmed <date>", "from the CV, <date>".
    $clean = $line -replace '<!--.*?-->', '' -replace '<(https?|mailto):[^>]*>', '' -replace '(confirmed|from the CV,?)\s+<date>', ''
    if ($clean -match '<[A-Za-z][^<>]*>') { $problems.Add("$(Split-Path $file -Leaf):${n}: placeholder $($Matches[0])") }
  }
}

# 3. Every fact (a bullet with its continuation lines) has a source and a date.
$facts = Join-Path $ws 'MyProfile\candidate_facts.md'
if (Test-Path $facts) {
  $items = New-Object System.Collections.Generic.List[string]
  $cur = $null
  foreach ($line in Get-Content $facts) {
    if ($line -match '^- ') { if ($cur) { $items.Add($cur) }; $cur = $line; continue }
    if ($cur -and $line -match '^\s{2,}\S') { $cur += ' ' + $line.Trim(); continue }
    if ($cur) { $items.Add($cur); $cur = $null }
  }
  if ($cur) { $items.Add($cur) }
  if (-not $items.Count) { $problems.Add('candidate_facts.md has no facts') }
  foreach ($i in $items) {
    if ($i -notmatch '(confirmed|from the CV)[^)]*\d{4}-\d\d-\d\d') { $problems.Add("fact without 'confirmed <date>' or 'from the CV, <date>': $($i.Substring(0, [math]::Min(90, $i.Length)))") }
  }
  Write-Output "$($items.Count) fact(s) checked"
}

if ($problems.Count) { $problems | ForEach-Object { Write-Output "PROBLEM: $_" }; exit 1 }
Write-Output 'workspace ok'
