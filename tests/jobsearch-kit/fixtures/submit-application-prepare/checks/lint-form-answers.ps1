# If the session saved form-answers.md, it must pass cv.js --lint with the workspace rules.
param([string]$Workspace, [string]$AnswerFile)
$file = Join-Path $Workspace '2026_10_20_ExampleBank\form-answers.md'
if (-not (Test-Path $file)) { Write-Output 'no form-answers.md (allowed)'; exit 0 }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
$out = & node (Join-Path $repo 'plugins\jobsearch-kit\scripts\cv.js') --lint $file --root $Workspace 2>&1 | Out-String
Write-Output $out.Trim()
exit $LASTEXITCODE
