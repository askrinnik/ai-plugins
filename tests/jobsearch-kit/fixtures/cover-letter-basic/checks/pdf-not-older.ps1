# The letter PDF exists and is not older than its .docx.
param([string]$Workspace, [string]$AnswerFile)
$docx = Get-ChildItem (Join-Path $Workspace '2026_10_22_Nordwind_Pay') -Filter '*Cover_Letter*.docx' | Select-Object -First 1
if (-not $docx) { Write-Output 'no letter .docx'; exit 1 }
$pdf = [IO.Path]::ChangeExtension($docx.FullName, '.pdf')
if (-not (Test-Path $pdf)) { Write-Output "$($docx.Name): no PDF"; exit 1 }
if ((Get-Item $pdf).LastWriteTime -lt $docx.LastWriteTime) { Write-Output "$($docx.Name): the PDF is older"; exit 1 }
Write-Output 'ok'
