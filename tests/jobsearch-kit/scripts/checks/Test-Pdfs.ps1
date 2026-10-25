<#
.SYNOPSIS
  Checks the PDFs of an application folder of a test workspace: every .docx has a PDF that is not older, and the CV
  PDF keeps every contact link of the master. A "script" check of the skill fixtures; exit code 1 on a problem.

.DESCRIPTION
    pwsh -File Test-Pdfs.ps1 -Workspace <ws> -Folder <application folder> [-CvPattern '*_CV_*']
#>
param(
  [Parameter(Mandatory)][string]$Workspace,
  [string]$AnswerFile,
  [Parameter(Mandatory)][string]$Folder,
  [string]$CvPattern = '*_CV_*'
)
$ErrorActionPreference = 'Stop'
# The folder may be a mask ({{date}}_Example*Bank*): take the first folder that matches.
$dir = @(Resolve-Path (Join-Path $Workspace $Folder) -ErrorAction SilentlyContinue | Select-Object -First 1)[0].Path
if (-not $dir) { Write-Output "PROBLEM: no folder matches $Folder"; exit 1 }
$problems = New-Object System.Collections.Generic.List[string]
$docxs = @(Get-ChildItem $dir -Filter '*.docx' -File | Where-Object Name -notlike '~$*')
if (-not $docxs.Count) { $problems.Add("no .docx in $Folder") }
foreach ($d in $docxs) {
  $pdf = [IO.Path]::ChangeExtension($d.FullName, '.pdf')
  if (-not (Test-Path $pdf)) { $problems.Add("$($d.Name): no PDF"); continue }
  if ((Get-Item $pdf).LastWriteTime -lt $d.LastWriteTime) { $problems.Add("$($d.Name): the PDF is older than the .docx") }
  else { Write-Output "$([IO.Path]::GetFileName($pdf)): ok" }
}

# Contact links of the master header (url fields) must be in the CV PDF.
$master = Get-Content (Join-Path $Workspace 'MyProfile\cv\cv_master.yaml') -Raw
$urls = @([regex]::Matches(($master -split '(?m)^titles:')[0], '(?m)^\s+url:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value })
$cvPdf = Get-ChildItem $dir -Filter '*.pdf' -File | Where-Object Name -like "$CvPattern" | Select-Object -First 1
if (-not $cvPdf) { $problems.Add("no CV PDF matching $CvPattern") }
else {
  $raw = [IO.File]::ReadAllText($cvPdf.FullName, [Text.Encoding]::GetEncoding(28591))
  $links = @([regex]::Matches($raw, '/URI\s*\(([^)]*)\)') | ForEach-Object { $_.Groups[1].Value })
  foreach ($u in $urls) {
    if ($links -notcontains $u) { $problems.Add("$($cvPdf.Name): contact link $u missing (links: $($links -join ', '))") }
  }
  Write-Output "$($cvPdf.Name): $($links.Count) link(s), $($urls.Count) contact link(s) expected"
}
if ($problems.Count) { $problems | ForEach-Object { Write-Output "PROBLEM: $_" }; exit 1 }
Write-Output 'pdfs ok'
