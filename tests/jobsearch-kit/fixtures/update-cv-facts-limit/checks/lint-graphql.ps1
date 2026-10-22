# The new GraphQL rule: an honest negation passes cv.js --lint, a claim fails.
param([string]$Workspace, [string]$AnswerFile)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
$cv = Join-Path $repo 'plugins\jobsearch-kit\scripts\cv.js'
$dir = Join-Path ([IO.Path]::GetTempPath()) ("jobsearch-tests\lint-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $dir | Out-Null
try {
  $honest = Join-Path $dir 'honest.md'
  $claim = Join-Path $dir 'claim.md'
  Set-Content $honest 'I have not worked with GraphQL, but I design REST APIs every day.' -Encoding UTF8
  Set-Content $claim 'I built GraphQL APIs for the payment platform.' -Encoding UTF8
  $out = & node $cv --lint $honest --root $Workspace 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0 -or $out -match 'WARNING') { Write-Output "the honest negation failed the lint: $out"; exit 1 }
  $out = & node $cv --lint $claim --root $Workspace 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) { Write-Output "the claim passed the lint: $out"; exit 1 }
  Write-Output 'honest negation passes, claim fails'
}
finally {
  Remove-Item $dir -Recurse -Force
}
