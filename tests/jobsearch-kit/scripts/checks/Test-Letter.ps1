<#
.SYNOPSIS
  Checks a cover letter (cover-letter.md) of a test workspace: front matter, one line per paragraph, body length,
  and no numbers derived from dates. A "script" check of the skill fixtures; exit code 1 on a problem.

.DESCRIPTION
    pwsh -File Test-Letter.ps1 -Workspace <ws> [-Letter <glob>] [-MinWords 250] [-MaxWords 350]

  - Front matter with "output" and "date".
  - One line per paragraph: every block (text between blank lines) has one line, except the sign-off block
    ("Kind regards," and the following lines).
  - Body words: the blocks without the front matter, the greeting (first block) and the sign-off block.
  - Derived numbers (regression of 2026-10-22, "the last seven years in payments"): every "<N> years", "the last
    <N>" and "since <year>" of the body must appear in the same form in MyProfile/candidate_facts.md. Number words
    count as numbers.
#>
param(
  [Parameter(Mandatory)][string]$Workspace,
  [string]$AnswerFile,
  [string]$Letter = '*/cover-letter.md',
  [int]$MinWords = 250,
  [int]$MaxWords = 350
)
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path $Workspace).Path.TrimEnd('\') + '\'
$files = @(Get-ChildItem $Workspace -Recurse -File -Filter 'cover-letter.md' |
    Where-Object { ($_.FullName.Substring($root.Length) -replace '\\', '/') -like $Letter })
if (-not $files.Count) { Write-Output "no letter matches $Letter"; exit 1 }

$words = @{ one = 1; two = 2; three = 3; four = 4; five = 5; six = 6; seven = 7; eight = 8; nine = 9; ten = 10; eleven = 11; twelve = 12; fifteen = 15; twenty = 20 }
function ConvertTo-Number([string]$t) { if ($words.ContainsKey($t.ToLower())) { $words[$t.ToLower()] } else { [int]$t } }
$num = '(\d+|' + ($words.Keys -join '|') + ')'

# Normalized number phrases of a text: "10 years", "last 7", "since 2015".
function Get-NumberPhrases([string]$text) {
  foreach ($m in [regex]::Matches($text, "\b$num\s*\+?\s*(?:years?|yrs)\b", 'IgnoreCase')) { "$(ConvertTo-Number $m.Groups[1].Value) years" }
  foreach ($m in [regex]::Matches($text, "\b(?:the\s+)?(?:last|past)\s+$num\b", 'IgnoreCase')) { "last $(ConvertTo-Number $m.Groups[1].Value)" }
  foreach ($m in [regex]::Matches($text, '\bsince\s+((?:19|20)\d\d)\b', 'IgnoreCase')) { "since $($m.Groups[1].Value)" }
}

$facts = Get-Content (Join-Path $Workspace 'MyProfile\candidate_facts.md') -Raw
$backed = @(Get-NumberPhrases $facts | Sort-Object -Unique)
$problems = New-Object System.Collections.Generic.List[string]
foreach ($f in $files) {
  $rel = $f.FullName.Substring($root.Length)
  $text = (Get-Content $f.FullName -Raw) -replace "`r`n", "`n"
  $fm = [regex]::Match($text, '\A---\n(.*?)\n---\n', 'Singleline')
  if (-not $fm.Success) { $problems.Add("${rel}: no front matter at the top") }
  else {
    foreach ($k in 'output', 'date') { if ($fm.Groups[1].Value -notmatch "(?m)^${k}:\s*\S") { $problems.Add("${rel}: front matter has no '$k'") } }
    $text = $text.Substring($fm.Length)
  }
  $blocks = @($text -split '\n\s*\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $signOff = [array]::FindIndex([string[]]$blocks, [Predicate[string]] { param($b) $b -match '^(Kind regards|Best regards|Regards|Sincerely|Yours sincerely|With best regards)' })
  if ($signOff -lt 0) { $problems.Add("${rel}: no sign-off block ('Kind regards,')"); $signOff = $blocks.Count }
  for ($i = 0; $i -lt $signOff; $i++) {
    if (($blocks[$i] -split '\n').Count -gt 1) { $problems.Add("${rel}: paragraph $($i + 1) is hard-wrapped over $(($blocks[$i] -split '\n').Count) lines: '$($blocks[$i].Substring(0, [math]::Min(60, $blocks[$i].Length)))...'") }
  }
  $body = @($blocks[1..([math]::Max(1, $signOff) - 1)] | Where-Object { $_ }) -join "`n"
  if ($signOff -le 1) { $body = '' }
  $count = @([regex]::Matches($body, "[\p{L}\p{N}][\p{L}\p{N}'’.,%+-]*")).Count
  if ($count -lt $MinWords -or $count -gt $MaxWords) { $problems.Add("${rel}: body has $count words, expected $MinWords-$MaxWords") }
  foreach ($p in @(Get-NumberPhrases $body | Sort-Object -Unique)) {
    if ($p -notin $backed) { $problems.Add("${rel}: '$p' is not stated in candidate_facts.md (derived number?)") }
  }
  Write-Output "${rel}: $count body words, $signOff paragraph(s) before the sign-off"
}
if ($problems.Count) {
  $problems | ForEach-Object { Write-Output "PROBLEM: $_" }
  exit 1
}
Write-Output 'letter ok'
